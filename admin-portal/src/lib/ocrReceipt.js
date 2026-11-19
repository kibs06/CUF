// admin-portal/src/lib/ocrReceipt.js
//
// OCR for a GCash screenshot in the browser, used by the payout dialog to fill
// the reference number the admin would otherwise retype.
//
// tesseract.js is imported lazily: the portal only pays for the WASM engine and
// the English model when someone actually attaches a screenshot, so the admin
// bundle and first paint are unchanged for every other page.

let workerPromise = null

async function getWorker(onProgress) {
  if (!workerPromise) {
    workerPromise = (async () => {
      const { createWorker } = await import('tesseract.js')
      return createWorker('eng', 1, {
        logger: (message) => {
          if (message?.status === 'recognizing text' && typeof onProgress === 'function') {
            onProgress(message.progress ?? 0)
          }
        },
      })
    })()
  }
  return workerPromise
}

/**
 * Recognize the text in an image file.
 *
 * Returns the raw OCR text (lines joined with `\n`). Throws only when the
 * engine itself cannot run; the caller decides what a miss means.
 *
 * A PDF is rejected before reaching this: tesseract reads raster images, and
 * silently returning empty text for a file it never looked at would look like
 * "the receipt has no reference".
 */
export async function recognizeReceiptText(file, { onProgress } = {}) {
  if (!file) throw new Error('No file')
  if (!String(file.type ?? '').startsWith('image/')) {
    throw new Error('Attach a screenshot (PNG/JPG) — PDFs cannot be read here.')
  }

  const worker = await getWorker(onProgress)
  const { data } = await worker.recognize(file)
  return String(data?.text ?? '')
}
