// ─── The worker that does the compressing ──────────────────────────
//
// A 90 MB export, decimated and re-baked, is tens of seconds of solid
// JavaScript with a few hundred megabytes of typed arrays in flight. On the
// main thread that is a frozen tab — no spinner, no cancel, and on some
// machines a "page unresponsive" dialog over the one screen that exists to fix
// the file. So it runs here.
//
// The worker owns exactly one job at a time and answers with one of two
// messages. It never decides anything: the plan (ratio, sole cut, declared
// length) is computed on the main thread by `modelCompress.js` and arrives
// complete, and the bytes that come back are handed straight to the existing
// publish pipeline — the server still judges them.
//
// It imports `modelCompressPipeline.js` rather than inlining the stages so the
// test can run the same code with `NodeIO`, which is the only difference
// between this environment and that one.

import { compressShoeModel } from './modelCompressPipeline.js'

self.onmessage = async (event) => {
  const { id, bytes, plan } = event.data ?? {}

  try {
    const result = await compressShoeModel({
      bytes,
      plan,
      onStage: (stage) => self.postMessage({ id, type: 'stage', stage }),
    })

    // The buffer is transferred rather than copied: a 2 MB result is cheap
    // either way, but the same code path is what a future higher-resolution
    // output would need, and copying here would be a trap set for later.
    self.postMessage({ id, type: 'done', result }, [result.bytes.buffer])
  } catch (error) {
    self.postMessage({
      id,
      type: 'failed',
      // `Error` does not survive structured clone with its message intact in
      // every browser, so the sentence travels as a string.
      message: error instanceof Error ? error.message : String(error ?? ''),
    })
  }
}
