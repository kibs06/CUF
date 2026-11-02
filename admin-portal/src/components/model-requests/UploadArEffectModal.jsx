import { useState } from 'react'
import { AlertTriangle, Check, Loader2, Sparkles } from 'lucide-react'
import Modal from '../ui/Modal.jsx'
import { useDeleteArEffect, useUploadArEffect } from '../../hooks/useArEffects.js'
import { describeError } from '../../lib/errors.js'
import { AR_EFFECT_CAP_BYTES } from '../../hooks/useArEffects.js'
import { formatBytes } from '../../lib/modelCompress.js'

// ─── Upload the product's AR effect ────────────────────────────────
//
// The `.deepar` Studio export for one product: picked here, stored in the
// `shoe-ar-effects` bucket, published as the product's live effect row in the
// same step. From then on both clients prefer it over their bundled effects —
// no chat handover, no release, no redeploy.
//
// What it deliberately does NOT do: judge the file. No validator can read a
// Studio binary, so the admin's own Studio preview is the review, and the
// upload lands `active` straight away. A later upload supersedes (higher
// version); the dialog also removes the live effect outright.

export default function UploadArEffectModal({ entry, current, onClose, onDone }) {
  const upload = useUploadArEffect()
  const remove = useDeleteArEffect()
  const [file, setFile] = useState(null)
  const [error, setError] = useState(null)

  const busy = upload.isPending || remove.isPending

  const reset = () => {
    setFile(null)
    setError(null)
  }

  const close = () => {
    if (busy) return
    reset()
    onClose?.()
  }

  const handleUpload = async () => {
    if (!file || !entry) return
    setError(null)
    try {
      const result = await upload.mutateAsync({
        productId: entry.productId,
        productName: entry.name,
        file,
      })
      reset()
      onDone?.(`AR effect v${result.version} is live on ${result.productName}.`)
    } catch (e) {
      setError(describeError(e, 'That effect could not be published.').message)
    }
  }

  const handleRemove = async () => {
    if (!current) return
    setError(null)
    try {
      await remove.mutateAsync({ rowId: current.id, storagePath: current.storage_path })
      reset()
      onDone?.(`The live AR effect is removed — ${entry?.name ?? 'that product'} falls back to its bundled effect, if it has one.`)
    } catch (e) {
      setError(describeError(e, 'That effect could not be removed.').message)
    }
  }

  return (
    <Modal
      open={!!entry}
      onClose={close}
      title="AR effect for fitting"
      footer={
        <>
          <button
            type="button"
            onClick={close}
            disabled={busy}
            className="rounded-xl border border-[#D9D0C7] px-4 py-2 text-sm text-[#6B5C4E] hover:bg-[#F5F0EB] disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={handleUpload}
            disabled={!file || busy}
            className="inline-flex items-center gap-2 rounded-xl bg-[#8B5A2B] px-5 py-2 text-sm font-semibold text-white shadow-md transition-colors hover:bg-[#6B4423] disabled:cursor-not-allowed disabled:opacity-50"
          >
            {upload.isPending ? (
              <>
                <Loader2 size={14} className="animate-spin" />
                Uploading…
              </>
            ) : (
              <>
                <Sparkles size={14} />
                Publish AR effect
              </>
            )}
          </button>
        </>
      }
    >
      <p className="mb-4 text-sm text-[#6B5C4E]">
        The DeepAR Studio export for{' '}
        <strong className="text-[#3B2314]">{entry?.name ?? 'this product'}</strong>. Publishing it
        here makes it live for every customer straight away — the app and the portal prefer it
        over their bundled effects, with no release in between.
      </p>

      {current && (
        <p className="mb-3 rounded-xl border border-[#F5F0EB] bg-[#FBF8F5] px-3 py-2 text-xs text-[#6B5C4E]">
          Live now: <strong className="text-[#3B2314]">version {current.version}</strong>
          {current.file_size_bytes
            ? ` · ${formatBytes(current.file_size_bytes)}`
            : ''}
          . A new upload supersedes it as the next version.
        </p>
      )}

      <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
        Choose a .deepar file
      </label>
      <input
        type="file"
        accept=".deepar"
        onChange={(e) => {
          setFile(e.target.files?.[0] ?? null)
          setError(null)
          upload.reset()
        }}
        className="w-full rounded-xl border border-[#D9D0C7] bg-white px-3 py-2 text-sm text-[#3B2314] file:mr-3 file:rounded-lg file:border-0 file:bg-[#8B5A2B] file:px-3 file:py-1.5 file:text-xs file:font-semibold file:text-white"
      />
      <p className="mt-1 text-xs text-[#6B5C4E]">
        Under {formatBytes(AR_EFFECT_CAP_BYTES)}, the export Studio produces. This is the file
        customers fit in.
      </p>

      {error && (
        <div
          className="mt-3 rounded-xl border px-4 py-3 text-sm text-[#6B5C4E]"
          style={{ borderColor: '#D64545', backgroundColor: '#FDF2F2' }}
        >
          <p className="flex items-center gap-2 font-semibold text-[#3B2314]">
            <AlertTriangle size={14} />
            That did not publish
          </p>
          <p className="mt-1 text-xs leading-relaxed">{error}</p>
        </div>
      )}

      {current && (
        <div className="mt-3 border-t border-[#F5F0EB] pt-3">
          <button
            type="button"
            onClick={handleRemove}
            disabled={busy}
            className="inline-flex items-center gap-2 rounded-xl border border-[#D64545] px-4 py-2 text-sm font-semibold text-[#D64545] transition-colors hover:bg-red-50 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {remove.isPending ? (
              <>
                <Loader2 size={14} className="animate-spin" />
                Removing…
              </>
            ) : (
              <>
                <Check size={14} />
                Remove the live effect
              </>
            )}
          </button>
        </div>
      )}
    </Modal>
  )
}
