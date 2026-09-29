import { useMemo, useState } from 'react'
import { Check, Copy, Layers, MousePointerClick, Sparkles, Waves } from 'lucide-react'

import AiFluidBlob from '../components/ai/AiFluidBlob.jsx'
import { useToast } from '../components/ui/Toast.jsx'
import {
  BLOB_DEFAULTS,
  BLOB_PRESETS,
  BLOB_SIZE_LIMITS,
  BLOB_VARIANTS,
  MAX_STRANDS,
  blobSnippet,
  normalizeColors,
  resolveBlobProps,
} from '../lib/aiBlob.js'

// ─── Ai Fluid Blob ─────────────────────────────────────────────────
//
// A page for one component, in the shape a component docs page usually takes:
// preview, install, usage, props. Three things about it are this project's rather
// than the original doc's, and each is deliberate:
//
//   1. **The preview is the component, not a screenshot.** The `AiFluidBlob` on
//      this page is the same file the portal imports anywhere else, so the doc
//      cannot describe a component that no longer exists.
//   2. **The snippet is generated from the props**, by `blobSnippet`, so the code
//      on screen and the blob beside it cannot disagree — the only failure mode a
//      "copy this" panel really has.
//   3. **The install section says what is true here.** This portal is not a
//      Lightswind project and the Pro source is not redistributable, so what is
//      installed is an in-repo implementation of the documented API. The original
//      CLI line is kept for provenance and labelled as not-to-run, because a doc
//      page that quietly rewrites history is worse than one that shows a step
//      that does not apply.
//
// Everything decidable lives in `lib/aiBlob.js` and is tested there; this file is
// the UI around it and holds no rules of its own.

/** The dotted page the component is previewed on — white with a dot grid, so the
 *  sphere's own edge and its halo are what you are looking at. */
const DOTTED_SURFACE = {
  backgroundColor: '#FFFFFF',
  backgroundImage: 'radial-gradient(#D9D4CE 1px, transparent 1px)',
  backgroundSize: '16px 16px',
}

const STATE_BLURB = {
  listening: 'Idle attention — slow spin, steady ripple, the field at rest but awake.',
  thinking: 'Wandering — the slowest spin with the most wobble, so the strands drift out of phase.',
  speaking: 'Agitated — the brightest and fastest, with the ripple running hard.',
  orbit: 'Orderly — wide, evenly spaced strands turning quickly with almost no deformation.',
  pulse: 'Breathing — nearly still, with the outward ripple doing all the work.',
}

const PROPS = [
  ['size', 'number', '260', 'Component width & height in pixels.', 'No'],
  ['colors', 'string[]', "['#10B981', '#06B6D4', '#3B82F6', '#6366F1']", 'Array of HEX color strings for fluid strands.', 'No'],
  ['count', 'number', '4', 'Number of fluid strands (1 to 12).', 'No'],
  [
    'variant',
    '"listening" | "thinking" | "speaking" | "orbit" | "pulse"',
    '"listening"',
    'AI Voice Assistant state mode.',
    'No',
  ],
  ['glass', 'boolean', 'true', 'Enable glass sphere refraction lens.', 'No'],
]

function Card({ title, subtitle, children, className = '' }) {
  return (
    <section className={`rounded-2xl border border-[#D9D0C7] bg-white p-6 ${className}`}>
      {title && (
        <header className="mb-4">
          <h2 className="font-display text-lg font-bold text-[#3B2314]">{title}</h2>
          {subtitle && <p className="mt-1 text-sm text-[#6B5C4E]">{subtitle}</p>}
        </header>
      )}
      {children}
    </section>
  )
}

function Code({ children }) {
  const [copied, setCopied] = useState(false)
  const { showToast } = useToast()

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(children)
      setCopied(true)
      showToast('Snippet copied')
      setTimeout(() => setCopied(false), 1600)
    } catch {
      // A refused clipboard is a permissions question, not a failure of the page:
      // the code is on screen and selectable either way.
      showToast('Copy was blocked — select the code and copy it manually', 'error')
    }
  }

  return (
    <div className="relative">
      <button
        type="button"
        onClick={copy}
        className="absolute right-3 top-3 inline-flex items-center gap-1.5 rounded-lg border border-white/15 bg-black/30 px-2.5 py-1.5 text-[11px] font-semibold text-[#C4A882] transition-colors hover:bg-black/50 hover:text-white"
      >
        {copied ? <Check size={12} /> : <Copy size={12} />}
        {copied ? 'Copied' : 'Copy'}
      </button>
      <pre className="overflow-x-auto rounded-xl bg-[#1B1410] p-4 pr-24 font-mono text-xs leading-relaxed text-[#E8DDD5]">
        <code>{children}</code>
      </pre>
    </div>
  )
}

export default function Ai() {
  const [variant, setVariant] = useState(BLOB_DEFAULTS.variant)
  // 320, the size the component's own documentation renders it at — so the page
  // opens on the picture the props table and the snippet describe.
  const [size, setSize] = useState(320)
  const [count, setCount] = useState(BLOB_DEFAULTS.count)
  const [glass, setGlass] = useState(BLOB_DEFAULTS.glass)
  const [paletteName, setPaletteName] = useState(BLOB_PRESETS[0].name)
  const [installTab, setInstallTab] = useState('portal')

  const preset = BLOB_PRESETS.find((p) => p.name === paletteName) ?? BLOB_PRESETS[0]
  const props = useMemo(
    () => ({ size, colors: preset.colors, count, variant, glass }),
    [size, preset, count, variant, glass],
  )
  // The resolved props, not the raw state: a slider can ask for a strand count
  // the shader cannot draw, and the caption should describe what is on screen.
  const resolved = resolveBlobProps(props)
  const snippet = useMemo(() => blobSnippet(props), [props])

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <div className="flex items-center gap-2">
          <Sparkles size={18} className="text-[#8B5A2B]" />
          <h1 className="font-display text-2xl font-bold text-[#3B2314]">AI</h1>
        </div>
        <p className="mt-1 max-w-3xl text-sm text-[#6B5C4E]">
          A WebGL multi-strand chromatic liquid wave with a glass refraction lens sphere, rendered
          by hand-written shaders in this portal — <strong className="text-[#3B2314]">Ai Fluid
          Blob</strong>. Four bands of liquid light wrap a sphere and cross in front of it, a
          frosted voice orb sits at its centre, and the sphere samples the liquid through itself —
          bending blue more than red.
        </p>
      </div>

      {/* ─── Preview + controls ─────────────────────────────────────── */}
      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_340px]">
        <Card className="bg-white">
          {/* The sphere is transparent, so it is shown on a light surface here for the
              same reason the original is: a picture of a glass ball on a black panel is
              a picture of a dark circle. */}
          <div
            className="flex items-center justify-center rounded-2xl border border-[#F0EAE3] px-6 py-10"
            style={DOTTED_SURFACE}
          >
            <AiFluidBlob {...props} />
          </div>
          <div className="mt-4 flex flex-wrap items-center gap-x-5 gap-y-2 text-xs text-[#6B5C4E]">
            <span className="font-semibold text-[#3B2314]">{STATE_BLURB[resolved.variant]}</span>
          </div>
          <dl className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
            {[
              ['variant', resolved.variant],
              ['count', `${resolved.count} of ${MAX_STRANDS}`],
              ['size', `${resolved.size} px`],
              ['glass', resolved.glass ? 'on' : 'off'],
            ].map(([label, value]) => (
              <div key={label} className="rounded-xl border border-[#F5F0EB] bg-[#FBF8F5] px-3 py-2">
                <dt className="text-[10px] uppercase tracking-wider text-[#6B5C4E]">{label}</dt>
                <dd className="font-mono text-sm font-semibold text-[#3B2314]">{value}</dd>
              </div>
            ))}
          </dl>
        </Card>

        <Card title="Try it" subtitle="Every control below is one of the five documented props.">
          <div className="space-y-5">
            <div>
              <p className="mb-2 text-[11px] font-semibold uppercase tracking-wider text-[#6B5C4E]">
                variant
              </p>
              <div className="flex flex-wrap gap-1.5">
                {BLOB_VARIANTS.map((name) => (
                  <button
                    key={name}
                    type="button"
                    onClick={() => setVariant(name)}
                    className={`rounded-lg px-2.5 py-1.5 text-[11px] font-semibold transition-colors ${
                      variant === name
                        ? 'bg-[#8B5A2B] text-white'
                        : 'border border-[#D9D0C7] text-[#6B5C4E] hover:bg-[#F5F0EB]'
                    }`}
                  >
                    {name}
                  </button>
                ))}
              </div>
            </div>

            <div>
              <label
                htmlFor="blob-size"
                className="mb-2 flex items-center justify-between text-[11px] font-semibold uppercase tracking-wider text-[#6B5C4E]"
              >
                <span>size</span>
                <span className="font-mono text-[#3B2314]">{size} px</span>
              </label>
              <input
                id="blob-size"
                type="range"
                min={120}
                max={460}
                step={10}
                value={size}
                onChange={(e) => setSize(Number(e.target.value))}
                className="w-full accent-[#8B5A2B]"
              />
            </div>

            <div>
              <label
                htmlFor="blob-count"
                className="mb-2 flex items-center justify-between text-[11px] font-semibold uppercase tracking-wider text-[#6B5C4E]"
              >
                <span>count</span>
                <span className="font-mono text-[#3B2314]">{count}</span>
              </label>
              <input
                id="blob-count"
                type="range"
                min={1}
                max={MAX_STRANDS}
                step={1}
                value={count}
                onChange={(e) => setCount(Number(e.target.value))}
                className="w-full accent-[#8B5A2B]"
              />
            </div>

            <div className="flex items-center gap-3">
              <button
                type="button"
                role="switch"
                aria-checked={glass}
                onClick={() => setGlass((on) => !on)}
                className={`relative h-6 w-11 rounded-full transition-colors ${
                  glass ? 'bg-[#8B5A2B]' : 'bg-[#D9D0C7]'
                }`}
              >
                <span
                  className="absolute top-0.5 h-5 w-5 rounded-full bg-white shadow-sm transition-transform"
                  style={{ transform: glass ? 'translateX(22px)' : 'translateX(2px)' }}
                />
              </button>
              <span className="text-sm text-[#3B2314]">
                glass <span className="text-[#6B5C4E]">— refraction lens sphere</span>
              </span>
            </div>

            <div>
              <p className="mb-2 text-[11px] font-semibold uppercase tracking-wider text-[#6B5C4E]">
                colors
              </p>
              <div className="flex flex-wrap gap-1.5">
                {BLOB_PRESETS.map((option) => (
                  <button
                    key={option.name}
                    type="button"
                    onClick={() => setPaletteName(option.name)}
                    title={option.colors.join(' · ')}
                    className={`flex items-center gap-1.5 rounded-lg border px-2 py-1.5 text-[11px] font-semibold transition-colors ${
                      paletteName === option.name
                        ? 'border-[#8B5A2B] bg-[#8B5A2B]/10 text-[#3B2314]'
                        : 'border-[#D9D0C7] text-[#6B5C4E] hover:bg-[#F5F0EB]'
                    }`}
                  >
                    <span className="flex overflow-hidden rounded-full">
                      {normalizeColors(option.colors).map((colour) => (
                        <span
                          key={colour}
                          className="h-3 w-3"
                          style={{ backgroundColor: colour }}
                        />
                      ))}
                    </span>
                    {option.name}
                  </button>
                ))}
              </div>
            </div>
          </div>
        </Card>
      </div>

      {/* ─── The generated snippet ──────────────────────────────────── */}
      <Card
        title="Usage"
        subtitle="Generated from the controls above, so the code and the preview cannot disagree."
      >
        <Code>{snippet}</Code>
        <p className="mt-3 font-mono text-xs text-[#6B5C4E]">
          {'size is clamped to '}
          {BLOB_SIZE_LIMITS.min}
          {'–'}
          {BLOB_SIZE_LIMITS.max}
          {' px and count to 1–'}
          {MAX_STRANDS}
          {': outside those, the component draws the limit rather than nothing. An unknown variant falls back to "'}
          {BLOB_DEFAULTS.variant}
          {'".'}
        </p>
      </Card>

      {/* ─── All five states at once ────────────────────────────────── */}
      <Card
        title="The five states"
        subtitle="Five instances of the same component, one per variant, so the differences are visible side by side."
      >
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
          {BLOB_VARIANTS.map((name) => (
            <div key={name} className="rounded-2xl border border-[#F5F0EB] bg-[#FBF8F5] p-3 text-center">
              <div
                className="flex items-center justify-center rounded-xl py-3"
                style={DOTTED_SURFACE}
              >
                <AiFluidBlob size={132} variant={name} count={4} colors={preset.colors} glass={glass} />
              </div>
              <p className="mt-2 font-mono text-xs font-semibold text-[#3B2314]">{name}</p>
              <p className="mt-1 text-[10px] leading-snug text-[#6B5C4E]">
                {STATE_BLURB[name]}
              </p>
            </div>
          ))}
        </div>
      </Card>

      {/* ─── Installation ──────────────────────────────────────────── */}
      <Card title="Installation">
        <div className="mb-4 flex gap-2">
          {[
            { key: 'portal', label: 'In this portal' },
            { key: 'cli', label: 'CLI (Lightswind Pro)' },
            { key: 'manual', label: 'Manual' },
          ].map((tab) => (
            <button
              key={tab.key}
              type="button"
              onClick={() => setInstallTab(tab.key)}
              className={`rounded-xl px-3 py-1.5 text-xs font-semibold transition-colors ${
                installTab === tab.key
                  ? 'bg-[#8B5A2B] text-white'
                  : 'border border-[#D9D0C7] text-[#6B5C4E] hover:bg-[#F5F0EB]'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {installTab === 'portal' && (
          <div className="space-y-3">
            <p className="flex items-start gap-2 text-sm text-[#6B5C4E]">
              <Check size={15} className="mt-0.5 shrink-0 text-[#4ECDC4]" />
              Nothing to install: the component ships with the portal.
            </p>
            <Code>{`// src/components/ai/AiFluidBlob.jsx — the drawing
// src/components/ai/blobShader.js  — the two GLSL sources
// src/lib/aiBlob.js                — the props, the palettes, the motion
import { AiFluidBlob } from '../components/ai/AiFluidBlob.jsx'`}</Code>
            <p className="text-xs text-[#6B5C4E]">
              No dependency was added. The strands and the lens are a fragment shader on a
              full-screen quad, so the bundle carries no 3D engine for one panel.
            </p>
          </div>
        )}

        {installTab === 'cli' && (
          <div className="space-y-3">
            <Code>{'npx lightswind@latest add ai-fluid-blob'}</Code>
            <p className="rounded-xl border border-[#D9CD9A] bg-[#FFF8E5] px-4 py-3 text-xs leading-relaxed text-[#6B5C4E]">
              <strong className="text-[#3B2314]">Kept for provenance, not for running.</strong> This
              portal is not a Lightswind project, and the component it documents is a Pro one: the
              published docs ship{' '}
              <code className="font-mono text-[11px]">
                {'// 🔒 Upgrade to Lightswind Pro to unlock full source code & CLI access'}
              </code>{' '}
              in place of the source. Running this command here would add nothing that the portal
              imports, and the file above is an independent implementation of the same public API —
              same five props, same defaults, our own pixels.
            </p>
          </div>
        )}

        {installTab === 'manual' && (
          <div className="space-y-3">
            <p className="text-sm text-[#6B5C4E]">
              The original doc's manual step pastes the component source in. There is no source to
              paste: this is that step, already done, in this repository —
            </p>
            <Code>{`admin-portal/src/
├── components/ai/
│   ├── AiFluidBlob.jsx     # the canvas, the program and the render loop
│   └── blobShader.js       # vertex + fragment GLSL (the whole drawing)
└── lib/
    ├── aiBlob.js           # props, palettes, motion, snippet — all pure
    └── aiBlob.test.js      # and its tests`}</Code>
            <p className="text-xs text-[#6B5C4E]">
              A change wanted in the drawing belongs in the fragment shader; a change wanted in the
              behaviour of a prop belongs in <code className="font-mono">aiBlob.js</code>, where it
              can be tested without a GPU.
            </p>
          </div>
        )}
      </Card>

      {/* ─── Props ─────────────────────────────────────────────────── */}
      <Card title="Props">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-[#D9D0C7] text-[11px] uppercase tracking-wider text-[#6B5C4E]">
                <th className="py-2 pr-4 font-semibold">Prop</th>
                <th className="py-2 pr-4 font-semibold">Type</th>
                <th className="py-2 pr-4 font-semibold">Default</th>
                <th className="py-2 pr-4 font-semibold">Description</th>
                <th className="py-2 font-semibold">Required</th>
              </tr>
            </thead>
            <tbody>
              {PROPS.map(([prop, type, value, description, required]) => (
                <tr key={prop} className="border-b border-[#F5F0EB] align-top">
                  <td className="py-2.5 pr-4 font-mono text-xs font-semibold text-[#3B2314]">
                    {prop}
                  </td>
                  <td className="py-2.5 pr-4 font-mono text-xs text-[#6B5C4E]">{type}</td>
                  <td className="py-2.5 pr-4 font-mono text-xs text-[#6B5C4E]">{value}</td>
                  <td className="py-2.5 pr-4 text-xs text-[#6B5C4E]">{description}</td>
                  <td className="py-2.5 text-xs text-[#6B5C4E]">{required}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="mt-3 text-xs text-[#6B5C4E]">
          Plus <code className="font-mono">className</code> and{' '}
          <code className="font-mono">style</code> passthrough for layout, which are HTML rather than
          part of the component's own API.
        </p>
      </Card>

      {/* ─── How it works ──────────────────────────────────────────── */}
      <Card title="How it works">
        <div className="grid gap-5 md:grid-cols-2">
          <div className="space-y-3 text-sm leading-relaxed text-[#6B5C4E]">
            <p className="flex items-start gap-2">
              <Layers size={15} className="mt-0.5 shrink-0 text-[#8B5A2B]" />
              <span>
                <strong className="text-[#3B2314]">A band is a ring, seen nearly edge-on.</strong>{' '}
                Each one is wide and bright on the axis and pinched to a point at both ends, because
                that is what a ring around a sphere looks like from slightly above its equator. Odd
                and even bands lean opposite ways, which is why they meet and cross in the middle
                rather than nest.
              </span>
            </p>
            <p className="flex items-start gap-2">
              <Waves size={15} className="mt-0.5 shrink-0 text-[#8B5A2B]" />
              <span>
                <strong className="text-[#3B2314]">Colour travels along a band, and each band
                starts somewhere else in the palette.</strong> So four bands show four ends of the
                same four colours instead of four stripes of one.
              </span>
            </p>
          </div>
          <div className="space-y-3 text-sm leading-relaxed text-[#6B5C4E]">
            <p className="flex items-start gap-2">
              <MousePointerClick size={15} className="mt-0.5 shrink-0 text-[#8B5A2B]" />
              <span>
                <strong className="text-[#3B2314]">The sphere bends blue more than red.</strong>{' '}
                It re-samples the liquid behind itself three times at three slightly different
                displacements — one per channel — pulling hardest where its surface turns away,
                which is what makes the bands inside it look split rather than blurred. A saturated
                rim, a tight specular and a bounce from below finish the glass.
              </span>
            </p>
            <p className="flex items-start gap-2">
              <Check size={15} className="mt-0.5 shrink-0 text-[#4ECDC4]" />
              <span>
                <strong className="text-[#3B2314]">It stops when nobody is looking.</strong> The
                loop pauses for a canvas scrolled out of view, for a hidden tab, and for{' '}
                <code className="font-mono text-xs">prefers-reduced-motion</code> — where the field
                is rendered once at a fixed phase instead of animating, because the blob is the
                panel and removing it would leave a hole.
              </span>
            </p>
            <p className="text-xs">
              Honest limits: this is an implementation of the documented API rather than the
              Lightswind Pro component, so the pixels are ours; the canvas is transparent and
              straight-alpha, which is why it can sit on a white card at all; and a browser that
              refuses a WebGL context gets a gradient fallback marked{' '}
              <code className="font-mono">data-blob-fallback</code> rather than an empty box.
            </p>
          </div>
        </div>
      </Card>
    </div>
  )
}
