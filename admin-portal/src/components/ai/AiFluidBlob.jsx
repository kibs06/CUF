import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useReducedMotion } from 'motion/react'

import {
  MIC_BAR_COUNT,
  MIC_BAR_WEIGHTS,
  blobUniformColors,
  frameTimeSeconds,
  micBarHeights,
  micBarMotion,
  micOrbSize,
  paletteCount,
  resolveBlobProps,
  shouldAnimate,
  variantMotion,
} from '../../lib/aiBlob.js'
import { FRAGMENT_SHADER, VERTEX_SHADER } from './blobShader.js'

// ─── AiFluidBlob ───────────────────────────────────────────────────
//
// A multi-strand chromatic liquid-wave energy field under a glass refraction
// lens — the AI voice-assistant surface, in hand-written WebGL, with the voice
// orb at its centre.
//
// **The public API is the documented one** (`size`, `colors`, `count`, `variant`,
// `glass`), and everything decidable about it lives in `lib/aiBlob.js` so it can
// be tested without a GL context. What is left here is the part that cannot be
// tested and therefore has to be *correct by construction*: one context, one
// program, one quad, one loop, and a cleanup that leaves nothing behind — this
// component is mounted twice on the AI page (once to demo, five times for the
// states) and a leak per mount would be a leak per navigation.
//
// ⚠️ Three deliberate hard choices, each one a browser fact rather than a taste:
//
//   • **WebGL1 (ES 1.00), and no dependency.** The portal's only graphics
//     libraries are Tailwind and `recharts`; adding `ogl` for one panel would put
//     a 3D engine in the bundle to draw a shader on a quad. The one thing ES 1.00
//     costs is index-by-expression into a uniform array, which the shader writes
//     as a bounded search instead.
//   • **The render loop stops.** It stops for `prefers-reduced-motion` (the field
//     is drawn once, frozen at a composed phase), for a canvas scrolled out of
//     view, and for a hidden document. A dashboard left open in a background tab
//     should not be a space heater.
//   • **No WebGL means a fallback, not a blank box.** Contexts are refused on
//     locked-down machines and in some headless browsers; the component degrades
//     to stacked radial gradients in the same palette, marked with
//     `data-blob-fallback` so the difference is visible in the DOM rather than
//     only in the pixels.

function createProgram(gl, vertexSource, fragmentSource) {
  const compile = (type, source) => {
    const shader = gl.createShader(type)
    gl.shaderSource(shader, source)
    gl.compileShader(shader)
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      const log = gl.getShaderInfoLog(shader)
      gl.deleteShader(shader)
      throw new Error(`AI blob shader failed to compile: ${log}`)
    }
    return shader
  }

  const program = gl.createProgram()
  const vertex = compile(gl.VERTEX_SHADER, vertexSource)
  const fragment = compile(gl.FRAGMENT_SHADER, fragmentSource)
  gl.attachShader(program, vertex)
  gl.attachShader(program, fragment)
  gl.linkProgram(program)
  gl.deleteShader(vertex)
  gl.deleteShader(fragment)

  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    const log = gl.getProgramInfoLog(program)
    gl.deleteProgram(program)
    throw new Error(`AI blob program failed to link: ${log}`)
  }

  return program
}

/** Everything the draw call needs, computed once per prop change rather than per
 *  frame — the palette is a 36-float upload and there is no reason to rebuild it
 *  sixty times a second. */
function drawState(resolved) {
  return {
    ...resolved,
    motion: variantMotion(resolved.variant),
    uniformColors: blobUniformColors(resolved.colors),
    paletteCount: paletteCount(resolved.colors),
  }
}

export function AiFluidBlob({ size, colors, count, variant, glass, className = '', style }) {
  const resolved = resolveBlobProps({ size, colors, count, variant, glass })
  const prefersReducedMotion = useReducedMotion()

  const canvasRef = useRef(null)
  const wrapRef = useRef(null)
  const stateRef = useRef(null)
  const apiRef = useRef({ draw: null })
  const visibleRef = useRef(true)

  const [failed, setFailed] = useState(false)

  if (stateRef.current === null) stateRef.current = drawState(resolved)

  // The loop reads the *latest* props without being torn down and rebuilt for
  // them: re-creating a GL context on every keystroke in the page's size slider
  // would exhaust the browser's context budget within a few seconds of dragging.
  //     The GPU is told nothing new when the voice orb's bars move: those are DOM,
  //     animated by CSS, because a sphere that redrew sixty times a second to jog
  //     three spans would be a space heater with a highlight.
  const { size: pixels, count: strands, variant: state, glass: hasGlass } = resolved
  const paletteKey = resolved.colors.join(',')

  const motionRef = useRef(Boolean(prefersReducedMotion))

  useEffect(() => {
    stateRef.current = drawState({
      size: pixels,
      colors: paletteKey.split(','),
      count: strands,
      variant: state,
      glass: hasGlass,
    })
    motionRef.current = Boolean(prefersReducedMotion)
    // A stopped loop still has to show the change, so a prop edit draws one frame.
    apiRef.current.draw?.()
  }, [pixels, strands, state, hasGlass, paletteKey, prefersReducedMotion])

  const draw = useCallback(() => {
    const canvas = canvasRef.current
    const gl = canvas?.getContext('webgl')
    const api = apiRef.current
    if (!canvas || !gl || !api.program) return

    const next = stateRef.current
    const dpr = Math.min(window.devicePixelRatio || 1, 2)
    const devicePixels = Math.max(1, Math.round(next.size * dpr))
    if (canvas.width !== devicePixels) canvas.width = devicePixels
    if (canvas.height !== devicePixels) canvas.height = devicePixels

    gl.viewport(0, 0, canvas.width, canvas.height)
    // ⚠️ The canvas has an alpha channel and starts every frame transparent: the
    // field is light drawn *over* the page, so a frame that is not cleared would
    // accumulate into a solid disc of the brightest colour the blob ever reached.
    gl.clearColor(0, 0, 0, 0)
    gl.clear(gl.COLOR_BUFFER_BIT)
    gl.useProgram(api.program)
    gl.uniform2f(api.uniforms.resolution, canvas.width, canvas.height)
    gl.uniform1f(api.uniforms.time, frameTimeSeconds({ elapsedMs: performance.now() - api.startedAt, reducedMotion: motionRef.current }))
    gl.uniform3fv(api.uniforms.colors, next.uniformColors)
    gl.uniform1i(api.uniforms.paletteCount, next.paletteCount)
    gl.uniform1i(api.uniforms.count, next.count)
    gl.uniform1f(api.uniforms.energy, next.motion.energy)
    gl.uniform1f(api.uniforms.spin, next.motion.spin)
    gl.uniform1f(api.uniforms.wobble, next.motion.wobble)
    gl.uniform1f(api.uniforms.pulse, next.motion.pulse)
    gl.uniform1f(api.uniforms.spread, next.motion.spread)
    gl.uniform1f(api.uniforms.glass, next.glass ? 1 : 0)
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4)
  }, [])

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return undefined

    // ⚠️ `alpha: true` and `premultipliedAlpha: false`, because the shader writes
    // straight alpha and the page shows through it — the blob has to sit on light
    // surfaces as well as dark ones, and a canvas that claimed to be opaque would
    // paint a black square over the first white card it was dropped into.
    const gl = canvas.getContext('webgl', {
      alpha: true,
      premultipliedAlpha: false,
      antialias: true,
      depth: false,
      powerPreference: 'high-performance',
    })

    if (!gl || gl.isContextLost()) {
      console.warn('[AiFluidBlob] no WebGL context — drawing the static fallback')
      setFailed(true)
      return undefined
    }

    let program
    let buffer
    try {
      program = createProgram(gl, VERTEX_SHADER, FRAGMENT_SHADER)
      buffer = gl.createBuffer()
      gl.bindBuffer(gl.ARRAY_BUFFER, buffer)
      gl.bufferData(
        gl.ARRAY_BUFFER,
        new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]),
        gl.STATIC_DRAW,
      )
      const position = gl.getAttribLocation(program, 'aPosition')
      gl.enableVertexAttribArray(position)
      gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0)
    } catch (error) {
      // A refused context and a shader that will not compile are the same visitor
      // experience, so they take the same path out — but they are not the same bug,
      // so the reason is logged rather than swallowed. The fallback is silent, and
      // a silent fallback that hides a broken shader is worse than a loud one.
      console.warn('[AiFluidBlob] falling back to the static gradient:', error?.message ?? error)
      setFailed(true)
      return undefined
    }

    const uniform = (name) => gl.getUniformLocation(program, name)
    apiRef.current = {
      program,
      startedAt: performance.now(),
      // `draw` is replaced below; the caller's `draw` closes over the program via
      // this object, which is why the context can be created after first paint.
      uniforms: {
        resolution: uniform('uResolution'),
        time: uniform('uTime'),
        colors: uniform('uColors'),
        paletteCount: uniform('uPaletteCount'),
        count: uniform('uCount'),
        energy: uniform('uEnergy'),
        spin: uniform('uSpin'),
        wobble: uniform('uWobble'),
        pulse: uniform('uPulse'),
        spread: uniform('uSpread'),
        glass: uniform('uGlass'),
      },
    }

    let frame = 0
    let running = false

    const wantsFrames = () =>
      shouldAnimate({ reducedMotion: motionRef.current, visible: visibleRef.current })

    // The phase comes from `startedAt` rather than from the frame timestamp, so a
    // tab that was hidden for a minute resumes where it stopped instead of jumping
    // a minute forward.
    const tick = () => {
      if (!wantsFrames()) {
        running = false
        return
      }
      frame = requestAnimationFrame(tick)
      draw()
    }

    const start = () => {
      if (running || !wantsFrames()) return
      running = true
      frame = requestAnimationFrame(tick)
    }

    // One frame regardless of the loop: this is what a reduced-motion visitor,
    // and a prop change on a stopped loop, actually see.
    apiRef.current.draw = () => {
      if (wantsFrames()) start()
      else draw()
    }

    const onVisibilityChange = () => {
      visibleRef.current = document.visibilityState !== 'hidden'
      apiRef.current.draw()
    }

    const observer =
      typeof IntersectionObserver === 'undefined'
        ? null
        : new IntersectionObserver((entries) => {
            visibleRef.current = entries.some((entry) => entry.isIntersecting)
            apiRef.current.draw()
          })

    observer?.observe(canvas)
    document.addEventListener('visibilitychange', onVisibilityChange)

    apiRef.current.draw()

    return () => {
      cancelAnimationFrame(frame)
      running = false
      observer?.disconnect()
      document.removeEventListener('visibilitychange', onVisibilityChange)
      apiRef.current = { draw: null }
      gl.deleteBuffer(buffer)
      gl.deleteProgram(program)
      // ⚠️ The context is deliberately NOT released here, even though the AI page
      // mounts six of these and browsers cap how many a document may hold. A lost
      // context cannot be re-acquired on the same canvas — `getContext` hands back
      // the same dead object forever — and React 18's StrictMode runs every effect
      // twice in development, so releasing it would break the second mount rather
      // than free anything. The canvas element goes with the unmount and its
      // context is reclaimed with it; the buffers and the program are explicitly
      // deleted above, which is the part that would otherwise accumulate.
    }
  }, [draw])

  const label = `AI assistant visual — ${resolved.variant}`

  // ⚠️ The fallback is not a placeholder for a broken component: it is the whole
  // component on a machine that refuses WebGL, so it uses the caller's palette and
  // stays transparent, the way the shader does. It is *not* a sphere — stacking
  // gradients into one would claim a lit body this path cannot draw — so it reads
  // as the same light in the same palette and says so through `data-blob-fallback`.
  const fallbackStyle = useMemo(() => {
    const layers = resolved.colors.map((colour, index) => {
      const angle = (index / resolved.colors.length) * Math.PI * 2
      const x = 50 + Math.round(Math.cos(angle) * 16)
      const y = 50 + Math.round(Math.sin(angle) * 16)
      return `radial-gradient(circle at ${x}% ${y}%, ${colour}cc 0%, transparent 55%)`
    })
    return {
      width: resolved.size,
      height: resolved.size,
      backgroundImage: [
        'radial-gradient(circle at 50% 50%, rgba(255,255,255,0.55) 0%, rgba(255,255,255,0) 62%)',
        ...layers,
      ].join(', '),
      ...style,
    }
  }, [resolved.colors, resolved.size, style])

  // ─── The voice orb ────────────────────────────────────────────────
  //
  // Three bars in a frosted disc, sized and timed from `lib/aiBlob.js`. Frozen at
  // their resting height under reduced motion — the state is still legible, it
  // just does not move, which is the point of the preference.
  const orb = micOrbSize(resolved.size)
  const orbMotion = micBarMotion(resolved.variant)
  const restingHeights = micBarHeights(resolved.variant)
  const barWidth = Math.max(1, Math.round(orb * 0.018))

  const orbDisc = (
    <span
      aria-hidden="true"
      data-blob-orb="true"
      className="pointer-events-none relative z-10 flex shrink-0 items-center justify-center rounded-full border border-white/60 bg-white/15 backdrop-blur-2xl"
      style={{
        width: orb,
        height: orb,
        boxShadow: '0 8px 32px rgba(0,0,0,0.25), inset 0 2px 6px rgba(255,255,255,0.7)',
      }}
    >
      <span className="flex items-center justify-center gap-[3px]">
        {Array.from({ length: MIC_BAR_COUNT }, (_, index) => (
          <span
            key={index}
            className="rounded-full bg-white"
            style={{
              width: barWidth,
              height: orb,
              transform: `scaleY(${restingHeights[index]})`,
              '--ai-mic-lo': restingHeights[index],
              '--ai-mic-hi': orbMotion.high * MIC_BAR_WEIGHTS[index],
              animation: prefersReducedMotion
                ? undefined
                : `ai-mic-bar ${orbMotion.durationMs}ms ease-in-out ${orbMotion.offsetsMs[index]}ms infinite`,
            }}
          />
        ))}
      </span>
    </span>
  )

  if (failed) {
    return (
      <div
        ref={wrapRef}
        role="img"
        aria-label={label}
        data-blob-fallback="true"
        className={`relative inline-flex shrink-0 items-center justify-center overflow-hidden rounded-full ${className}`}
        style={fallbackStyle}
      >
        {orbDisc}
      </div>
    )
  }

  // The wrapper is the component's box; the canvas fills it and the orb sits on
  // top of the canvas' centre. `overflow-hidden` is what clips the outer halo to
  // the box, which is why the sphere looks like it is sitting in the panel rather
  // than leaking a rectangle of glow across it.
  return (
    <div
      ref={wrapRef}
      className={`relative inline-flex shrink-0 select-none items-center justify-center overflow-hidden rounded-full ${className}`}
      style={{ width: resolved.size, height: resolved.size, ...style }}
    >
      <canvas
        ref={canvasRef}
        role="img"
        aria-label={label}
        width={resolved.size}
        height={resolved.size}
        className="absolute inset-0 h-full w-full"
      />
      {orbDisc}
    </div>
  )
}

export default AiFluidBlob
