import { useRef, useState } from 'react'
import { AlertTriangle, Check, Cuboid, Loader2, Ruler, Sparkles, Upload } from 'lucide-react'
import Modal from '../ui/Modal.jsx'
import { usePublishModelRequest } from '../../hooks/usePublishModel.js'
import { useCompressModel } from '../../hooks/useCompressModel.js'
import { describeError } from '../../lib/errors.js'
import {
  BUCKET_CAP_BYTES,
  DECLARATION_FIELD,
  declarationMessageFor,
  declaredLengthAgreement,
  modellingPrefill,
  readDeclaration,
  MODELLING_ENDING,
} from '../../lib/modelPublish.js'
import {
  FILE_SIZE_BUDGET_BYTES,
  MIN_TARGET_TRIANGLES,
  TARGET_TRIANGLES,
  compressFailureMessage,
  compressionSummary,
  formatBytes,
} from '../../lib/modelCompress.js'
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

// Follow-up passes beyond the first: 20k, 10k, 5k triangle targets. Past the
// last one the mesh would lose its silhouette, so the loop stops and says the
// weight is in the textures.
const MAX_EXTRA_PASSES = 3

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
  // Which rung of the ladder the auto-loop is on (0 = the full-target first
  // pass). Reset whenever the picked file changes.
  const [passes, setPasses] = useState(0)
  // One click runs the whole ladder without stopping, so closing the modal or
  // picking another file mid-run must retire the loop, not leave it feeding
  // workers into a closed dialog. The hook's own run guard only covers one
  // pass; this one covers the chain.
  const loopRef = useRef(0)
  // What the compress step produced, and the sentence it ended with — kept
  // beside `file` because both are "the source", and the admin needs to see
  // which one is in hand before pressing Publish.
  const [compressed, setCompressed] = useState(null)
  const compress = useCompressModel()

  const declaration = readDeclaration({ externalLengthMm: lengthMm, authoredSizeEu: sizeEu })
  const agreement = declaredLengthAgreement({
    measuredMm: request?.external_length_mm ?? null,
    declaredMm: declaration.externalLengthMm,
  })

  const hasSource = Boolean(file) || link.trim() !== ''
  // The length is required: the server's scale check cannot run without it, so a
  // publish without one would be a round trip to a refusal.
  const baseReady =
    hasSource &&
    !declaration.error &&
    declaration.externalLengthMm !== null &&
    !publish.isPending &&
    // Publishing mid-loop would upload an intermediate pass's bytes — a file
    // already known to be over budget — instead of the loop's answer.
    !compress.isRunning
  // Compressing needs a file and a length, but never a publishable size —
  // shrinking an over-cap file is the whole point of the button.

  const compressReady =
    Boolean(file) &&
    !declaration.error &&
    declaration.externalLengthMm !== null &&
    !publish.isPending

  // ⚠️ The file that was compressed, tracked by identity rather than by name:
  // a second file with the same name from another folder is a different file,
  // and offering the previous run's bytes for it would be the worst kind of
  // quiet mistake. So the result is dropped whenever the picked file changes.
  const compressedMatchesFile = compressed !== null && compressed.forFile === file

  // Offered when a picked file is over the authoring budget, or when the last
  // run left its result in hand (so the admin can see it, and re-run it).
  const overBudget = Boolean(file) && file.size > FILE_SIZE_BUDGET_BYTES
  const showCompress = Boolean(file) && (overBudget || compressedMatchesFile)

  // The bytes Publish would upload, whatever the source: the compressed
  // result when it is about the picked file, else the picked file itself. A
  // link's size is unknown until it downloads, so it is never pre-judged.
  const outgoingBytes = compressedMatchesFile
    ? compressed.bytes.length
    : file
      ? file.size
      : null
  // The bucket's hard cap, not the authoring budget: a publish over this is
  // refused before the validator ever sees it, so the button stays off and
  // says why instead of spending the upload.
  const overCap = outgoingBytes !== null && outgoingBytes > BUCKET_CAP_BYTES
  // The server's number, not the bucket's: anything over the authoring budget
  // uploads and is then refused on `file size`, so Publish stays off here too.
  // The screenshot this was written against is the proof — 6.9 MB sailed past
  // the button and came back refused. The way through is another pass, which
  // is why the notice below points at the button above instead.
  const outgoingOverBudget =
    outgoingBytes !== null && outgoingBytes > FILE_SIZE_BUDGET_BYTES
  // Publish needs everything above, plus bytes the bucket will take and the
  // server will pass. A link's size is unknown, so a link-only publish stays
  // enabled and the server judges it.
  const ready = baseReady && !overCap && !outgoingOverBudget

  const reset = () => {
    setLink('')
    setFile(null)
    setNote('')
    setError(null)
    setCompressed(null)
    setPasses(0)
    compress.clear()
  }

  const close = () => {
    if (publish.isPending) return
    // A run in flight is stopped rather than left to finish into a closed
    // modal: it holds a few hundred megabytes until it does. Retiring the
    // loop as well, so a pass finishing after this cannot start another.
    loopRef.current += 1
    compress.stop()
    reset()
    onClose()
  }

  const handleCompress = async () => {
    if (!file || compress.isRunning) return
    // ⚠️ Deliberately not `setError`: that one is the *publish* error and is
    // rendered under "That did not publish", which would be a lie about a
    // compression that never reached the server. The hook keeps its own.
    //
    // One click runs the whole ladder without stopping: each over-budget
    // result feeds the next pass with half the triangle target (20k, 10k, 5k),
    // so the first press already lands under the budget whenever the file can
    // get there at all. The picked file itself is never touched: pass 1 reads
    // it, later passes read the previous pass's bytes.
    const myLoop = ++loopRef.current
    compress.clear()

    // A copy this component owns, because the hook transfers the buffer to the
    // worker rather than cloning 90 MB of it. `arrayBuffer()` already returns a
    // fresh buffer per call, so this is a view onto a copy, not the file itself.
    let sourceBytes = new Uint8Array(await file.arrayBuffer())
    let extras = 0
    let baseTriangles = null

    while (loopRef.current === myLoop) {
      setPasses(extras)
      const targetTriangles =
        extras === 0
          ? undefined
          : Math.max(Math.round(TARGET_TRIANGLES / 2 ** extras), MIN_TARGET_TRIANGLES)
      const outcome = await compress.compress({
        bytes: sourceBytes,
        declaredLengthMm: declaration.externalLengthMm,
        authoredSizeEu: declaration.authoredSizeEu,
        ...(targetTriangles === undefined ? {} : { targetTriangles }),
      })

      // Retired mid-pass (modal closed, file re-picked): leave nothing behind.
      if (loopRef.current !== myLoop) return
      if (!outcome.ok) return

      if (baseTriangles === null) baseTriangles = outcome.plan.triangleCount
      const stillOver = outcome.result.bytes.length > FILE_SIZE_BUDGET_BYTES

      setCompressed({
        forFile: file,
        blob: new Blob([outcome.result.bytes], { type: 'model/gltf-binary' }),
        bytes: outcome.result.bytes,
        changes: outcome.result.changes,
        before: outcome.result.before,
        after: outcome.result.after,
        // The story is always original → latest, whatever the pass: the triangle
        // count the first pass started from, and the count the latest produced.
        trianglesBefore: baseTriangles,
        overBudgetAfter: stillOver,
        summary: compressionSummary({
          beforeBytes: file.size,
          afterBytes: outcome.result.bytes.length,
          triangleCount: baseTriangles,
          triangleCountAfter: outcome.result.after?.triangles ?? null,
        }),
      })

      if (!stillOver || extras >= MAX_EXTRA_PASSES) return

      // Next pass reads this pass's bytes. `.slice()` copies because the hook
      // transfers (detaches) the buffer to the worker.
      extras += 1
      sourceBytes = outcome.result.bytes.slice()
    }
  }

  const handlePublish = async () => {
    setError(null)
    try {
      // The compressed bytes go in as the file, under the picked file's name.
      // The upload pipeline reads them exactly as it reads a picked file, so
      // nothing downstream changes: the server still judges the stored bytes.
      const source = compressedMatchesFile
        ? new File([compressed.blob], file.name, { type: 'model/gltf-binary' })
        : file

      const result = await publish.mutateAsync({
        request,
        link,
        file: source,
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
        </label>          <input
            id="model-file"
            type="file"
            accept=".glb,model/gltf-binary"
            onChange={(e) => {
              // A different file retires a running loop the same way closing
              // does: its passes are about bytes no longer in hand.
              loopRef.current += 1
              setFile(e.target.files?.[0] ?? null)
              setError(null)
              // A different file is a different problem: the previous run's
              // bytes and change log are no longer about what is in hand.
              setCompressed(null)
              setPasses(0)
              compress.clear()
            }}
            className="w-full rounded-xl border border-[#D9D0C7] bg-white px-3 py-2 text-sm text-[#3B2314] file:mr-3 file:rounded-lg file:border-0 file:bg-[#8B5A2B] file:px-3 file:py-1.5 file:text-xs file:font-semibold file:text-white"
          />
        <p className="mt-1 text-xs text-[#6B5C4E]">
          Under {formatBytes(BUCKET_CAP_BYTES)}, exported as glTF binary (.glb). This is the source
          that always works.
        </p>
      </div>

      {/* ── The compress step ────────────────────────────────────────
          Offered only when there is something to fix, and it is the *budget*
          (5 MB) rather than the bucket cap (8 MB) that raises it: a file
          between the two uploads and is then refused by the server, which
          costs a round trip and a download to be told what this button
          already knows.

          What it does NOT do: judge the model. It runs the same reference
          normalizer the CLI runs — re-axis, re-ground, rescale to the declared
          length, re-bake textures, rename parts — plus a decimation pass the
          CLI cannot do at all. The server still reads the stored bytes, and a
          green run here is not acceptance (guide §5.2). */}
      {showCompress && (
        <div className="mt-3 rounded-xl border border-[#F5F0EB] bg-[#FBF8F5] px-4 py-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div className="min-w-0">
              <p className="flex items-center gap-2 text-sm font-semibold text-[#3B2314]">
                <Sparkles size={14} className="text-[#8B5A2B]" />
                {!compressedMatchesFile
                  ? 'This file is over the authoring budget'
                  : compressed.overBudgetAfter
                    ? 'Compressed, but still over the budget'
                    : 'Compressed and ready to upload'}
              </p>
              <p className="mt-1 text-xs leading-relaxed text-[#6B5C4E]">
                {compressedMatchesFile
                  ? 'The compressed bytes are in hand and are what Publish will upload — the ' +
                    'picked file itself is left alone.'
                  : `${formatBytes(file.size)} against a ${formatBytes(FILE_SIZE_BUDGET_BYTES)} ` +
                    'budget — the bucket takes it, but the server will refuse it. Compressing ' +
                    'decimates the mesh and re-bakes the textures to 1024², then runs the same ' +
                    'normalizer the CLI runs: re-aimed axes, grounded, scaled to the declared ' +
                    'length, parts renamed. One press runs up to four passes on its own — each ' +
                    'over-budget result halves the triangle target for the next — a minute or so ' +
                    'per pass for a file this size, and the tab stays usable while it does.'}
              </p>
            </div>
            {/* The loop runs itself to the budget or the floor — there is no
                manual "again" left to press. Past 5,000 triangles the shoe keeps
                its footprint but loses its silhouette, so more passes would trade
                the fitting for bytes. The weight then is in the textures, which
                need a human and the guide, not a button. */}
            {!compressedMatchesFile && !compress.isRunning && (
              <button
                type="button"
                onClick={handleCompress}
                disabled={!compressReady}
              className="inline-flex shrink-0 items-center gap-2 rounded-xl border border-[#8B5A2B] px-4 py-2 text-sm font-semibold text-[#8B5A2B] transition-colors hover:bg-[#8B5A2B] hover:text-white disabled:cursor-not-allowed disabled:opacity-50"
            >
                <Sparkles size={14} />
                Compress it
              </button>
            )}
            {compress.isRunning && (
              <button
                type="button"
                disabled
                className="inline-flex shrink-0 items-center gap-2 rounded-xl border border-[#8B5A2B] px-4 py-2 text-sm font-semibold text-[#8B5A2B] disabled:cursor-not-allowed disabled:opacity-50"
              >
                <Loader2 size={14} className="animate-spin" />
                Compressing… (pass {passes + 1} of {MAX_EXTRA_PASSES + 1})
              </button>
            )}
          </div>

          {compress.isRunning && compress.stageSentence && (
            <p className="mt-2 text-xs text-[#8B5A2B]">{compress.stageSentence}</p>
          )}

          {!compressReady && !compress.isRunning && (
            <p className="mt-2 text-xs text-[#6B5C4E]">
              Fill in the declared length first — the mesh is scaled to it, so compressing
              without one would leave the scale wrong.
            </p>
          )}

          {compress.error && !compress.isRunning && (
            <div className="mt-2">
              <Notice title="That file could not be compressed">{compress.error}</Notice>
            </div>
          )}

          {compressedMatchesFile && !compress.isRunning && (
            <div className="mt-2">
              <p className="text-xs font-semibold text-[#3B2314]">
                {compressed.summary}
                {/* Reachable only when the loop ran all four passes: anything
                    else fits the budget and lands on Publish instead. */}
                {compressed.overBudgetAfter && (
                  <>
                    {' '}Four passes and still over: the weight is in the textures, not the mesh.
                    Re-bake them and re-export (guide §C5/C7), or run the CLI.
                  </>
                )}
              </p>
              {/* ⚠️ The assumptions, shown rather than applied quietly. The toe
                  end and the sole cut line are decisions the file cannot make
                  for itself, and the reviewer still has to confirm both. */}
              <details className="mt-2">
                <summary className="cursor-pointer text-xs font-semibold text-[#8B5A2B]">
                  What it changed ({compressed.changes.length})
                </summary>
                <ul className="mt-1 list-disc space-y-0.5 pl-4 text-[11px] leading-relaxed text-[#6B5C4E]">
                  {compressed.changes.map((change, index) => (
                    <li key={index}>{change}</li>
                  ))}
                </ul>
              </details>
            </div>
          )}
        </div>
      )}

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

      {overCap && file && !compress.isRunning && (
        <div className="mt-3">
          <Notice tone="warn" title="Still too big to publish">
            {formatBytes(outgoingBytes)} against the {formatBytes(BUCKET_CAP_BYTES)} the model
            bucket accepts — Publish stays off until the bytes in hand fit. Run another compress
            pass above, or pick a smaller export.
          </Notice>
        </div>
      )}

      {!overCap && outgoingOverBudget && file && !compress.isRunning && (
        <div className="mt-3">
          <Notice
            tone="warn"
            title={`Over the ${formatBytes(FILE_SIZE_BUDGET_BYTES)} the server enforces`}
          >
            {formatBytes(outgoingBytes)} uploads, then the server refuses it on file size — so
            Publish stays off until the bytes fit. Run the next compress pass above (each one
            halves the triangle target){!compressedMatchesFile || passes < MAX_EXTRA_PASSES
              ? '. The picked file itself is left alone.'
              : ', or re-bake the textures and re-export (guide §C5/C7): four passes is the floor.'}
          </Notice>
        </div>
      )}

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
