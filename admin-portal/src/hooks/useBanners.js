import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

const BUCKET = 'banners'

// ─── Queries ───────────────────────────────────────────────────────

export function useBanners() {
  return useQuery({
    queryKey: ['admin-banners'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('banners')
        .select('*')
        .order('display_order', { ascending: true })
        .order('created_at', { ascending: false })

      if (error) throw error
      return data ?? []
    },
  })
}

// ─── Mutations ─────────────────────────────────────────────────────

export function useCreateBanner() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ banner, imageFile }) => {
      let imageUrl = banner.image_url

      // Upload image if provided
      if (imageFile) {
        const ext = imageFile.name.split('.').pop() ?? 'jpg'
        const path = `admin/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`

        const { error: uploadErr } = await supabase.storage
          .from(BUCKET)
          .upload(path, imageFile, { contentType: imageFile.type, upsert: false })

        if (uploadErr) throw new Error(`Image upload failed: ${uploadErr.message}`)

        imageUrl = supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl
      }

      if (!imageUrl) throw new Error('Image is required')

      const { data, error } = await supabase
        .from('banners')
        .insert({
          image_url: imageUrl,
          eyebrow_text: banner.eyebrow_text || null,
          title: banner.title,
          cta_label: banner.cta_label || null,
          link_type: banner.link_type ?? 'none',
          link_value: banner.link_value || null,
          display_order: banner.display_order ?? 0,
          is_active: banner.is_active ?? true,
          starts_at: banner.starts_at || null,
          ends_at: banner.ends_at || null,
        })
        .select()
        .single()

      if (error) throw error
      return data
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin-banners'] }),
  })
}

export function useUpdateBanner() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ id, banner, imageFile }) => {
      let imageUrl = banner.image_url

      // Upload new image if provided
      if (imageFile) {
        const ext = imageFile.name.split('.').pop() ?? 'jpg'
        const path = `admin/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`

        const { error: uploadErr } = await supabase.storage
          .from(BUCKET)
          .upload(path, imageFile, { contentType: imageFile.type, upsert: false })

        if (uploadErr) throw new Error(`Image upload failed: ${uploadErr.message}`)

        imageUrl = supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl
      }

      const { error } = await supabase
        .from('banners')
        .update({
          image_url: imageUrl,
          eyebrow_text: banner.eyebrow_text || null,
          title: banner.title,
          cta_label: banner.cta_label || null,
          link_type: banner.link_type ?? 'none',
          link_value: banner.link_value || null,
          display_order: banner.display_order ?? 0,
          is_active: banner.is_active ?? true,
          starts_at: banner.starts_at || null,
          ends_at: banner.ends_at || null,
          updated_at: new Date().toISOString(),
        })
        .eq('id', id)

      if (error) throw error
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin-banners'] }),
  })
}

export function useDeleteBanner() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (banner) => {
      // Delete the storage file if we can extract the path from the URL
      if (banner.image_url) {
        try {
          const url = new URL(banner.image_url)
          const pathParts = url.pathname.split(`/storage/v1/object/public/${BUCKET}/`)
          if (pathParts.length > 1) {
            const filePath = decodeURIComponent(pathParts[1])
            await supabase.storage.from(BUCKET).remove([filePath])
          }
        } catch {
          // Orphaned file is acceptable — don't block the row delete
        }
      }

      const { error } = await supabase
        .from('banners')
        .delete()
        .eq('id', banner.id)

      if (error) throw error
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin-banners'] }),
  })
}

export function useReorderBanners() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (orderedIds) => {
      // Batch update display_order for each banner
      const updates = orderedIds.map((id, index) =>
        supabase
          .from('banners')
          .update({ display_order: index, updated_at: new Date().toISOString() })
          .eq('id', id),
      )

      const results = await Promise.all(updates)
      const firstError = results.find((r) => r.error)
      if (firstError) throw firstError.error
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin-banners'] }),
  })
}
