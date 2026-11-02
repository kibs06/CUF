import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { toPortalError } from '../lib/errors.js'
import { sha256Hex } from '../lib/modelPublish.js'

// ─── Product AR effects ────────────────────────────────────────────
//
// The `.deepar` Studio files customers fit in, uploaded per product instead of
// bundled in a release. One live (`active`) row per product; the resolvers on
// both clients prefer it over the bundled Luna/Luxe effects.
//
// Two deliberate choices, both inherited from the model pipeline:
//   1. **The row goes before the object is trusted, and the row goes first on
//      delete.** An object with no row is invisible; a row with no object
//      renders as "no AR" at worst.
//   2. **Admin uploads land `active` straight away.** There is no validator
//      for a Studio binary — no Edge Function can judge a `.deepar` — so a
//      draft state would be process without a decider. The uploader previewed
//      the file in Studio before exporting it; that is the review.

/** The public-read bucket `product_ar_effects.storage_path` points into. */
export const AR_EFFECT_BUCKET = 'shoe-ar-effects'

/** The bucket's own `file_size_limit` — Studio exports run ~16 MB. */
export const AR_EFFECT_CAP_BYTES = 32 * 1024 * 1024

/** A `.deepar` is an opaque Studio binary, never a web type. */
export const AR_EFFECT_CONTENT_TYPE = 'application/octet-stream'

/** Every live effect, newest first — the 3D shelf's AR badge source. */
export function useArEffects() {
  return useQuery({
    queryKey: ['ar-effects'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('product_ar_effects')
        .select('id, product_id, version, storage_path, file_size_bytes, created_at')
        .eq('status', 'active')
        .order('created_at', { ascending: false })

      if (error) throw toPortalError(error, 'Could not load the live AR effects.')
      return data ?? []
    },
  })
}

/** Next version number for a product: one above its highest, starting at 1. */
async function nextVersion(productId) {
  const { data, error } = await supabase
    .from('product_ar_effects')
    .select('version')
    .eq('product_id', productId)
    .order('version', { ascending: false })
    .limit(1)

  if (error) throw toPortalError(error, 'Could not read that product’s AR effects.')
  return ((data ?? [])[0]?.version ?? 0) + 1
}

/**
 * Upload a `.deepar` file for a product and publish it as the live effect.
 * Resolves with `{ version, bytes }`.
 */
export function useUploadArEffect() {
  const qc = useQueryClient()

  return useMutation({
    mutationFn: async ({ productId, productName, file }) => {
      if (!productId) throw new Error('That product has no id to attach the effect to.')
      if (!file) throw new Error('Choose a .deepar file first.')

      const name = String(file.name ?? '')
      if (!/\.deepar$/i.test(name)) {
        throw new Error(
          'That is not a DeepAR Studio export — pick the .deepar file Studio’s export produced.',
        )
      }
      if (file.size > AR_EFFECT_CAP_BYTES) {
        throw new Error(
          `That file is ${(file.size / (1024 * 1024)).toFixed(1)} MB against the 32 MB the ` +
            'AR bucket accepts — re-export it from Studio.',
        )
      }
      if (file.size === 0) throw new Error('That file is empty — re-export it from Studio.')

      const bytes = new Uint8Array(await file.arrayBuffer())
      const sha = await sha256Hex(bytes)
      const path = `${productId}/${sha}.deepar`

      const { error: objectError } = await supabase.storage
        .from(AR_EFFECT_BUCKET)
        .upload(path, bytes, {
          contentType: AR_EFFECT_CONTENT_TYPE,
          upsert: true,
        })
      if (objectError) throw toPortalError(objectError, 'That effect could not be uploaded.')

      const version = await nextVersion(productId)
      const { error: rowError } = await supabase.from('product_ar_effects').insert({
        product_id: productId,
        storage_path: path,
        sha256: sha,
        version,
        status: 'active',
        file_size_bytes: bytes.length,
      })
      if (rowError) {
        // Rowless bytes are invisible, so the upload is harmless — but say so
        // rather than leaving the admin guessing what landed.
        throw toPortalError(
          rowError,
          'The file uploaded but its row was refused, so no product shows it. ' +
            'Remove the file from the bucket by hand and try again.',
        )
      }

      return { version, bytes: bytes.length, productName: productName ?? 'that product' }
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['ar-effects'] })
    },
  })
}

/**
 * Remove a product's live effect, row before object (a row that survives its
 * file reads as "no AR"; an object that survives its row is invisible).
 */
export function useDeleteArEffect() {
  const qc = useQueryClient()

  return useMutation({
    mutationFn: async ({ rowId, storagePath }) => {
      if (rowId == null) throw new Error('That effect has no row to delete.')

      const { error: rowError } = await supabase
        .from('product_ar_effects')
        .delete()
        .eq('id', rowId)
      if (rowError) throw toPortalError(rowError, 'That effect could not be deleted.')

      if (storagePath) {
        const { error: objectError } = await supabase.storage
          .from(AR_EFFECT_BUCKET)
          .remove([storagePath])
        if (objectError) {
          throw toPortalError(
            objectError,
            'The effect row is deleted, so no product shows it — but its file could not be ' +
              'removed. It is invisible and safe to leave, or delete it from the bucket by hand.',
          )
        }
      }
      return { rowId }
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['ar-effects'] })
    },
  })
}
