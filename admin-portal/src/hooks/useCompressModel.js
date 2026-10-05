import { useCallback, useEffect, useRef, useState } from 'react'

import { compressFailureMessage, compressStageSentence, planCompression } from '../lib/modelCompress.js'

// ─── "Compress it", as a hook ──────────────────────────────────────
//
// Three jobs, and they are deliberately not one:
//
//   1. **plan** — `planCompression` runs on the main thread, because it only
//      reads the JSON chunk and the answer (can this be repaired at all?) has
//      to arrive before the button is offered. A refusal here is a sentence,
//      not a spinner.
//   2. **run** — the bytes go to a worker and come back smaller. The tab stays
//      responsive, which matters when the work is 20–30 s and the machine is
//      an admin's laptop with twenty tabs open.
//   3. **report** — the change log and the two sizes come back to the modal, so
//      the admin can see *what was assumed* (the toe end, the sole cut line)
//      rather than trusting that a green button meant a correct model.
//
// **The worker is created per run and terminated after it.** A module worker
// holds its imports and its WASM instance alive; keeping one parked for the
// lifetime of the page would hold a few hundred megabytes for a step that runs
// once per model request. Creating it costs a module fetch, which is cached
// after the first run.
//
// Nothing here publishes anything: the compressed bytes are handed back to the
// caller, which puts them in the existing pipeline. The server still judges
// them, and nothing in this hook is a verdict.

/** The one in-flight run, so a second click cannot start a second worker. */
let nextRunId = 1

export function useCompressModel() {
  const workerRef = useRef(null)
  const runRef = useRef(0)

  const [isRunning, setIsRunning] = useState(false)
  const [stage, setStage] = useState(null)
  const [error, setError] = useState(null)
  const [plan, setPlan] = useState(null)

  /** Kill a run in flight — the modal's close button, and the unmount path. */
  const stop = useCallback(() => {
    runRef.current += 1
    if (workerRef.current) {
      workerRef.current.terminate()
      workerRef.current = null
    }
    setIsRunning(false)
    setStage(null)
  }, [])

  // A run outliving the modal would post its result to nothing and hold the
  // worker's memory until the tab closed.
  useEffect(() => stop, [stop])

  /**
   * Plan the file and, if it can be repaired, compress it.
   *
   * Resolves with the same shape the modal renders:
   * `{ ok, plan, result }` or `{ ok: false, message }`.
   */
  const compress = useCallback(async ({ bytes, declaredLengthMm, authoredSizeEu = null }) => {
    setError(null)

    const planned = planCompression({ bytes, declaredLengthMm, authoredSizeEu })
    setPlan(planned.ok ? planned.plan : null)

    if (!planned.ok) {
      setError(planned.message)
      return { ok: false, plan: null, message: planned.message }
    }

    if (typeof Worker === 'undefined') {
      const message = compressFailureMessage(new Error('worker unavailable'))
      setError(message)
      return { ok: false, plan: planned.plan, message }
    }

    const runId = nextRunId++
    runRef.current = runId
    setIsRunning(true)
    setStage('reading')

    const worker = new Worker(new URL('../lib/modelCompress.worker.js', import.meta.url), {
      type: 'module',
    })
    workerRef.current = worker

    return await new Promise((resolve) => {
      const finish = (outcome) => {
        if (runRef.current === runId) {
          worker.terminate()
          workerRef.current = null
          setIsRunning(false)
          setStage(null)
        }
        resolve(outcome)
      }

      worker.onmessage = (event) => {
        const message = event.data ?? {}
        if (message.id !== runId) return

        if (message.type === 'stage') {
          setStage(message.stage)
          return
        }

        if (message.type === 'done') {
          finish({ ok: true, plan: planned.plan, result: message.result })
          return
        }

        const text = compressFailureMessage(new Error(message.message ?? ''))
        if (runRef.current === runId) setError(text)
        finish({ ok: false, plan: planned.plan, message: text })
      }

      worker.onerror = (event) => {
        // A worker that failed to load never runs `onmessage`, so without this
        // the promise would never settle and the modal would spin forever.
        const text = compressFailureMessage(new Error(event?.message ?? 'worker unavailable'))
        if (runRef.current === runId) setError(text)
        finish({ ok: false, plan: planned.plan, message: text })
      }

      // ⚠️ The bytes are **transferred**, not cloned. A raw export is 90 MB and
      // a structured clone of that would double the peak memory of the step
      // that is already the memory-hungry one — for a buffer this side never
      // reads again. The caller hands over a copy it owns (see the modal), so
      // detaching it here cannot empty anything still on screen.
      const transferable = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes)
      worker.postMessage({ id: runId, bytes: transferable, plan: planned.plan }, [
        transferable.buffer,
      ])
    })
  }, [])

  const clear = useCallback(() => {
    setError(null)
    setPlan(null)
  }, [])

  return {
    compress,
    clear,
    stop,
    isRunning,
    stage,
    stageSentence: compressStageSentence(stage),
    error,
    plan,
  }
}
