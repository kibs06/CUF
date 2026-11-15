import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { toPortalError } from '../lib/errors.js'
import { distinctColorNames, paintRow } from '../lib/paintGuess.js'

// ─── Per-colour 3D paint ───────────────────────────────────────────
// The capture half of the swipe-the-colour mission: which colours this
// product comes in, which already carry a confirmed paint, and the upsert
// that stores a confirmation. The guess lives in `lib/paintGuess.js`
// (prefill only); this hook only ever writes a hex a human confirmed,
// because the guess for an unknown name is a hash pick, not a colour.

const PAINT_SELECT =
  'product_variants(color), product_color_images(color_name), ' +
  'product_color_paint(color_name, paint_hex)'

export function useColorPaint(productId) {
  const queryClient = useQueryClient()

  const query = useQuery({
    queryKey: ['color-paint', productId],
    enabled: !!productId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('products')
        .select(PAINT_SELECT)
        .eq('id', productId)
        .single()
      if (error) throw toPortalError(error, 'Could not load the product colours.')
      const paints = {}
      for (const row of data?.product_color_paint ?? []) {
        const name = row?.color_name?.toString().trim()
        if (name) paints[name] = row?.paint_hex
      }
      return {
        colors: distinctColorNames({
          variants: data?.product_variants,
          colorImages: data?.product_color_images,
        }),
        paints,
      }
    },
  })

  const save = useMutation({
    mutationFn: async ({ colorName, paintHex }) => {
      const { error } = await supabase
        .from('product_color_paint')
        .upsert(paintRow(productId, colorName, paintHex), {
          onConflict: 'product_id,color_name',
        })
      if (error) throw toPortalError(error, 'Could not save the paint.')
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['color-paint', productId] })
    },
  })

  // `savePaint` keeps the rows' two-argument call `(colorName, paintHex)` —
  // it must NOT be the raw `mutateAsync`, which takes a single variables
  // object. Passing two positionals through made react-query deliver the
  // colour NAME as the variables, so the mutation stored `paint_hex: ''`
  // and every Confirm died on the hex CHECK with a value the admin never
  // typed. That mismatch, not the hex, was the persistent failure.
  const savePaint = (colorName, paintHex) => save.mutateAsync({ colorName, paintHex })

  // Removing is the way back from a wrong Confirm (a hash-guess stored as
  // truth, a colourway dropped from the range): the row leaves the table
  // and the colour renders as-authored again, in the app and in the viewer
  // chips, with no re-upload and no new version. Same two-argument shape
  // as `savePaint` for the same reason.
  const remove = useMutation({
    mutationFn: async ({ colorName }) => {
      const { error } = await supabase
        .from('product_color_paint')
        .delete()
        .eq('product_id', productId)
        .eq('color_name', colorName)
      if (error) throw toPortalError(error, 'Could not remove the paint.')
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['color-paint', productId] })
    },
  })
  const removePaint = (colorName) => remove.mutateAsync({ colorName })

  return { ...query, savePaint, saveState: save, removePaint, removeState: remove }
}
