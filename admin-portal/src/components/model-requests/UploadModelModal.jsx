import { useState } from 'react'
import { AlertTriangle, Check, Cuboid, Loader2, Ruler, Upload } from 'lucide-react'
import Modal from '../ui/Modal.jsx'
import { usePublishModelRequest } from '../../hooks/usePublishModel.js'
import { describeError } from '../../lib/errors.js'
import {
  DECLARATION_FIELD,
  declarationMessageFor,
  declaredLengthAgreement,
  modellingPrefill,
  readDeclaration,
  MODELLING_ENDING,
} from '../../lib/modelPublish.js'
// P3: what the seller is told, which is the database's doing and this page's
// claim — see `askDelivery.js` and the contract test that keeps them equal.
import {
  NOTICE_NOT_READABLE_SENTENCE,
  deliverySentence,
  noteReachesSeller,
} from '../../lib/askDelivery.js'

// ─── Upload the model, and close the ask in the same step ──────────
//
// The portal's *Upload a 3D model* (roadmap V2.11, P2) — the action the queue
// was missing. Until this existed, the only thing the portal could do with an
// ask was point at a model somebody else had already published, which is the
// exact gap the Flutter screen's header describes:
//
//   "Without it the picker above could only ever be filled by someone with a
//    terminal, which would leave this screen unable to answer the requests it
//    exists for."
//
// **One surface difference from the app, and it is a browser fact rather than a
// design choice.** The app has no file picker (no dependency can select a
// `.glb`), so its only source is a link. A browser has a picker for free — and
// a browser is also the one client whose *link* downloads can be refused by the
// host's CORS rules. So both sources are offered: the file is the reliable one,
// the link is kept because it is what the app does and what a studio shares.
// They feed the same pipeline, and the declaration rules below are identical
// either way.
//
// **What is deliberately not shown: a pre-flight report card.** The app runs the
// 11-check contract on the bytes before publishing; the portal does not, because
// that contract already has two implementations (the Dart reference and the
// TypeScript mirror inside `validate-shoe-model`, parity-checked over 22
// fixtures) and a third would be a third place for eleven rules to drift. The
// server judges the stored bytes, which is the authoritative check — the app's
// client-side run is a courtesy that saves a round trip, not a gate. So a
// refusal here costs one upload, arrives with the failing rows named, and leaves
// the row hidden and the ask open.

const fieldClass =
  'w-full rounded-xl border bg-[#F5F0EB] px-3 py-2 text-sm text-[#3B2314] outline-none transition-colors focus:ring-2 disabled:opacity-60'
const labelClass = 'mb-1.5 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]'

function borderFor(error) {
  return error
    ? 'border-[#D64545] focus:border-[#D64545] focus:ring-[#D64545]/20'
    : 'border-[#D9D0C7] focus:border-[#8B5A2B] focus:ring-[#8B5A2B]/20'
}

function Notice({ tone = 'error', title, children }) {
  const tones = {
    error: { border: '#D64545', bg: '#FDF2F2' },
    warn: { border: '#D9CD9A', bg: '#FFF8E5' },
  }
  const { border, bg } = tones[tone] ?? tones.error
  return (
    <div
      className="rounded-xl border px-4 py-3 text-sm text-[#6B5C4E]"
      style={{ borderColor: border, backgroundColor: bg }}
    >
      {title && (
        <p className="flex items-center gap-2 font-semibold text-[#3B2314]">
          <AlertTriangle size={14} />
          {title}
        </p>
      )}
      <div className={title ? 'mt-1 text-xs leading-relaxed' : 'text-xs leading-relaxed'}>
        {children}
      </div>
    </div>
  )
}

export default function UploadModelModal({ request, onClose, onDone }) {
  const publish = usePublishModelRequest()

  // The seller's own measurement, so it is the right starting point here — the
  // prefill has a different rule on the seller's side, and the reason is spelled
  // out in `modellingPrefill` (this one IS the external figure the mesh scales
  // to; the seller's form had only the internal last).
  const prefill = modellingPrefill({
    externalLengthMm: request?.external_length_mm,
    measuredSizeEu: request?.measured_size_eu,
  })

  const [link, setLink] = useState('')
  const [file, setFile] = useState(null)
  const [lengthMm, setLengthMm] = useState(prefill.externalLengthMm)
  const [sizeEu, setSizeEu] = useState(prefill.authoredSizeEu)
  const [note, setNote] = useState('')
  const [error, setError] = useState(null)

  const declaration = readDeclaration({ externalLengthMm: lengthMm, authoredSizeEu: sizeEu })
  const agreement = declaredLengthAgreement({
    measuredMm: request?.external_length_mm ?? null,
    declaredMm: declaration.externalLengthMm,
  })

  const hasSource = Boolean(file) || link.trim() !== ''
  // The length is required: the server's scale check cannot run without it, so a
  // publish without one would be a round trip to a refusal.
  const ready =
    hasSource && !declaration.error && declaration.externalLengthMm !== null && !publish.isPending

  const reset = () => {
    setLink('')
    setFile(null)
    setNote('')
    setError(null)
  }

  const close = () => {
    if (publish.isPending) return
    reset()
    onClose()
  }

  const handlePublish = async () => {
    setError(null)
    try {
      const result = await publish.mutateAsync({
        request,
        link,
        file,
        declaration,
        note: note.trim() === '' ? null : note.trim(),
      })

      // Nothing went live: stay open, because the link and the fields are still
      // in front of the admin and the fix is usually one of the two — the app's
      // sheet keeps itself open for the same reason.
      if (result.ending === 'not_live') {
        setError(result.message)
        return
      }

      reset()
      onDone(result)
    } catch (e) {
      setError(describeError(e, 'The model could not be published.').message)
    }
  }

  return (
    <Modal
      open={Boolean(request)}
      onClose={close}
      title="Upload the model"
      size="xl"
      footer={
        <>
          <button
            type="button"
            onClick={close}
            disabled={publish.isPending}
            className="rounded-xl border border-[#D9D0C7] px-4 py-2 text-sm text-[#6B5C4E] hover:bg-[#F5F0EB] disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={!ready}
            onClick={handlePublish}
            className="inline-flex items-center gap-2 rounded-xl bg-[#4ECDC4] px-5 py-2 text-sm font-semibold text-white shadow-md transition-colors hover:bg-teal-600 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {publish.isPending ? (
              <>
                <Loader2 size={14} className="animate-spin" />
                Publishing…
              </>
            ) : (
              <>
                <Check size={14} />
                Publish and close the request
              </>
            )}
          </button>
        </>
      }
    >
      <p className="mb-4 text-sm text-[#6B5C4E]">
        Publish the finished <span className="font-semibold text-[#3B2314]">.glb</span> for{' '}
        <strong className="text-[#3B2314]">{request?.products?.name ?? 'this product'}</strong> and
        close the seller&apos;s request in the same step. The server checks the stored bytes before
        the model goes live, so a refusal leaves it hidden and the request open.
      </p>

      {/* The ask, so the admin can see what was measured before answering it. */}
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <span className="inline-flex items-center gap-2 rounded-xl border border-[#F5F0EB] bg-[#FBF8F5] px-3 py-2">
          <Ruler size={13} className="text-[#8B5A2B]" />
          <span className="text-[11px] uppercase tracking-wider text-[#6B5C4E]">Seller measured</span>
          <span className="text-sm font-semibold text-[#3B2314]">
            {request?.external_length_mm == null
              ? '—'
              : `${Number(request.external_length_mm).toFixed(1)} mm outside`}
          </span>
        </span>
        {request?.note && (
          <span className="rounded-xl bg-[#F5F0EB] px-3 py-2 text-xs text-[#6B5C4E]">
            <strong className="text-[#3B2314]">Their note:</strong> {request.note}
          </span>
        )}
      </div>

      <div className="grid gap-3 sm:grid-cols-2">
        <div>
          <label className={labelClass} htmlFor="model-length">
            Declared length (mm, outside)
          </label>
          <input
            id="model-length"
            value={lengthMm}
            onChange={(e) => setLengthMm(e.target.value)}
            inputMode="decimal"
            placeholder="270"
            className={`${fieldClass} ${borderFor(declarationMessageFor(declaration, DECLARATION_FIELD.EXTERNAL_LENGTH_MM))}`}
          />
          {declarationMessageFor(declaration, DECLARATION_FIELD.EXTERNAL_LENGTH_MM) ? (
            <p className="mt-1 text-xs text-[#D64545]">
              {declarationMessageFor(declaration, DECLARATION_FIELD.EXTERNAL_LENGTH_MM)}
            </p>
          ) : (
            <p className="mt-1 text-xs text-[#6B5C4E]">
              Prefilled from the seller&apos;s own measurement — the figure the mesh is scaled to.
            </p>
          )}
        </div>

        <div>
          <label className={labelClass} htmlFor="model-size">
            Authored at (EU size, optional)
          </label>
          <input
            id="model-size"
            value={sizeEu}
            onChange={(e) => setSizeEu(e.target.value)}
            inputMode="decimal"
            placeholder="42"
            className={`${fieldClass} ${borderFor(declarationMessageFor(declaration, DECLARATION_FIELD.AUTHORED_SIZE_EU))}`}
          />
          {declarationMessageFor(declaration, DECLARATION_FIELD.AUTHORED_SIZE_EU) && (
            <p className="mt-1 text-xs text-[#D64545]">
              {declarationMessageFor(declaration, DECLARATION_FIELD.AUTHORED_SIZE_EU)}
            </p>
          )}
        </div>
      </div>

      {/* ⚠️ The one rule this surface adds over a plain upload: a note, never a
          gate. The admin may know the seller measured the wrong pair, and
          refusing to publish would be refusing a correct model. */}
      {agreement.message && (
        <div className="mt-3">
          <Notice tone="warn" title="The declared length disagrees with the ruler">
            {agreement.message}
          </Notice>
        </div>
      )}

      <div className="mt-4">
        <label className={labelClass} htmlFor="model-file">
          Choose a .glb file
        </label>
        <input
          id="model-file"
          type="file"
          accept=".glb,model/gltf-binary"
          onChange={(e) => {
            setFile(e.target.files?.[0] ?? null)
            setError(null)
          }}
          className="w-full rounded-xl border border-[#D9D0C7] bg-white px-3 py-2 text-sm text-[#3B2314] file:mr-3 file:rounded-lg file:border-0 file:bg-[#8B5A2B] file:px-3 file:py-1.5 file:text-xs file:font-semibold file:text-white"
        />
        <p className="mt-1 text-xs text-[#6B5C4E]">
          Under 8 MB, exported as glTF binary (.glb). This is the source that always works.
        </p>
      </div>

      <div className="mt-3">
        <label className={labelClass} htmlFor="model-link">
          …or paste a link to it
        </label>
        <input
          id="model-link"
          value={link}
          onChange={(e) => {
            setLink(e.target.value)
            setError(null)
          }}
          placeholder="https://…"
          className={`${fieldClass} ${borderFor(null)}`}
        />
        <p className="mt-1 text-xs text-[#6B5C4E]">
          A direct https link, the way the app takes one. A file is used instead when both are given.
        </p>
      </div>

      <div className="mt-3">
        <label className={labelClass} htmlFor="model-note">
          Note for the seller (optional)
        </label>
        <textarea
          id="model-note"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          rows={2}
          placeholder="Anything they should know about the model…"
          className={`w-full rounded-xl border border-[#D9D0C7] bg-[#F5F0EB] px-3 py-2 text-sm text-[#3B2314] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20`}
        />
        <p className="mt-1 text-xs text-[#6B5C4E]">{noteReachesSeller()}</p>
      </div>

      {error && (
        <div className="mt-3">
          <Notice title="That did not publish">{error}</Notice>
        </div>
      )}

      {/* ⚠️ The ending this dialog stays open for is the one where an admin is
          most likely to assume the seller was told *something* — a refusal
          notice, a "try again". Nothing was written, and that is the news. */}
      {error && (
        <div className="mt-2 rounded-xl border border-[#F5F0EB] bg-[#FBF8F5] px-3 py-2 text-[11px] leading-relaxed text-[#6B5C4E]">
          {deliverySentence(MODELLING_ENDING.NOT_LIVE)}
        </div>
      )}

      <p className="mt-4 flex items-start gap-2 text-[11px] leading-relaxed text-[#6B5C4E]">
        <Cuboid size={13} className="mt-0.5 shrink-0 text-[#8B5A2B]" />
        A green run means the file is buildable, not that it looks right: the toe direction, the
        de-lit colour and the likeness still need a human eye (guide §5.2). Publishing also tells
        the seller, in the same transaction. {NOTICE_NOT_READABLE_SENTENCE}
      </p>
    </Modal>
  )
}
