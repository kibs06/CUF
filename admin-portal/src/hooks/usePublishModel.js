import { useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { toPortalError } from '../lib/errors.js'
import { useFulfilModelRequest } from './useModelRequests.js'
import {
  BUCKET_CAP_BYTES,
  MODEL_BUCKET,
  MODEL_CONTENT_TYPE,
  VALIDATE_MODEL_FUNCTION,
  downloadFailureMessage,
  looksLikeGlb,
  modelRow,
  modellingResult,
  nextVersion,
  reuseMatch,
  rowId,
  serverVerdict,
  sha256Hex,
  sourceUrlAllowed,
  storagePath,
  verdictMessage,
} from '../lib/modelPublish.js'

// ─── Publish a model against a request, and close the ask ──────────
//
// The portal's half of roadmap P2 (V2.11), and it is the same pipeline as
// `ShoeModelUploadService.publish` in Dart, in the same order, for the same
// reason:
//
//   1. the bytes and their digest
//   2. **the object first, the row second** — a row whose object is missing
//      renders as "no model" at best and a failed download every launch at
//      worst, while an object with no row is simply invisible
//   3. the row lands as a **draft**, never `active` — between the insert and the
//      server's answer the only state the catalog can observe is a hidden one
//   4. `validate-shoe-model` judges the stored bytes and is the only caller the
//      database lets write `active` (V2.4)
//   5. only a live model can close the ask, so the fulfil runs last and its
//      failure is reported as `liveButOpen` rather than swallowed
//
// Nothing here is behind `AppConstants` — those switches are Dart compile-time
// constants and mean nothing to a browser. The portal's own switch is
// `MODEL_UPLOAD_ENABLED` in `lib/constants.js`.
//
// The one thing this hook will not do is guess: a transport failure leaves the
// row a draft and the request open, and says so.

/** Read a picked file, refusing anything the bucket would refuse anyway. */
async function bytesFromFile(file) {
  if (!file) throw new Error('Choose a .glb file first.')

  // Checked before reading rather than after: a 500 MB file should not be
  // pulled into memory to be told it is too big.
  if (file.size > BUCKET_CAP_BYTES) throw new Error(tooLargeMessage(file.size))
  if (file.size === 0) {
    throw new Error('That file is empty — check the export and choose it again.')
  }

  const bytes = new Uint8Array(await file.arrayBuffer())
  if (bytes.length > BUCKET_CAP_BYTES) throw new Error(tooLargeMessage(bytes.length))
  return bytes
}

/** Download a link, with a sentence for each way a browser can be stopped. */
async function bytesFromLink(link) {
  const url = String(link ?? '').trim()
  if (!sourceUrlAllowed(url)) {
    throw new Error(
      'Paste a direct https link to the .glb. Links that open a page (Drive previews, ' +
        'sharing pages) do not return the file itself.',
    )
  }

  let response
  try {
    response = await fetch(url, { redirect: 'follow' })
  } catch {
    // The request never got an answer, and in a browser that is nearly always
    // the page rules rather than the network — see `downloadFailureMessage`.
    throw new Error(downloadFailureMessage({ cors: true }))
  }

  if (!response.ok) {
    throw new Error(downloadFailureMessage({ status: response.status }))
  }

  const declared = Number(response.headers.get('content-length') ?? 0)
  if (declared > BUCKET_CAP_BYTES) throw new Error(tooLargeMessage(declared))

  const bytes = new Uint8Array(await response.arrayBuffer())
  if (bytes.length === 0) {
    throw new Error(
      'The link returned an empty file. Check that it points at the exported .glb and that ' +
        'sharing is set to anyone with the link.',
    )
  }
  if (bytes.length > BUCKET_CAP_BYTES) throw new Error(tooLargeMessage(bytes.length))
  return bytes
}

const tooLargeMessage = (bytes) =>
  `The file is over the 8 MB the model bucket accepts (${(bytes / (1024 * 1024)).toFixed(1)} MB). ` +
  'Re-bake the textures and retopo, then export again (guide §C5/C7).'

/** Every `product_models` row for one product, whatever its status — a reuse
 *  match or a version number depends on all of them, drafts included. */
async function rowsFor(productId) {
  const { data, error } = await supabase
    .from('product_models')
    .select('id, status, version, variant_id, sha256, storage_path')
    .eq('product_id', productId)

  if (error) throw toPortalError(error, 'Could not read this product’s models.')
  return data ?? []
}

/**
 * Ask the server to judge one row.
 *
 * `functions.invoke` answers a non-2xx as an `error` whose `context` is the
 * `Response` — and the 422 that *is* our refusal arrives exactly that way, so
 * the body is read as carefully as a success. Nothing here throws: a validator
 * that threw would turn "not judged" into "the upload failed", which loses the
 * row and the reason.
 */
async function judgeModel(modelId) {
  try {
    const { data, error } = await supabase.functions.invoke(VALIDATE_MODEL_FUNCTION, {
      body: { model_id: modelId, activate: true },
    })

    if (!error) return serverVerdict({ statusCode: 200, body: data })

    const status = error?.context?.status ?? 0
    let body = null
    try {
      body = error?.context ? await error.context.clone().json() : null
    } catch {
      // A body that will not parse is not a reason to lose the verdict: a 422
      // still counts as a judgement, and everything else falls back to the
      // function's own sentence below.
      body = null
    }
    return serverVerdict({
      statusCode: status,
      body: body ?? { error: error?.message || 'could not reach the server' },
    })
  } catch {
    return serverVerdict({
      statusCode: 0,
      body: { error: 'could not reach the server' },
    })
  }
}

/** The whole act: bytes → bucket → draft row → server → close. */
async function publishAndClose({ request, link, file, declaration, note }) {
  const bytes = file ? await bytesFromFile(file) : await bytesFromLink(link)

  if (!looksLikeGlb(bytes)) {
    throw new Error(
      'That file is not a GLB v2 — its header says something else. Export the model as .glb ' +
        'and try again (guide §C5).',
    )
  }

  const digest = await sha256Hex(bytes)
  const existing = await rowsFor(request.product_id)
  const reusable = reuseMatch(existing, digest)

  let modelId = null
  let alreadyLive = false

  if (reusable) {
    // These exact bytes are already this product's: the digest IS the filename,
    // so the object is in the bucket under it and a second row would give the
    // resolver two candidates for one asset. Judged only if it is not already
    // live — `active` is itself the record that these bytes passed the server,
    // and asking again would spend a download to be told what the row says.
    modelId = rowId(reusable.id)
    alreadyLive = String(reusable.status) === 'active'
    if (modelId === null) {
      throw new Error(
        'The stored model record is missing its id, so it cannot be published. Upload the model ' +
          'again.',
      )
    }
  } else {
    const version = nextVersion(existing)
    const path = storagePath({
      storeId: request.store_id,
      productId: request.product_id,
      sha256: digest,
    })

    const upload = await supabase.storage.from(MODEL_BUCKET).upload(path, bytes, {
      contentType: MODEL_CONTENT_TYPE,
      // The filename is the digest, so a retry of the same bytes is the same
      // object — a 409 there would be a lie about what went wrong.
      upsert: true,
    })
    if (upload.error) {
      throw toPortalError(upload.error, 'The file could not be uploaded to storage.')
    }

    const row = modelRow({
      productId: request.product_id,
      storagePath: path,
      sha256: digest,
      version,
      authoredLengthMm: declaration.externalLengthMm,
      authoredSizeEu: declaration.authoredSizeEu,
      // `triangle_count` and `file_size_bytes` are filled from the contract in
      // the app; here the server reads the stored bytes, and a size we know for
      // free is still worth recording.
      fileSizeBytes: bytes.length,
    })

    const insert = await supabase.from('product_models').insert(row).select().single()
    if (insert.error) throw toPortalError(insert.error, 'The model record could not be saved.')
    modelId = rowId(insert.data?.id)
    if (modelId === null) {
      // The server moves a row by its id, and this write did not report one. The
      // bytes and the row are safely in place and hidden, so publishing again is
      // the retry — the same conclusion the Dart service reaches. Returned in the
      // same shape as the rest of this function, so the caller has one thing to
      // read rather than two.
      return {
        modelId: null,
        live: false,
        refusal: 'the saved model record did not report its id',
      }
    }
  }

  const verdict = alreadyLive ? null : await judgeModel(modelId)

  return {
    modelId,
    live: alreadyLive || verdict?.outcome === 'validated',
    // The server's own sentence when it refused, and null when it passed — the
    // `notLive` ending reads it, because "refused (materials, scale)" is
    // actionable and "it did not work" is not.
    refusal: verdictMessage(verdict),
  }
}

export function usePublishModelRequest() {
  const queryClient = useQueryClient()
  const fulfil = useFulfilModelRequest()

  const mutation = useMutation({
    mutationFn: async ({ request, link, file, declaration, note }) => {
      const published = await publishAndClose({ request, link, file, declaration, note })

      // Only a live model can close an ask — the RPC requires an `active` model
      // of the same product — so the close is attempted only when there is
      // something to point at, and its failure is a reported ending rather than
      // a thrown error. That is the `liveButOpen` state: the one outcome this
      // feature must not quietly produce.
      let fulfilled = false
      if (published.live && published.modelId !== null) {
        try {
          await fulfil.mutateAsync({
            requestId: request.id,
            modelId: published.modelId,
            note,
          })
          fulfilled = true
        } catch {
          fulfilled = false
        }
      }

      return modellingResult({
        modelIsLive: published.live,
        fulfilled,
        modelId: published.modelId,
        refusal: published.refusal,
      })
    },
    onSettled: (_result, _error, variables) => {
      // Read the queue again rather than assume it changed: a `liveButOpen`
      // ending leaves the ask exactly where it was, and the model picker now has
      // one more row in it.
      queryClient.invalidateQueries({ queryKey: ['model-requests'] })
      queryClient.invalidateQueries({ queryKey: ['product-models', variables?.request?.product_id] })
      queryClient.invalidateQueries({ queryKey: ['dashboard-stats'] })
    },
  })

  return mutation
}
