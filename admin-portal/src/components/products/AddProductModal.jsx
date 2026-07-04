import { useState } from 'react'
import { X } from 'lucide-react'
import { supabase } from '../../lib/supabase'

export default function AddProductModal({ open, stores, onClose, onSuccess, onError }) {
  const [storeId, setStoreId] = useState('')
  const [name, setName] = useState('')
  const [price, setPrice] = useState('')
  const [category, setCategory] = useState('Casual')
  const [description, setDescription] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const resetForm = () => {
    setStoreId('')
    setName('')
    setPrice('')
    setCategory('Casual')
    setDescription('')
    setError('')
  }

  const handleClose = () => {
    resetForm()
    onClose()
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError('')

    if (!storeId || !name.trim() || !price) {
      setError('Please fill in all required fields.')
      return
    }

    const priceNum = Number(price)
    if (isNaN(priceNum) || priceNum < 0) {
      setError('Price must be a valid number.')
      return
    }

    setSaving(true)
    try {
      const { error: insertErr } = await supabase.from('products').insert({
        name: name.trim(),
        price: priceNum,
        category,
        description: description.trim() || null,
        store_id: storeId,
        is_published: true,
        is_featured: false,
      })

      if (insertErr) throw insertErr

      onSuccess?.()
      handleClose()
    } catch (err) {
      setError(err.message ?? 'Failed to add product.')
      onError?.(err)
    } finally {
      setSaving(false)
    }
  }

  if (!open) return null

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-[#3B2314]/40" onClick={handleClose} />
      <div className="relative z-10 w-full max-w-lg rounded-2xl bg-white shadow-2xl">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-[#F5F0EB] p-6">
          <h2 className="font-display text-xl font-bold text-[#3B2314]">Add Product</h2>
          <button
            type="button"
            onClick={handleClose}
            className="flex h-8 w-8 items-center justify-center rounded-lg transition-colors hover:bg-[#F5F0EB]"
          >
            <X size={16} className="text-[#6B5C4E]" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4 p-6">
          {/* Error message */}
          {error && (
            <div className="rounded-xl border border-[#D64545]/30 bg-[#D64545]/10 px-4 py-3 text-sm text-[#D64545]">
              {error}
            </div>
          )}

          {/* Store selector */}
          <div>
            <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
              Store *
            </label>
            <select
              value={storeId}
              onChange={(e) => setStoreId(e.target.value)}
              className="w-full rounded-xl border border-[#D9D0C7] bg-[#F5F0EB] px-4 py-2.5 text-sm text-[#3B2314] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
            >
              <option value="">Select a store...</option>
              {stores.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
            </select>
          </div>

          {/* Product name */}
          <div>
            <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
              Product Name *
            </label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="w-full rounded-xl border border-[#D9D0C7] bg-[#F5F0EB] px-4 py-2.5 text-sm text-[#3B2314] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
              placeholder="e.g. Handcrafted Leather Sandal"
            />
          </div>

          {/* Price + Category */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
                Price (₱) *
              </label>
              <input
                type="number"
                min="0"
                step="0.01"
                value={price}
                onChange={(e) => setPrice(e.target.value)}
                className="w-full rounded-xl border border-[#D9D0C7] bg-[#F5F0EB] px-4 py-2.5 font-mono text-sm text-[#3B2314] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
                placeholder="0.00"
              />
            </div>
            <div>
              <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
                Category *
              </label>
              <select
                value={category}
                onChange={(e) => setCategory(e.target.value)}
                className="w-full rounded-xl border border-[#D9D0C7] bg-[#F5F0EB] px-4 py-2.5 text-sm text-[#3B2314] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
              >
                <option>Casual</option>
                <option>Formal</option>
                <option>Sports</option>
                <option>Sandals</option>
                <option>Custom</option>
              </select>
            </div>
          </div>

          {/* Description */}
          <div>
            <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
              Description
            </label>
            <textarea
              rows={3}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              className="w-full resize-none rounded-xl border border-[#D9D0C7] bg-[#F5F0EB] px-4 py-2.5 text-sm text-[#3B2314] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
              placeholder="Describe the product..."
            />
          </div>

          {/* Action buttons */}
          <div className="flex gap-3 pt-2">
            <button
              type="button"
              onClick={handleClose}
              className="flex-1 rounded-xl border border-[#D9D0C7] py-2.5 text-sm font-semibold text-[#6B5C4E] transition-colors hover:bg-[#F5F0EB]"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={saving}
              className="flex-1 rounded-xl bg-[#8B5A2B] py-2.5 text-sm font-semibold text-white transition-colors hover:bg-[#6B4520] disabled:opacity-50"
            >
              {saving ? 'Saving...' : 'Save Product'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
