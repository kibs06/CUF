import { useMemo, useState } from 'react'
import { AlertTriangle, Check, Cuboid, Hand, Loader2, MoreVertical, Package, Ruler, Sparkles, Upload } from 'lucide-react'
import Badge from '../components/ui/Badge.jsx'
import EmptyState from '../components/ui/EmptyState.jsx'
import Modal from '../components/ui/Modal.jsx'
import { useToast } from '../components/ui/Toast.jsx'
import {
  CLOSED_STATUSES,
  OPEN_STATUSES,
  REQUEST_STATUS,
  useClaimModelRequest,
  useDeclineModelRequest,
  useDeleteProductModel,
  useFulfilModelRequest,
  useModelRequests,
  useModelledProducts,
  useProductModels,
} from '../hooks/useModelRequests.js'
import UploadModelModal from '../components/model-requests/UploadModelModal.jsx'
import UploadArEffectModal from '../components/model-requests/UploadArEffectModal.jsx'
import ProductPhotosDialog, { orderedPhotos } from '../components/model-requests/ProductPhotosDialog.jsx'
import ModelledProductMenu from '../components/model-requests/ModelledProductMenu.jsx'
import { useArEffects } from '../hooks/useArEffects.js'
import { supabase } from '../lib/supabase.js'
import { MODEL_BUCKET } from '../lib/modelPublish.js'
import ModelViewerDialog from '../components/products/ModelViewerDialog.jsx'
import { useDeviceGate } from '../hooks/useDeviceGate.js'
import { describeError } from '../lib/errors.js'
import { MODEL_UPLOAD_ENABLED, formatDateTime } from '../lib/constants.js'
// ⚠️ P3: every "the seller has been told" in this page comes from one module,
// because the claim is about SQL this page does not own — see `askDelivery.js`
// and the contract test beside it.
import {
  NOTICE_NOT_READABLE_SENTENCE,
  declineDeliverySentence,
  declineHeadline,
  deliveryHeadline,
  noteReachesSeller,
} from '../lib/askDelivery.js'
import { MODELLING_ENDING } from '../lib/modelPublish.js'

// The three buckets the Flutter queue uses. Same names on purpose: an admin who
// has used the app should not have to learn a second vocabulary for the same
// rows, and the counts mean the same thing in both places.
const TABS = [
  { key: 'waiting', label: 'Waiting', statuses: OPEN_STATUSES },
  { key: 'fulfilled', label: 'Fulfilled', statuses: [REQUEST_STATUS.FULFILLED] },
  { key: 'closed', label: 'Closed', statuses: CLOSED_STATUSES },
]

// Not a queue: every product with a live model, the admin's answer to "what can
// customers spin and fit right now". Rendered beside the queues because the two
// halves of this page are one workflow — a fulfilled ask lands its product here.
const MODELS_TAB = { key: 'models', label: '3D products' }

// ─── Small display helpers ─────────────────────────────────────────

const mm = (value) => (value == null ? null : `${Number(value).toFixed(1)} mm`)

// 42 rather than 42.0 — a EU size is a label, not a measurement. `measured_size_eu`
// is numeric in the database, so it arrives as 42 or 42.5 and must not be padded.
const size = (value) => (value == null ? null : `${Number(value)}`)

const statusLabel = (status) =>
  ({
    [REQUEST_STATUS.REQUESTED]: 'Waiting',
    [REQUEST_STATUS.IN_PROGRESS]: "I'll do it",
    [REQUEST_STATUS.FULFILLED]: 'Fulfilled',
    [REQUEST_STATUS.DECLINED]: 'Declined',
    [REQUEST_STATUS.CANCELLED]: 'Withdrawn',
  })[status] ?? status

// The Badge's tones are shared with order statuses, where `cancelled` is red for
// a cancelled *order*. A seller withdrawing their own ask is not the same news as
// the team refusing it, and the two must not be the same colour, so a withdrawal
// borrows the neutral tone already used for "nothing to worry about".
const statusVariant = (status) =>
  status === REQUEST_STATUS.CANCELLED ? 'dismissed' : status

// ─── The shelf's own header ────────────────────────────────────────
//
// The two numbers this tab exists to answer: how many products customers can
// spin and fit right now, and how many of them also fit in AR. The helper line
// keeps the two viewers straight (photo grid vs the model itself), because a
// new admin otherwise opens the wrong one first.
function ShelfSummary({ modelled, arCount }) {
  const total = modelled.length
  const withAr = Math.min(arCount, total)
  return (
    <div className="relative mb-4 overflow-hidden rounded-3xl bg-[#3B2314] px-6 py-5 text-white shadow-[0_18px_40px_-24px_rgba(59,35,20,0.6)]">
      {/* Warm light leaks — depth without leaving the palette. */}
      <div aria-hidden="true" className="pointer-events-none absolute -right-16 -top-24 h-56 w-56 rounded-full bg-[#8B5A2B]/40 blur-3xl" />
      <div aria-hidden="true" className="pointer-events-none absolute -bottom-28 left-1/3 h-48 w-48 rounded-full bg-[#E8A020]/20 blur-3xl" />
      <div className="relative flex flex-wrap items-center justify-between gap-4">
        <div className="min-w-0">
          <p className="text-[11px] font-bold uppercase tracking-[0.18em] text-[#E8CFA8]">
            Live shelf
          </p>
          <p className="mt-1 font-display text-xl font-bold leading-snug">
            {total} {total === 1 ? 'product' : 'products'} customers can spin and fit
          </p>
          <p className="mt-1 max-w-xl text-xs leading-relaxed text-white/70">
            The same live file the app renders. The photo opens all of the
            product&apos;s pictures; <strong className="text-white">View 3D</strong> opens
            the model itself.
          </p>
        </div>
        <div className="flex shrink-0 items-center gap-2">
          <span className="inline-flex items-center gap-1.5 rounded-2xl bg-white/10 px-3.5 py-2 text-xs font-semibold ring-1 ring-white/15 backdrop-blur">
            <Cuboid size={13} className="text-[#E8CFA8]" />
            <span className="tabular-nums">{total} live</span>
          </span>
          <span className="inline-flex items-center gap-1.5 rounded-2xl bg-[#4ECDC4]/15 px-3.5 py-2 text-xs font-semibold ring-1 ring-[#4ECDC4]/30 backdrop-blur">
            <Sparkles size={13} className="text-[#4ECDC4]" />
            <span className="tabular-nums">{withAr} AR fit</span>
          </span>
        </div>
      </div>
    </div>
  )
}

// A seller measures the OUTSIDE of the pair (the number the renderer scales to),
// which is why these are labelled "external" here and never called a last length:
// `products.last_length_mm` is the INTERNAL last the fit verdict compares, and
// the two differ by 8–15 mm (SHOE_MODEL_AUTHORING_GUIDE.md §5).
function Measurement({ label, value, icon: Icon }) {
  if (value == null) return null
  return (
    <div className="rounded-xl border border-[#EFE7DF] bg-[#FBF8F5] px-4 py-3">
      <div className="flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wider text-[#6B5C4E]">
        {Icon && <Icon size={12} className="text-[#8B5A2B]" />}
        {label}
      </div>
      <p className="mt-1 font-display text-lg font-bold tabular-nums text-[#3B2314]">{value}</p>
    </div>
  )
}

export default function ModelRequests() {
  const [tab, setTab] = useState('waiting')
  const [fulfilTarget, setFulfilTarget] = useState(null)
  const [photoTarget, setPhotoTarget] = useState(null)
  const [uploadTarget, setUploadTarget] = useState(null)
  const [declineTarget, setDeclineTarget] = useState(null)
  const [declineReason, setDeclineReason] = useState('')
  const [busyId, setBusyId] = useState(null)
  const { showToast } = useToast()

  const { data, isLoading, isError, error } = useModelRequests()
  const claim = useClaimModelRequest()
  const fulfil = useFulfilModelRequest()
  const decline = useDeclineModelRequest()
  const modelledQuery = useModelledProducts()
  const [viewingModel, setViewingModel] = useState(null)
  // The shelf's right-click menu, and the delete it can ask for. The menu
  // only points; the page owns every action, so `menu` is just coordinates
  // plus the entry under the cursor.
  const [menu, setMenu] = useState(null)
  const [deleteTarget, setDeleteTarget] = useState(null)
  // Shelf replace without a queue row: `{ entry, storeId }`. The pipeline
  // needs the store for the object path and the entry only carries the
  // product, so the store is read once when the menu item is picked.
  const [replaceTarget, setReplaceTarget] = useState(null)
  const [arTarget, setArTarget] = useState(null)
  const del = useDeleteProductModel()
  // One read for the whole shelf: which products carry a live uploaded
  // effect, so the menu can name the version it would replace.
  const arEffectsQuery = useArEffects()
  const arByProduct = useMemo(() => {
    const map = new Map()
    for (const row of arEffectsQuery.data ?? []) {
      if (!map.has(row.product_id)) map.set(row.product_id, row)
    }
    return map
  }, [arEffectsQuery.data])

  const rows = useMemo(() => data ?? [], [data])
  const modelled = useMemo(() => modelledQuery.data ?? [], [modelledQuery.data])

  // ⚠️ There are two ways to see nothing here and they are not the same news.
  // The device gate hides ROWS rather than raising, so an empty queue is
  // ambiguous by construction — "Nothing waiting" is the one sentence an admin
  // must not be told when the truth is "this session is not an admin's". The
  // probe is only asked for once the list has actually come back empty, which
  // is what `enabled` is doing.
  const queueError = isError
    ? describeError(error, 'Could not load the model-request queue.')
    : null
  const gate = useDeviceGate({ enabled: !isLoading && !isError && rows.length === 0 })
  const gatedEmpty = !isLoading && !isError && rows.length === 0 && gate.data === false

  const byStatus = (statuses) => rows.filter((r) => statuses.includes(r.status))

  const counts = useMemo(
    () => ({
      waiting: rows.filter((r) => OPEN_STATUSES.includes(r.status)).length,
      fulfilled: rows.filter((r) => r.status === REQUEST_STATUS.FULFILLED).length,
      closed: rows.filter((r) => CLOSED_STATUSES.includes(r.status)).length,
      models: modelled.length,
    }),
    [rows, modelled],
  )

  const isModelsTab = tab === MODELS_TAB.key

  // ─── The shelf menu's actions ───────────────────────────────────
  // View and photos reuse the dialogs the queue rows open; download and copy
  // work on the live file (the same public object customers fetch); delete
  // goes through its own confirm first.
  const openViewerFor = (entry) =>
    setViewingModel({
      title: entry.name,
      storagePath: entry.model.storage_path,
      status: entry.model.status,
      version: entry.model.version,
    })

  const openPhotosFor = (entry) =>
    setPhotoTarget({
      id: `model-${entry.productId}`,
      products: { name: entry.name, product_images: entry.images },
    })

  const downloadForEdit = async (entry) => {
    try {
      const { data, error } = await supabase.storage
        .from(MODEL_BUCKET)
        .download(entry.model.storage_path)
      if (error) throw error
      const url = URL.createObjectURL(data)
      const a = document.createElement('a')
      a.href = url
      a.download = `${entry.name} v${entry.model.version}.glb`
      document.body.appendChild(a)
      a.click()
      a.remove()
      URL.revokeObjectURL(url)
      showToast(
        'Downloaded — edit it in Blender, then re-upload the fixed file with “Replace live model…” from this card’s menu.',
      )
    } catch (e) {
      showToast(describeError(e, 'That file could not be downloaded.').message, 'error')
    }
  }

  const copyPublicLink = async (entry) => {
    const url = supabase.storage.from(MODEL_BUCKET).getPublicUrl(entry.model.storage_path)
      .data.publicUrl
    // The async clipboard API needs a focused tab with permission; the
    // textarea fallback covers the cases where it refuses.
    try {
      await navigator.clipboard.writeText(url)
    } catch {
      const area = document.createElement('textarea')
      area.value = url
      document.body.appendChild(area)
      area.select()
      document.execCommand('copy')
      area.remove()
    }
    showToast('Public link copied — it downloads the exact file customers get.')
  }

  // Shelf replace without a queue row: the pipeline needs the store for the
  // object path and the entry only carries the product — one read fills it,
  // and a failure is a toast rather than a modal that cannot publish.
  const startReplace = async (entry) => {
    if (!MODEL_UPLOAD_ENABLED) {
      showToast('Model uploads are disabled in this build.', 'error')
      return
    }
    try {
      const { data, error } = await supabase
        .from('products')
        .select('store_id')
        .eq('id', entry.productId)
        .single()
      if (error) throw error
      if (!data?.store_id) throw new Error('That product has no store to publish under.')
      setReplaceTarget({ entry, storeId: data.store_id })
    } catch (e) {
      showToast(describeError(e, 'Could not open the replacement upload.').message, 'error')
    }
  }

  const handleMenuPick = (action, entry) => {
    const ar = menu?.ar ?? null
    setMenu(null)
    if (!entry) return
    if (action === 'view') openViewerFor(entry)
    else if (action === 'photos') openPhotosFor(entry)
    else if (action === 'download') void downloadForEdit(entry)
    else if (action === 'copy') void copyPublicLink(entry)
    else if (action === 'upload-ar') setArTarget({ entry, current: ar })
    else if (action === 'replace') void startReplace(entry)
    else if (action === 'delete') setDeleteTarget(entry)
  }

  const handleDeleteConfirm = async () => {
    if (!deleteTarget) return
    try {
      await del.mutateAsync({
        modelId: deleteTarget.model.id,
        storagePath: deleteTarget.model.storage_path,
      })
      showToast(
        `Version ${deleteTarget.model.version} of ${deleteTarget.name} deleted — file and row.`,
      )
      setDeleteTarget(null)
    } catch (e) {
      showToast(describeError(e, 'That model could not be deleted.').message, 'error')
    }
  }

  const activeTab = TABS.find((t) => t.key === tab) ?? TABS[0]
  const visible = byStatus(activeTab.statuses)

  const handleClaim = async (row) => {
    setBusyId(row.id)
    try {
      await claim.mutateAsync(row.id)
      showToast(`You are now on ${row.products?.name ?? 'that request'}`)
    } catch (e) {
      showToast(describeError(e, 'Could not claim that request').message, 'error')
    } finally {
      setBusyId(null)
    }
  }

  const handleFulfil = async (modelId, note) => {
    if (!fulfilTarget || modelId == null) return
    setBusyId(fulfilTarget.id)
    try {
      await fulfil.mutateAsync({ requestId: fulfilTarget.id, modelId, note })
      // The RPC wrote the notice inside the transaction that set `fulfilled`, so
      // this claim is the database's rather than this page's (P3).
      showToast(`Request closed. ${deliveryHeadline(MODELLING_ENDING.CLOSED)}`)
      setFulfilTarget(null)
    } catch (e) {
      showToast(describeError(e, 'Could not close that request').message, 'error')
    } finally {
      setBusyId(null)
    }
  }

  const handleDecline = async () => {
    if (!declineTarget || !declineReason.trim()) return
    setBusyId(declineTarget.id)
    try {
      await decline.mutateAsync({ requestId: declineTarget.id, reason: declineReason })
      // Same rule: `decline_shoe_model_request` carries the reason into the
      // seller's notice, so an empty field is refused here AND reads as nothing
      // to act on there.
      showToast(`Request declined. ${declineHeadline()}`)
      setDeclineTarget(null)
      setDeclineReason('')
    } catch (e) {
      showToast(describeError(e, 'Could not decline that request').message, 'error')
    } finally {
      setBusyId(null)
    }
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="font-display text-2xl font-bold text-[#3B2314]">3D Fitting Requests</h1>
          <p className="mt-1 max-w-2xl text-sm text-[#6B5C4E]">
            Sellers who cannot produce a compliant <code>.glb</code> measure the pair with a ruler
            instead, and the team models it. <strong className="text-[#3B2314]">Closing one as
            done names a live model of that product</strong> — there is no way to close an ask by
            setting a status.
          </p>
        </div>
        {counts.waiting > 0 && (
          <div className="rounded-xl border border-[#E8A020]/40 bg-[#E8A020]/10 px-4 py-2.5">
            <p className="text-xs uppercase tracking-wider text-[#6B5C4E]">Waiting</p>
            <p className="font-display text-xl font-bold text-[#3B2314]">{counts.waiting}</p>
          </div>
        )}
      </div>

      {/* Tabs */}
      <div
        role="tablist"
        aria-label="Request queues"
        className="inline-flex flex-wrap gap-1 rounded-2xl border border-[#D9D0C7] bg-white p-1"
      >
        {[...TABS, MODELS_TAB].map((t) => {
          const selected = tab === t.key
          return (
            <button
              key={t.key}
              type="button"
              role="tab"
              aria-selected={selected}
              onClick={() => setTab(t.key)}
              className={`inline-flex items-center gap-2 rounded-xl px-4 py-2 text-sm font-medium transition-all ${
                selected
                  ? 'bg-[#8B5A2B] text-white shadow-sm'
                  : 'text-[#6B5C4E] hover:bg-[#F5F0EB] hover:text-[#3B2314]'
              }`}
            >
              {t.label}
              <span
                className={`min-w-[1.5rem] rounded-full px-1.5 py-0.5 text-center text-xs font-semibold tabular-nums ${
                  selected ? 'bg-white/20 text-white' : 'bg-[#F5F0EB] text-[#6B5C4E]'
                }`}
              >
                {counts[t.key]}
              </span>
            </button>
          )
        })}
      </div>

      {/* Loading */}
      {isLoading && (
        <div className="space-y-3">
          {[1, 2, 3].map((i) => (
            <div key={i} className="space-y-3 rounded-2xl border border-[#D9D0C7] bg-white p-5">
              <div className="h-4 w-48 animate-pulse rounded bg-[#E8DDD5]" />
              <div className="h-3 w-72 animate-pulse rounded bg-[#E8DDD5]" />
              <div className="h-10 w-full animate-pulse rounded-xl bg-[#F5F0EB]" />
            </div>
          ))}
        </div>
      )}

      {/* Error — the sentence first, the server's own words under it */}
      {isError && (
        <div className="rounded-2xl border border-[#D9D0C7] bg-white p-8 text-center">
          <p className="text-sm font-semibold text-[#D64545]">{queueError.message}</p>
          {queueError.detail && queueError.detail !== queueError.message && (
            <p className="mt-2 text-xs text-[#6B5C4E]">The server said: {queueError.detail}</p>
          )}
        </div>
      )}

      {/* Empty because it is HIDDEN, which is not the same as empty */}
      {gatedEmpty && (
        <EmptyState
          Icon={AlertTriangle}
          title="The server is not showing this queue"
          description="This session is signed in, but the database does not treat it as an admin's — and the device gate hides rows instead of raising, so this reads empty rather than refused. Sign out and back in; if it persists, check the account's role."
        />
      )}

      {/* Empty for the ordinary reason */}
      {!isModelsTab && !isLoading && !isError && visible.length === 0 && !gatedEmpty && (
        <EmptyState
          Icon={Cuboid}
          title={tab === 'waiting' ? 'Nothing waiting' : 'Nothing here yet'}
          description={
            tab === 'waiting'
              ? 'Requests appear here the moment a seller files one from the product’s actions in the app.'
              : 'Closed requests stay here as the history of what the team made and what it could not.'
          }
        />
      )}

      {/* Rows */}
      {!isModelsTab && !isLoading && !isError && visible.length > 0 && (
        <div className="space-y-3">
          {visible.map((row) => {
            const isOpen = OPEN_STATUSES.includes(row.status)
            const claimed = !!row.assigned_to
            // The admin models from this photo, so the row carries the
            // product's own primary image (first image when none is marked
            // primary) — the same pick the product list uses.
            const productImage =
              row.products?.product_images?.find((i) => i.is_primary)?.image_url ??
              row.products?.product_images?.[0]?.image_url ??
              null
            return (
              <div
                key={row.id}
                className={`rounded-2xl border border-[#D9D0C7] bg-white p-5 transition-shadow hover:shadow-md ${
                  isOpen ? 'border-l-4 border-l-[#E8A020]' : ''
                }`}
              >
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div className="flex min-w-0 items-start gap-3">
                    {productImage ? (
                      <button
                        type="button"
                        onClick={() => setPhotoTarget(row)}
                        title="View all product photos"
                        aria-label={`View photos of ${row.products?.name ?? 'this product'}`}
                        className="h-14 w-14 flex-shrink-0 overflow-hidden rounded-xl bg-[#E8DDD5] transition-shadow hover:shadow-md hover:ring-2 hover:ring-[#8B5A2B]/40"
                      >
                        <img
                          src={productImage}
                          className="h-full w-full object-cover"
                          alt={row.products?.name ?? 'Product photo'}
                        />
                      </button>
                    ) : (
                      <div className="h-14 w-14 flex-shrink-0 overflow-hidden rounded-xl bg-[#E8DDD5]">
                        <div className="flex h-full w-full items-center justify-center">
                          <Package size={20} className="text-[#8B5A2B]/30" />
                        </div>
                      </div>
                    )}
                    <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-2">
                      <h3 className="text-sm font-semibold text-[#3B2314]">
                        {row.products?.name ?? 'Product removed'}
                      </h3>
                      <Badge label={statusLabel(row.status)} variant={statusVariant(row.status)} />
                      {isOpen && claimed && (
                        <span className="inline-flex items-center gap-1 rounded-full bg-blue-50 px-2 py-0.5 text-[10px] font-medium text-blue-700">
                          <Hand size={10} />
                          Claimed
                        </span>
                      )}
                    </div>
                    <p className="mt-1 text-xs text-[#6B5C4E]">
                      {row.stores?.name ?? 'Unknown store'} · asked {formatDateTime(row.created_at)}
                    </p>
                    </div>
                  </div>

                  {isOpen && (
                    <div className="flex flex-wrap items-center gap-2">
                      {/* P2 (V2.11), and the action this queue was missing: without it
                          "Close as done" could only ever point at a model somebody else
                          had already published. Dark by default — see
                          `MODEL_UPLOAD_ENABLED`. Offered whether or not somebody has
                          claimed the ask: claiming says whose desk it is, it does not
                          put the file out of anyone else's reach. */}
                      {MODEL_UPLOAD_ENABLED && (
                        <button
                          type="button"
                          disabled={busyId === row.id}
                          onClick={() => setUploadTarget(row)}
                          className="inline-flex items-center gap-1.5 rounded-lg bg-[#8B5A2B] px-3 py-1.5 text-xs font-semibold text-white transition-colors hover:bg-[#6B4423] disabled:opacity-50"
                        >
                          <Upload size={13} />
                          Upload a model
                        </button>
                      )}
                      {!claimed && (
                        <button
                          type="button"
                          disabled={busyId === row.id}
                          onClick={() => handleClaim(row)}
                          className="inline-flex items-center gap-1.5 rounded-lg border border-[#8B5A2B] px-3 py-1.5 text-xs font-semibold text-[#8B5A2B] transition-colors hover:bg-[#8B5A2B]/10 disabled:opacity-50"
                        >
                          {busyId === row.id && claim.isPending ? (
                            <Loader2 size={13} className="animate-spin" />
                          ) : (
                            <Hand size={13} />
                          )}
                          I&apos;ll do it
                        </button>
                      )}
                      <button
                        type="button"
                        disabled={busyId === row.id}
                        onClick={() => setFulfilTarget(row)}
                        className="inline-flex items-center gap-1.5 rounded-lg bg-[#4ECDC4] px-3 py-1.5 text-xs font-semibold text-white transition-colors hover:bg-teal-600 disabled:opacity-50"
                      >
                        <Check size={13} />
                        Close as done
                      </button>
                      <button
                        type="button"
                        disabled={busyId === row.id}
                        onClick={() => setDeclineTarget(row)}
                        className="rounded-lg border border-[#D64545] px-3 py-1.5 text-xs font-semibold text-[#D64545] transition-colors hover:bg-red-50 disabled:opacity-50"
                      >
                        Decline
                      </button>
                    </div>
                  )}
                </div>

                {/* The seller's half: what they measured, with a ruler. */}
                <div className="mt-4 grid grid-cols-2 gap-2 md:grid-cols-4">
                  <Measurement
                    label="External length"
                    value={mm(row.external_length_mm)}
                    icon={Ruler}
                  />
                  <Measurement label="External width" value={mm(row.external_width_mm)} />
                  <Measurement label="Heel" value={mm(row.heel_height_mm)} />
                  <Measurement label="Measured size" value={size(row.measured_size_eu)} />
                </div>

                {row.note && (
                  <p className="mt-3 rounded-xl bg-[#F5F0EB] px-3 py-2 text-xs text-[#6B5C4E]">
                    <strong className="text-[#3B2314]">Seller&apos;s note:</strong> {row.note}
                  </p>
                )}

                {/* The team's half, once there is one. */}
                {row.admin_note && (
                  <p className="mt-2 rounded-xl border border-[#D9D0C7] px-3 py-2 text-xs text-[#6B5C4E]">
                    <strong className="text-[#3B2314]">
                      {row.status === REQUEST_STATUS.DECLINED ? 'Reason sent' : 'Note sent'}:
                    </strong>{' '}
                    {row.admin_note}
                  </p>
                )}
                {row.reviewed_at && (
                  <p className="mt-2 text-[11px] text-[#6B5C4E]">
                    Closed {formatDateTime(row.reviewed_at)}
                  </p>
                )}
              </div>
            )
          })}
        </div>
      )}

      {/* ─── 3D products: every product with a live model ─────────────
          The shelf beside the queue: a fulfilled ask lands its product here,
          and this is the same live file the app's preview renders — drag to
          turn, scroll to zoom, exactly what a customer gets. */}
      {isModelsTab && modelledQuery.isLoading && (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {[1, 2, 3].map((i) => (
            <div key={i} className="rounded-3xl border border-[#E5DACA] bg-white p-5">
              <div className="flex items-start gap-4">
                <div className="h-20 w-20 animate-pulse rounded-2xl bg-[#EFE3D3]" />
                <div className="flex-1 space-y-2 pt-1">
                  <div className="h-4 w-24 animate-pulse rounded-full bg-[#EFE3D3]" />
                  <div className="h-4 w-40 animate-pulse rounded bg-[#EFE3D3]" />
                  <div className="h-3 w-32 animate-pulse rounded bg-[#F5F0EB]" />
                </div>
              </div>
              <div className="mt-4 h-9 animate-pulse rounded-xl bg-[#F5F0EB]" />
            </div>
          ))}
        </div>
      )}

      {isModelsTab && modelledQuery.isError && (
        <div className="rounded-2xl border border-[#D9D0C7] bg-white p-8 text-center">
          <p className="text-sm font-semibold text-[#D64545]">
            {describeError(modelledQuery.error, 'Could not load the products with 3D models.')
              .message}
          </p>
        </div>
      )}

      {isModelsTab && !modelledQuery.isLoading && !modelledQuery.isError && modelled.length === 0 && (
        <EmptyState
          Icon={Cuboid}
          title="No live 3D models yet"
          description="Publish a model against a request and its product lands here. This shelf is every product customers can spin and fit in the app right now."
        />
      )}

      {isModelsTab && !modelledQuery.isLoading && !modelledQuery.isError && modelled.length > 0 && (
        <div>
          {/* The shelf's own header: what is live, and how much of it fits —
              the two numbers this tab exists to answer. */}
          <ShelfSummary modelled={modelled} arCount={arByProduct.size} />
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {modelled.map((entry, index) => {
              const image =
                orderedPhotos(entry.images).find((p) => p?.image_url)?.image_url ?? null
              const hasAr = arByProduct.has(entry.productId)
              return (
                <div
                  key={entry.productId}
                  onContextMenu={(e) => {
                    e.preventDefault()
                    setMenu({ entry, x: e.clientX, y: e.clientY, ar: arByProduct.get(entry.productId) ?? null })
                  }}
                  style={{ animationDelay: `${Math.min(index * 70, 420)}ms` }}
                  className="shelf-card group relative overflow-hidden rounded-3xl border border-[#E5DACA] bg-white p-5 transition-all duration-200 hover:-translate-y-1 hover:border-[#8B5A2B]/50 hover:shadow-[0_18px_40px_-18px_rgba(59,35,20,0.35)] focus-within:border-[#8B5A2B]/50"
                >
                  {/* Warm top glow on hover — depth without leaving the palette. */}
                  <div
                    aria-hidden="true"
                    className="pointer-events-none absolute inset-x-0 top-0 h-20 bg-gradient-to-b from-[#F5E9D6]/0 via-[#F5E9D6]/0 to-transparent opacity-0 transition-opacity duration-200 group-hover:opacity-100"
                  />
                  <div className="relative flex min-w-0 items-start gap-4">
                    {image ? (
                      <button
                        type="button"
                        onClick={() =>
                          setPhotoTarget({
                            id: `model-${entry.productId}`,
                            products: { name: entry.name, product_images: entry.images },
                          })
                        }
                        title="View all product photos"
                        aria-label={`View photos of ${entry.name}`}
                        className="h-20 w-20 flex-shrink-0 overflow-hidden rounded-2xl bg-gradient-to-br from-[#EFE3D3] to-[#E2D2BD] ring-1 ring-[#E5DACA] transition-all hover:shadow-lg hover:ring-2 hover:ring-[#8B5A2B]/50"
                      >
                        <img
                          src={image}
                          className="h-full w-full object-cover transition-transform duration-300 group-hover:scale-[1.06]"
                          alt={entry.name}
                          loading="lazy"
                        />
                      </button>
                    ) : (
                      <div className="flex h-20 w-20 flex-shrink-0 items-center justify-center overflow-hidden rounded-2xl bg-gradient-to-br from-[#EFE3D3] to-[#E2D2BD] ring-1 ring-[#E5DACA]">
                        <Package size={24} className="text-[#8B5A2B]/30" />
                      </div>
                    )}
                    <div className="min-w-0 flex-1 pt-0.5">
                      <div className="flex flex-wrap items-center gap-1.5">
                        <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider text-emerald-700 ring-1 ring-emerald-600/20">
                          <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
                          Live
                        </span>
                        {hasAr && (
                          <span className="inline-flex items-center gap-1 rounded-full bg-[#4ECDC4]/15 px-2 py-0.5 text-[10px] font-semibold text-teal-700 ring-1 ring-teal-600/20">
                            <Sparkles size={10} />
                            AR fit
                          </span>
                        )}
                      </div>
                      <h3 className="mt-1.5 font-display text-[15px] font-bold leading-snug text-[#3B2314]">{entry.name}</h3>
                      <p className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-xs tabular-nums text-[#6B5C4E]">
                        <span className="inline-flex items-center rounded-md bg-[#F5F0EB] px-1.5 py-0.5 font-semibold text-[#8B5A2B]">
                          v{entry.model.version}
                        </span>
                        {entry.model.authored_length_mm != null && (
                          <span className="inline-flex items-center gap-1">
                            <Ruler size={11} className="text-[#8B5A2B]/60" />
                            {Number(entry.model.authored_length_mm).toFixed(1)} mm
                          </span>
                        )}
                        {entry.model.authored_size_eu != null && (
                          <span>EU {Number(entry.model.authored_size_eu)}</span>
                        )}
                      </p>
                    </div>
                  </div>
                  <div className="relative mt-4 flex gap-2">
                    <button
                      type="button"
                      onClick={() => openViewerFor(entry)}
                      className="inline-flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-[#8B5A2B] px-3 py-2 text-xs font-bold text-white shadow-sm transition-all hover:bg-[#6B4423] hover:shadow-md active:scale-[0.99]"
                    >
                      <Cuboid size={14} />
                      View 3D
                    </button>
                    {/* The same menu as right-click, for trackpads and touch:
                        no admin should need to discover a hidden gesture. */}
                    <button
                      type="button"
                      aria-label={`More actions for ${entry.name}`}
                      title="More actions"
                      onClick={(e) => setMenu({ entry, x: e.clientX, y: e.clientY, ar: arByProduct.get(entry.productId) ?? null })}
                      className="shrink-0 rounded-xl border border-[#E5DACA] bg-[#FBF8F5] px-3 py-2 text-[#6B5C4E] transition-colors hover:border-[#8B5A2B]/50 hover:bg-[#F5F0EB] hover:text-[#3B2314]"
                    >
                      <MoreVertical size={15} />
                    </button>
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      )}

      {/* The shelf's right-click menu: photos, file, link, and — at the bottom,
          behind a confirm — the delete. */}
      <ModelledProductMenu menu={menu} onPick={handleMenuPick} onClose={() => setMenu(null)} />

      {/* The AR upload: picked here, live for every customer straight away. */}
      <UploadArEffectModal
        entry={arTarget?.entry ?? null}
        current={arTarget?.current ?? null}
        onClose={() => setArTarget(null)}
        onDone={(message) => {
          setArTarget(null)
          showToast(message, 'success')
        }}
      />

      {/* Delete is the one menu action that asks first: the file and its row go
          together, and a closed ask that names this version blocks it rather
          than dangling. */}
      {!!deleteTarget && (
        <Modal
          open
          onClose={() => !del.isPending && setDeleteTarget(null)}
          title="Delete this 3D model"
          footer={
            <>
              <button
                type="button"
                onClick={() => setDeleteTarget(null)}
                disabled={del.isPending}
                className="rounded-xl border border-[#D9D0C7] px-4 py-2 text-sm text-[#6B5C4E] hover:bg-[#F5F0EB] disabled:opacity-50"
              >
                Keep it
              </button>
              <button
                type="button"
                onClick={handleDeleteConfirm}
                disabled={del.isPending}
                className="rounded-xl bg-[#D64545] px-5 py-2 text-sm font-semibold text-white shadow-md transition-colors hover:bg-[#B83535] disabled:cursor-not-allowed disabled:opacity-50"
              >
                {del.isPending ? 'Deleting…' : 'Delete file and row'}
              </button>
            </>
          }
        >
          <p className="mb-3 text-sm text-[#6B5C4E]">
            Version <strong className="text-[#3B2314]">{deleteTarget.model.version}</strong> of{' '}
            <strong className="text-[#3B2314]">{deleteTarget.name}</strong> will be removed — the
            uploaded file and its database row, together.
          </p>
          <p className="rounded-xl border border-[#D9CD9A] bg-[#FFF8E5] px-3 py-2 text-xs leading-relaxed text-[#6B5C4E]">
            If this product has older live versions, the previous one becomes the current model on
            the shelf; otherwise the product leaves the 3D shelf. A closed request that names
            this version blocks the delete instead of dangling.
          </p>
        </Modal>
      )}

      {/* The shelf's viewer: the same dialog the fulfil picker opens, so a model
          looks identical wherever an admin opens it. */}
      <ModelViewerDialog target={viewingModel} onClose={() => setViewingModel(null)} />

      {/* ─── All product photos, for modelling reference ────────────── */}
      <ProductPhotosDialog request={photoTarget} onClose={() => setPhotoTarget(null)} />

      {/* ─── Close as done ────────────────────────────────────────── */}
      <FulfilModal
        request={fulfilTarget}
        onClose={() => setFulfilTarget(null)}
        onConfirm={handleFulfil}
        busy={!!fulfilTarget && busyId === fulfilTarget.id}
      />

      {/* ─── Upload the model and close it (P2) ───────────────────── */}
      <UploadModelModal
        // ⚠️ Keyed on the request so opening it for a second row builds fresh
        // state: the declaration is prefilled from THAT ask's measurement, and a
        // reused component would carry the previous row's numbers into it.
        key={uploadTarget?.id ?? 'closed'}
        request={uploadTarget}
        onClose={() => setUploadTarget(null)}
        onDone={(result) => {
          setUploadTarget(null)
          // `live_but_open` is the one ending that is neither good news nor a
          // failure: the model is live and the seller still reads "waiting".
          // It is toasted as an error because somebody has to act on it — and
          // the sentence says where delivery stands, because "published" and
          // "told" are two different facts in exactly that case.
          showToast(
            `${result.message} ${deliveryHeadline(result.ending)}`,
            result.ending === MODELLING_ENDING.CLOSED ? 'success' : 'error',
          )
        }}
      />

      {/* ─── Replace the live version, with no ask ───────────────
          The wrong-file way out: publishes the fixed file as the next live
          version of the same product. History keeps pointing at the old
          version, which is why the delete stays blocked — and why it no
          longer matters, since customers only ever see the newest live one. */}
      <UploadModelModal
        key={replaceTarget ? `replace-${replaceTarget.entry.productId}` : 'replace-closed'}
        replaceTarget=
          {replaceTarget
            ? {
                productId: replaceTarget.entry.productId,
                storeId: replaceTarget.storeId,
                name: replaceTarget.entry.name,
                version: replaceTarget.entry.model.version,
                authoredLengthMm: replaceTarget.entry.model.authored_length_mm,
                authoredSizeEu: replaceTarget.entry.model.authored_size_eu,
              }
            : null}
        onClose={() => setReplaceTarget(null)}
        onDone={({ version, reused }) => {
          const name = replaceTarget?.entry?.name ?? 'this product'
          setReplaceTarget(null)
          showToast(
            reused
              ? `That exact file is already live as version ${version} — nothing changed.`
              : `Version ${version} of ${name} is live — customers see it now. The old version stays in history.`,
            'success',
          )
        }}
      />

      {/* ─── Decline ─────────────────────────────────────────────── */}
      <Modal
        open={!!declineTarget}
        onClose={() => {
          setDeclineTarget(null)
          setDeclineReason('')
        }}
        title="Decline this request"
        footer={
          <>
            <button
              type="button"
              onClick={() => {
                setDeclineTarget(null)
                setDeclineReason('')
              }}
              className="rounded-xl border border-[#D9D0C7] px-4 py-2 text-sm text-[#6B5C4E] hover:bg-[#F5F0EB]"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleDecline}
              // Disabled until there is something to send: the seller reads this
              // sentence on their notification bell, so an empty one would tell
              // them nothing while closing the ask for good.
              disabled={!declineReason.trim() || busyId === declineTarget?.id}
              className="rounded-xl border border-[#D64545] px-4 py-2 text-sm font-semibold text-[#D64545] transition-colors hover:bg-red-50 disabled:cursor-not-allowed disabled:opacity-50"
            >
              {busyId === declineTarget?.id ? 'Declining…' : 'Send decline'}
            </button>
          </>
        }
      >
        <p className="mb-4 text-sm text-[#6B5C4E]">
          Tell the seller why{' '}
          <strong className="text-[#3B2314]">{declineTarget?.products?.name}</strong> cannot be
          modelled. They can ask again afterwards, so this is not a dead end — but it is the only
          explanation they get.
        </p>
        <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
          Reason (required)
        </label>
        <textarea
          value={declineReason}
          onChange={(e) => setDeclineReason(e.target.value)}
          rows={3}
          className="w-full rounded-xl border border-[#D9D0C7] bg-[#F5F0EB] px-3 py-2 text-sm text-[#3B2314] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
          placeholder="e.g. The photos did not show the shape of the toe clearly enough to model from."
        />
        {/* Live, and deliberately live: this is the sentence the seller's bell
            will hold, so an admin writing it can see what arrives. Blank fields
            get the honest version rather than an empty quote. */}
        <p className="mt-2 rounded-xl border border-[#F5F0EB] bg-[#FBF8F5] px-3 py-2 text-[11px] leading-relaxed text-[#6B5C4E]">
          {declineDeliverySentence({ reason: declineReason })}
        </p>
      </Modal>
    </div>
  )
}

// ─── Close as done, against a model that exists ─────────────────────
//
// The picker, and the reason it shows drafts rather than hiding them: the RPC
// refuses anything that is not `active`, so the admin needs to see that the model
// exists but is unpublished — "nothing here" would send them looking for a
// problem in the wrong place. Publishing a draft is the seller's own upload path
// (or the app's queue), so this screen deliberately offers no upload of its own
// yet: a portal cannot run the authoring contract over a `.glb`.
function FulfilModal({ request, onClose, onConfirm, busy }) {
  const [selected, setSelected] = useState(null)
  const [note, setNote] = useState('')
  const [viewing, setViewing] = useState(null)
  const { data: models, isLoading, isError, error } = useProductModels(request?.product_id)
  const modelsError = isError
    ? describeError(error, 'Could not read that product’s models.')
    : null

  const active = (models ?? []).filter((m) => m.status === 'active')
  const drafts = (models ?? []).filter((m) => m.status !== 'active')

  const close = () => {
    setSelected(null)
    setNote('')
    onClose()
  }

  return (
    <>
    <Modal
      open={!!request}
      onClose={close}
      title="Close as done"
      size="xl"
      footer={
        <>
          <button
            type="button"
            onClick={close}
            className="rounded-xl border border-[#D9D0C7] px-4 py-2 text-sm text-[#6B5C4E] hover:bg-[#F5F0EB]"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={selected == null || busy}
            onClick={async () => {
              await onConfirm(selected, note)
              setSelected(null)
              setNote('')
            }}
            className="rounded-xl bg-[#8B5A2B] px-5 py-2 text-sm font-semibold text-white shadow-md transition-colors hover:bg-[#6B4423] disabled:cursor-not-allowed disabled:opacity-50"
          >
            {busy ? 'Closing…' : 'Close request'}
          </button>
        </>
      }
    >
      <p className="mb-4 text-sm text-[#6B5C4E]">
        Close the request for{' '}
        <strong className="text-[#3B2314]">{request?.products?.name}</strong> against the model that
        answers it. The seller is told in the same transaction, so the ask cannot read &ldquo;done&rdquo;
        while nobody has been notified.
      </p>

      {isLoading && (
        <div className="space-y-2">
          {[1, 2].map((i) => (
            <div key={i} className="h-14 animate-pulse rounded-xl bg-[#F5F0EB]" />
          ))}
        </div>
      )}

      {isError && (
        <div className="rounded-xl border border-[#D9CD9A] bg-[#FFF8E5] px-4 py-3 text-sm text-[#6B5C4E]">
          <p className="flex items-center gap-2 font-semibold text-[#3B2314]">
            <AlertTriangle size={14} />
            Could not read this product&apos;s models
          </p>
          <p className="mt-1 text-xs">{modelsError.message}</p>
          {modelsError.detail && modelsError.detail !== modelsError.message && (
            <p className="mt-1 text-xs opacity-70">The server said: {modelsError.detail}</p>
          )}
        </div>
      )}

      {!isLoading && !isError && active.length === 0 && (
        <div className="rounded-xl border border-[#D9CD9A] bg-[#FFF8E5] px-4 py-3 text-sm text-[#6B5C4E]">
          <p className="flex items-center gap-2 font-semibold text-[#3B2314]">
            <AlertTriangle size={14} />
            This product has no live model yet
          </p>
          <p className="mt-1 text-xs">
            {drafts.length > 0
              ? `It has ${drafts.length} model${drafts.length > 1 ? 's' : ''}, but ${
                  drafts.length > 1 ? 'none are' : 'it is not'
                } published — a draft is not a model customers can render, so it cannot close this request.`
              : 'Nothing has been uploaded for it. A request is closed against a published model, never against a status.'}
          </p>
        </div>
      )}

      {/* Every model is listed, so an admin can look at a draft before deciding.
          Only a live one can be picked: the RPC refuses anything else, and the
          picker says so rather than hiding the row. */}
      {!isLoading && !isError && (models ?? []).length > 0 && (
        <div className="space-y-2">
          {(models ?? []).map((m) => {
            const live = m.status === 'active'
            const chosen = selected === m.id
            return (
              <div
                key={m.id}
                className={`flex items-center gap-3 rounded-xl border px-4 py-3 transition-colors ${
                  chosen
                    ? 'border-[#8B5A2B] bg-[#8B5A2B]/5'
                    : 'border-[#D9D0C7] bg-white'
                }`}
              >
                <button
                  type="button"
                  disabled={!live}
                  aria-pressed={chosen}
                  onClick={() => setSelected(m.id)}
                  className="flex min-w-0 flex-1 items-center justify-between gap-3 text-left disabled:cursor-not-allowed"
                >
                  <div>
                    <p className="text-sm font-semibold text-[#3B2314]">Version {m.version}</p>
                    <p className="mt-0.5 text-xs text-[#6B5C4E]">
                      {m.authored_length_mm
                        ? `${Number(m.authored_length_mm).toFixed(1)} mm`
                        : 'No declared length'}
                      {m.authored_size_eu ? ` · EU ${Number(m.authored_size_eu)}` : ''}
                      {!live && ' · cannot close a request'}
                    </p>
                  </div>
                  <Badge label={m.status} variant={m.status} />
                </button>
                {m.storage_path && (
                  <button
                    type="button"
                    onClick={() =>
                      setViewing({
                        title: request?.products?.name ?? 'Product',
                        storagePath: m.storage_path,
                        status: m.status,
                        version: m.version,
                      })
                    }
                    className="shrink-0 rounded-lg border border-[#8B5A2B] px-3 py-1.5 text-xs font-semibold text-[#8B5A2B] transition-colors hover:bg-[#8B5A2B]/10"
                  >
                    View 3D
                  </button>
                )}
              </div>
            )
          })}
        </div>
      )}

      <div className="mt-5">
        <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
          Note to the seller (optional)
        </label>
        <textarea
          value={note}
          onChange={(e) => setNote(e.target.value)}
          rows={2}
          className="w-full rounded-xl border border-[#D9D0C7] bg-[#F5F0EB] px-3 py-2 text-sm text-[#3B2314] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
          placeholder="Anything they should know about the model…"
        />
        <p className="mt-1.5 text-[11px] leading-relaxed text-[#6B5C4E]">{noteReachesSeller()}</p>
      </div>

      <p className="mt-3 text-[11px] leading-relaxed text-[#6B5C4E]">
        {NOTICE_NOT_READABLE_SENTENCE}
      </p>
    </Modal>
    {/* Outside the Modal on purpose: the dialog's transform would trap a fixed
        overlay inside it. */}
    <ModelViewerDialog target={viewing} onClose={() => setViewing(null)} />
    </>
  )
}
