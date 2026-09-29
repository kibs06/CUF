import { useMemo, useState } from 'react'
import { AlertTriangle, Check, Cuboid, Hand, Loader2, Ruler, Upload } from 'lucide-react'
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
  useFulfilModelRequest,
  useModelRequests,
  useProductModels,
} from '../hooks/useModelRequests.js'
import UploadModelModal from '../components/model-requests/UploadModelModal.jsx'
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

// A seller measures the OUTSIDE of the pair (the number the renderer scales to),
// which is why these are labelled "external" here and never called a last length:
// `products.last_length_mm` is the INTERNAL last the fit verdict compares, and
// the two differ by 8–15 mm (SHOE_MODEL_AUTHORING_GUIDE.md §5).
function Measurement({ label, value, icon: Icon }) {
  if (value == null) return null
  return (
    <div className="flex items-center gap-2 rounded-xl border border-[#F5F0EB] bg-[#FBF8F5] px-3 py-2">
      {Icon && <Icon size={13} className="text-[#8B5A2B]" />}
      <span className="text-[11px] uppercase tracking-wider text-[#6B5C4E]">{label}</span>
      <span className="text-sm font-semibold text-[#3B2314]">{value}</span>
    </div>
  )
}

export default function ModelRequests() {
  const [tab, setTab] = useState('waiting')
  const [fulfilTarget, setFulfilTarget] = useState(null)
  const [uploadTarget, setUploadTarget] = useState(null)
  const [declineTarget, setDeclineTarget] = useState(null)
  const [declineReason, setDeclineReason] = useState('')
  const [busyId, setBusyId] = useState(null)
  const { showToast } = useToast()

  const { data, isLoading, isError, error } = useModelRequests()
  const claim = useClaimModelRequest()
  const fulfil = useFulfilModelRequest()
  const decline = useDeclineModelRequest()

  const rows = useMemo(() => data ?? [], [data])

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
    }),
    [rows],
  )

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
      <div className="flex gap-2">
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            onClick={() => setTab(t.key)}
            className={`rounded-xl px-4 py-2 text-sm font-medium transition-all ${
              tab === t.key
                ? 'bg-[#8B5A2B] text-white shadow-sm'
                : 'border border-[#D9D0C7] bg-white text-[#6B5C4E] hover:bg-[#F5F0EB]'
            }`}
          >
            {t.label}
            <span
              className={`ml-2 rounded-full px-1.5 py-0.5 text-xs ${
                tab === t.key ? 'bg-white/20 text-white' : 'bg-[#F5F0EB] text-[#6B5C4E]'
              }`}
            >
              {counts[t.key]}
            </span>
          </button>
        ))}
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
      {!isLoading && !isError && visible.length === 0 && !gatedEmpty && (
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
      {!isLoading && !isError && visible.length > 0 && (
        <div className="space-y-3">
          {visible.map((row) => {
            const isOpen = OPEN_STATUSES.includes(row.status)
            const claimed = !!row.assigned_to
            return (
              <div
                key={row.id}
                className="rounded-2xl border border-[#D9D0C7] bg-white p-5 transition-shadow hover:shadow-sm"
              >
                <div className="flex flex-wrap items-start justify-between gap-3">
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

                  {isOpen && (
                    <div className="flex items-center gap-2">
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
                <div className="mt-4 flex flex-wrap gap-2">
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

      {!isLoading && !isError && active.length > 0 && (
        <div className="space-y-2">
          {active.map((m) => (
            <button
              key={m.id}
              type="button"
              onClick={() => setSelected(m.id)}
              className={`flex w-full items-center justify-between gap-3 rounded-xl border px-4 py-3 text-left transition-colors ${
                selected === m.id
                  ? 'border-[#8B5A2B] bg-[#8B5A2B]/5'
                  : 'border-[#D9D0C7] bg-white hover:bg-[#F5F0EB]'
              }`}
            >
              <div>
                <p className="text-sm font-semibold text-[#3B2314]">Version {m.version}</p>
                <p className="mt-0.5 text-xs text-[#6B5C4E]">
                  {m.authored_length_mm ? `${Number(m.authored_length_mm).toFixed(1)} mm` : 'No declared length'}
                  {m.authored_size_eu ? ` · EU ${Number(m.authored_size_eu)}` : ''}
                </p>
              </div>
              <Badge label={m.status} variant={m.status} />
            </button>
          ))}
        </div>
      )}

      {!isLoading && !isError && drafts.length > 0 && active.length > 0 && (
        <p className="mt-2 text-xs text-[#6B5C4E]">
          {drafts.length} unpublished model{drafts.length > 1 ? 's are' : ' is'} hidden here — only
          a live one can close this request.
        </p>
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
  )
}
