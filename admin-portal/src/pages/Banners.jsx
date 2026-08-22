import { useState, useRef } from 'react'
import {
  Plus,
  Pencil,
  Trash2,
  ChevronUp,
  ChevronDown,
  Image as ImageIcon,
  Eye,
  EyeOff,
  Calendar,
} from 'lucide-react'
import { useToast } from '../components/ui/Toast.jsx'
import EmptyState from '../components/ui/EmptyState.jsx'
import Modal from '../components/ui/Modal.jsx'
import {
  useBanners,
  useCreateBanner,
  useUpdateBanner,
  useDeleteBanner,
  useReorderBanners,
} from '../hooks/useBanners.js'
import { formatDateTime } from '../lib/constants.js'

const LINK_TYPES = [
  { value: 'none', label: 'No link' },
  { value: 'category', label: 'Category' },
  { value: 'product', label: 'Product' },
  { value: 'url', label: 'URL' },
]

// Categories matching the customer app's ProductProvider
const CATEGORIES = [
  'All', 'Boots', 'Sandals', 'Sneakers', 'Formal', 'Casual',
  'Slip-ons', 'Sports', 'Heels', 'Loafers', 'Mules', 'Platforms',
]

const EMPTY_FORM = {
  image_url: '',
  eyebrow_text: '',
  title: '',
  cta_label: '',
  link_type: 'none',
  link_value: '',
  display_order: 0,
  is_active: true,
  starts_at: '',
  ends_at: '',
}

export default function Banners() {
  const { showToast } = useToast()
  const [showForm, setShowForm] = useState(false)
  const [editTarget, setEditTarget] = useState(null)
  const [deleteTarget, setDeleteTarget] = useState(null)
  const [form, setForm] = useState(EMPTY_FORM)
  const [imageFile, setImageFile] = useState(null)
  const [imagePreview, setImagePreview] = useState(null)
  const [uploading, setUploading] = useState(false)
  const [validationError, setValidationError] = useState('')
  const fileRef = useRef(null)

  const { data: banners, isLoading, isError, error } = useBanners()
  const createBanner = useCreateBanner()
  const updateBanner = useUpdateBanner()
  const deleteBanner = useDeleteBanner()
  const reorderBanners = useReorderBanners()

  // ─── Form helpers ────────────────────────────────────────────────

  const resetForm = () => {
    setForm(EMPTY_FORM)
    setImageFile(null)
    setImagePreview(null)
    setValidationError('')
    setEditTarget(null)
  }

  const openCreate = () => {
    resetForm()
    setShowForm(true)
  }

  const openEdit = (banner) => {
    setForm({
      image_url: banner.image_url ?? '',
      eyebrow_text: banner.eyebrow_text ?? '',
      title: banner.title ?? '',
      cta_label: banner.cta_label ?? '',
      link_type: banner.link_type ?? 'none',
      link_value: banner.link_value ?? '',
      display_order: banner.display_order ?? 0,
      is_active: banner.is_active ?? true,
      starts_at: banner.starts_at ? banner.starts_at.slice(0, 16) : '',
      ends_at: banner.ends_at ? banner.ends_at.slice(0, 16) : '',
    })
    setImageFile(null)
    setImagePreview(banner.image_url ?? null)
    setEditTarget(banner)
    setShowForm(true)
  }

  const handleImageChange = (e) => {
    const file = e.target.files?.[0]
    if (!file) return
    if (!file.type.startsWith('image/')) {
      showToast('Please select an image file', 'error')
      return
    }
    setImageFile(file)
    setImagePreview(URL.createObjectURL(file))
  }

  const validate = () => {
    if (!form.title.trim()) return 'Title is required'
    if (!editTarget && !imageFile && !form.image_url) return 'Image is required'
    if (form.link_type !== 'none' && !form.link_value.trim()) {
      return 'Link value is required when a link type is selected'
    }
    if (form.starts_at && form.ends_at && new Date(form.ends_at) <= new Date(form.starts_at)) {
      return 'End date must be after start date'
    }
    return null
  }

  const handleSubmit = async () => {
    const err = validate()
    if (err) {
      setValidationError(err)
      return
    }
    setValidationError('')
    setUploading(true)

    try {
      if (editTarget) {
        await updateBanner.mutateAsync({ id: editTarget.id, banner: form, imageFile })
        showToast('Banner updated')
      } else {
        await createBanner.mutateAsync({ banner: form, imageFile })
        showToast('Banner created')
      }
      setShowForm(false)
      resetForm()
    } catch (e) {
      showToast(e.message ?? 'Save failed', 'error')
    } finally {
      setUploading(false)
    }
  }

  const handleDelete = async () => {
    if (!deleteTarget) return
    try {
      await deleteBanner.mutateAsync(deleteTarget)
      showToast('Banner deleted')
      setDeleteTarget(null)
    } catch (e) {
      showToast(e.message ?? 'Delete failed', 'error')
    }
  }

  const handleMoveUp = async (index) => {
    if (index === 0 || !banners) return
    const ids = banners.map((b) => b.id)
    ;[ids[index - 1], ids[index]] = [ids[index], ids[index - 1]]
    try {
      await reorderBanners.mutateAsync(ids)
    } catch (e) {
      showToast(e.message ?? 'Reorder failed', 'error')
    }
  }

  const handleMoveDown = async (index) => {
    if (!banners || index >= banners.length - 1) return
    const ids = banners.map((b) => b.id)
    ;[ids[index], ids[index + 1]] = [ids[index + 1], ids[index]]
    try {
      await reorderBanners.mutateAsync(ids)
    } catch (e) {
      showToast(e.message ?? 'Reorder failed', 'error')
    }
  }

  const isSubmitting = createBanner.isPending || updateBanner.isPending || uploading

  // ─── Schedule status helper ──────────────────────────────────────

  const getScheduleLabel = (banner) => {
    const now = new Date()
    const start = banner.starts_at ? new Date(banner.starts_at) : null
    const end = banner.ends_at ? new Date(banner.ends_at) : null

    if (start && start > now) return { text: `Starts ${formatDateTime(banner.starts_at)}`, color: 'text-blue-600' }
    if (end && end < now) return { text: `Expired ${formatDateTime(banner.ends_at)}`, color: 'text-[#D64545]' }
    if (start && end) return { text: `${formatDateTime(banner.starts_at)} — ${formatDateTime(banner.ends_at)}`, color: 'text-[#6B5C4E]' }
    if (start) return { text: `Started ${formatDateTime(banner.starts_at)}`, color: 'text-[#6B5C4E]' }
    if (end) return { text: `Ends ${formatDateTime(banner.ends_at)}`, color: 'text-[#6B5C4E]' }
    return null
  }

  // ─── Render ──────────────────────────────────────────────────────

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="font-display text-2xl font-bold text-[#3B2314]">Banners</h1>
          <p className="text-sm text-[#6B5C4E]">Manage the home screen hero carousel</p>
        </div>
        <button
          type="button"
          onClick={openCreate}
          className="flex items-center gap-2 rounded-xl bg-[#8B5A2B] px-4 py-2.5 text-sm font-semibold text-white shadow-md transition-colors hover:bg-[#6B4423]"
        >
          <Plus size={16} />
          Add Banner
        </button>
      </div>

      {/* Loading */}
      {isLoading && (
        <div className="space-y-3">
          {[1, 2, 3].map((i) => (
            <div key={i} className="flex items-center gap-4 rounded-2xl border border-[#D9D0C7] bg-white p-4">
              <div className="h-20 w-32 animate-pulse rounded-xl bg-[#E8DDD5]" />
              <div className="flex-1 space-y-2">
                <div className="h-4 w-1/3 animate-pulse rounded bg-[#E8DDD5]" />
                <div className="h-3 w-1/4 animate-pulse rounded bg-[#E8DDD5]" />
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Error */}
      {isError && (
        <div className="rounded-2xl border border-[#D9D0C7] bg-white p-8 text-center">
          <p className="text-sm text-[#D64545]">{error.message}</p>
        </div>
      )}

      {/* Empty */}
      {!isLoading && !isError && banners?.length === 0 && (
        <EmptyState
          icon="🖼️"
          title="No banners yet"
          description="Create your first banner to display in the customer app's hero carousel."
        />
      )}

      {/* Banner list */}
      {!isLoading && !isError && banners && banners.length > 0 && (
        <div className="space-y-3">
          {banners.map((banner, index) => {
            const schedule = getScheduleLabel(banner)
            return (
              <div
                key={banner.id}
                className={`flex items-center gap-4 rounded-2xl border bg-white p-4 transition-colors ${
                  banner.is_active ? 'border-[#D9D0C7]' : 'border-[#D9D0C7] opacity-60'
                }`}
              >
                {/* Reorder controls */}
                <div className="flex flex-col gap-1">
                  <button
                    type="button"
                    onClick={() => handleMoveUp(index)}
                    disabled={index === 0}
                    className="rounded-lg p-1 text-[#6B5C4E] transition-colors hover:bg-[#F5F0EB] disabled:opacity-30"
                  >
                    <ChevronUp size={14} />
                  </button>
                  <button
                    type="button"
                    onClick={() => handleMoveDown(index)}
                    disabled={index === banners.length - 1}
                    className="rounded-lg p-1 text-[#6B5C4E] transition-colors hover:bg-[#F5F0EB] disabled:opacity-30"
                  >
                    <ChevronDown size={14} />
                  </button>
                </div>

                {/* Thumbnail */}
                <div className="h-20 w-32 flex-shrink-0 overflow-hidden rounded-xl bg-[#F5F0EB]">
                  {banner.image_url ? (
                    <img
                      src={banner.image_url}
                      alt={banner.title}
                      className="h-full w-full object-cover"
                    />
                  ) : (
                    <div className="flex h-full w-full items-center justify-center">
                      <ImageIcon size={20} className="text-[#D9D0C7]" />
                    </div>
                  )}
                </div>

                {/* Info */}
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <h3 className="truncate text-sm font-semibold text-[#3B2314]">{banner.title}</h3>
                    {!banner.is_active && (
                      <span className="inline-flex items-center gap-1 rounded-full bg-[#F5F0EB] px-2 py-0.5 text-[10px] font-medium text-[#6B5C4E]">
                        <EyeOff size={10} />
                        Inactive
                      </span>
                    )}
                    {banner.is_active && (
                      <span className="inline-flex items-center gap-1 rounded-full bg-green-50 px-2 py-0.5 text-[10px] font-medium text-green-700">
                        <Eye size={10} />
                        Active
                      </span>
                    )}
                  </div>
                  {banner.eyebrow_text && (
                    <p className="mt-0.5 text-xs text-[#6B5C4E]">{banner.eyebrow_text}</p>
                  )}
                  {schedule && (
                    <p className={`mt-0.5 flex items-center gap-1 text-xs ${schedule.color}`}>
                      <Calendar size={10} />
                      {schedule.text}
                    </p>
                  )}
                  {banner.link_type !== 'none' && (
                    <p className="mt-0.5 text-xs text-[#6B5C4E]">
                      Links to: {banner.link_type}
                      {banner.link_value ? ` → ${banner.link_value}` : ''}
                    </p>
                  )}
                </div>

                {/* Actions */}
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => openEdit(banner)}
                    className="rounded-xl border border-[#D9D0C7] p-2 text-[#6B5C4E] transition-colors hover:bg-[#F5F0EB]"
                  >
                    <Pencil size={14} />
                  </button>
                  <button
                    type="button"
                    onClick={() => setDeleteTarget(banner)}
                    className="rounded-xl border border-[#D9D0C7] p-2 text-[#D64545] transition-colors hover:bg-red-50"
                  >
                    <Trash2 size={14} />
                  </button>
                </div>
              </div>
            )
          })}
        </div>
      )}

      {/* ─── Create/Edit Form Modal ─────────────────────────────── */}
      <Modal
        open={showForm}
        onClose={() => { setShowForm(false); resetForm() }}
        title={editTarget ? 'Edit Banner' : 'Create Banner'}
        size="xl"
        footer={
          <>
            <button
              type="button"
              onClick={() => { setShowForm(false); resetForm() }}
              className="rounded-xl border border-[#D9D0C7] px-4 py-2 text-sm text-[#6B5C4E] hover:bg-[#F5F0EB]"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleSubmit}
              disabled={isSubmitting}
              className="rounded-xl bg-[#8B5A2B] px-5 py-2 text-sm font-semibold text-white shadow-md transition-colors hover:bg-[#6B4423] disabled:opacity-50"
            >
              {isSubmitting ? 'Saving…' : editTarget ? 'Save Changes' : 'Create Banner'}
            </button>
          </>
        }
      >
        <div className="space-y-5">
          {/* Validation error */}
          {validationError && (
            <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-[#D64545]">
              {validationError}
            </div>
          )}

          {/* Image upload */}
          <div>
            <label className="mb-1.5 block text-sm font-medium text-[#3B2314]">
              Banner Image {!editTarget && <span className="text-[#D64545]">*</span>}
            </label>
            <p className="mb-2 text-xs text-[#6B5C4E]">
              Recommended: 1200×630px (16:9 ratio). The image fills the hero background on mobile.
            </p>
            <div
              onClick={() => fileRef.current?.click()}
              className="flex h-40 cursor-pointer flex-col items-center justify-center rounded-xl border-2 border-dashed border-[#D9D0C7] bg-[#F5F0EB] transition-colors hover:border-[#8B5A2B]/40"
            >
              {imagePreview ? (
                <img src={imagePreview} alt="Preview" className="h-full w-full rounded-xl object-cover" />
              ) : (
                <>
                  <ImageIcon size={32} className="mb-2 text-[#D9D0C7]" />
                  <p className="text-sm text-[#6B5C4E]">Click to upload</p>
                  <p className="text-xs text-[#D9D0C7]">PNG, JPG, WebP</p>
                </>
              )}
            </div>
            <input
              ref={fileRef}
              type="file"
              accept="image/*"
              onChange={handleImageChange}
              className="hidden"
            />
          </div>

          {/* Title */}
          <div>
            <label className="mb-1.5 block text-sm font-medium text-[#3B2314]">
              Title <span className="text-[#D64545]">*</span>
            </label>
            <input
              type="text"
              value={form.title}
              onChange={(e) => setForm((f) => ({ ...f, title: e.target.value }))}
              placeholder="e.g. CRAFTED FOR FALL"
              className="w-full rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] placeholder-[#D9D0C7] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
            />
          </div>

          {/* Eyebrow text */}
          <div>
            <label className="mb-1.5 block text-sm font-medium text-[#3B2314]">Eyebrow Text</label>
            <input
              type="text"
              value={form.eyebrow_text}
              onChange={(e) => setForm((f) => ({ ...f, eyebrow_text: e.target.value }))}
              placeholder="e.g. NEW ARRIVALS"
              className="w-full rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] placeholder-[#D9D0C7] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
            />
          </div>

          {/* CTA label */}
          <div>
            <label className="mb-1.5 block text-sm font-medium text-[#3B2314]">CTA Label</label>
            <input
              type="text"
              value={form.cta_label}
              onChange={(e) => setForm((f) => ({ ...f, cta_label: e.target.value }))}
              placeholder="e.g. Shop Now"
              className="w-full rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] placeholder-[#D9D0C7] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
            />
          </div>

          {/* Link type + value */}
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="mb-1.5 block text-sm font-medium text-[#3B2314]">Link Type</label>
              <select
                value={form.link_type}
                onChange={(e) => setForm((f) => ({ ...f, link_type: e.target.value, link_value: '' }))}
                className="w-full rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]"
              >
                {LINK_TYPES.map((lt) => (
                  <option key={lt.value} value={lt.value}>{lt.label}</option>
                ))}
              </select>
            </div>

            {form.link_type === 'category' && (
              <div>
                <label className="mb-1.5 block text-sm font-medium text-[#3B2314]">
                  Category <span className="text-[#D64545]">*</span>
                </label>
                <select
                  value={form.link_value}
                  onChange={(e) => setForm((f) => ({ ...f, link_value: e.target.value }))}
                  className="w-full rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]"
                >
                  <option value="">Select category</option>
                  {CATEGORIES.filter((c) => c !== 'All').map((c) => (
                    <option key={c} value={c}>{c}</option>
                  ))}
                </select>
              </div>
            )}

            {form.link_type === 'product' && (
              <div>
                <label className="mb-1.5 block text-sm font-medium text-[#3B2314]">
                  Product ID <span className="text-[#D64545]">*</span>
                </label>
                <input
                  type="text"
                  value={form.link_value}
                  onChange={(e) => setForm((f) => ({ ...f, link_value: e.target.value }))}
                  placeholder="Product UUID"
                  className="w-full rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] placeholder-[#D9D0C7] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
                />
              </div>
            )}

            {form.link_type === 'url' && (
              <div>
                <label className="mb-1.5 block text-sm font-medium text-[#3B2314]">
                  URL <span className="text-[#D64545]">*</span>
                </label>
                <input
                  type="url"
                  value={form.link_value}
                  onChange={(e) => setForm((f) => ({ ...f, link_value: e.target.value }))}
                  placeholder="https://..."
                  className="w-full rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] placeholder-[#D9D0C7] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
                />
              </div>
            )}
          </div>

          {/* Active toggle */}
          <div className="flex items-center gap-3">
            <button
              type="button"
              onClick={() => setForm((f) => ({ ...f, is_active: !f.is_active }))}
              className={`relative h-6 w-11 rounded-full transition-colors ${
                form.is_active ? 'bg-[#8B5A2B]' : 'bg-[#D9D0C7]'
              }`}
            >
              <span
                className={`absolute top-0.5 h-5 w-5 rounded-full bg-white shadow-sm transition-transform ${
                  form.is_active ? 'translate-x-5.5 left-0.5' : 'left-0.5'
                }`}
                style={{ transform: form.is_active ? 'translateX(22px)' : 'translateX(2px)' }}
              />
            </button>
            <span className="text-sm text-[#3B2314]">
              {form.is_active ? 'Active' : 'Inactive'}
            </span>
          </div>

          {/* Schedule */}
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="mb-1.5 block text-sm font-medium text-[#3B2314]">Start Date</label>
              <input
                type="datetime-local"
                value={form.starts_at}
                onChange={(e) => setForm((f) => ({ ...f, starts_at: e.target.value }))}
                className="w-full rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]"
              />
            </div>
            <div>
              <label className="mb-1.5 block text-sm font-medium text-[#3B2314]">End Date</label>
              <input
                type="datetime-local"
                value={form.ends_at}
                onChange={(e) => setForm((f) => ({ ...f, ends_at: e.target.value }))}
                className="w-full rounded-xl border border-[#D9D0C7] bg-white px-4 py-2.5 text-sm text-[#3B2314] outline-none focus:border-[#8B5A2B]"
              />
            </div>
          </div>
          <p className="text-xs text-[#6B5C4E]">
            Leave both empty for a banner that's always active (when toggled on). Set dates to schedule
            a time window.
          </p>
        </div>
      </Modal>

      {/* ─── Delete Confirmation Modal ───────────────────────────── */}
      <Modal
        open={!!deleteTarget}
        onClose={() => setDeleteTarget(null)}
        title="Delete Banner"
        footer={
          <>
            <button
              type="button"
              onClick={() => setDeleteTarget(null)}
              className="rounded-xl border border-[#D9D0C7] px-4 py-2 text-sm text-[#6B5C4E] hover:bg-[#F5F0EB]"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleDelete}
              disabled={deleteBanner.isPending}
              className="rounded-xl border border-[#D64545] px-4 py-2 text-sm font-semibold text-[#D64545] transition-colors hover:bg-red-50 disabled:opacity-50"
            >
              {deleteBanner.isPending ? 'Deleting…' : 'Delete'}
            </button>
          </>
        }
      >
        <p className="text-sm text-[#6B5C4E]">
          Delete <strong className="text-[#3B2314]">{deleteTarget?.title}</strong>? This will remove
          the banner from the carousel and delete the uploaded image.
        </p>
      </Modal>
    </div>
  )
}
