import { BadgeCheck, FileText, Landmark, Store, UserCheck } from 'lucide-react'
import Modal from '../ui/Modal.jsx'
import VerificationDoc from './VerificationDoc.jsx'
import { formatDate } from '../../lib/constants'

const PRIVATE_BUCKET = 'seller-verification-docs'
const PUBLIC_BUCKET = 'store-assets'

const STORE_TAG_LABELS = {
  handmade: 'Handmade',
  family_owned: 'Family-owned',
  multi_generation: 'Multi-generation',
  custom_orders: 'Custom orders',
  local: 'Local',
  carcar_made: 'Carcar-made',
  cebu_made: 'Cebu-made',
  filipino_made: 'Filipino-made',
  custom_sizing: 'Custom sizing',
  repairs: 'Repairs & resoling',
  wholesale: 'Wholesale',
  retail: 'Retail / walk-ins',
}

function tagLabel(stored) {
  if (typeof stored !== 'string') return ''
  if (stored.startsWith('custom:')) {
    const parts = stored.split(':')
    return parts.length >= 3 ? parts.slice(2).join(':') : stored
  }
  return STORE_TAG_LABELS[stored] ?? stored
}

const ID_TYPE_LABELS = {
  philid: 'PhilID (National ID)',
  passport: 'Passport',
  drivers_license: "Driver's License",
  umid_sss: 'UMID / SSS ID',
  gsis_ecard: 'GSIS eCard',
  prc: 'PRC ID',
  postal: 'Postal ID',
  voters: "Voter's ID",
  senior_citizen: 'Senior Citizen ID',
  pwd: 'PWD ID',
  tin: 'TIN ID',
  nbi_clearance: 'NBI Clearance',
}

function SectionTitle({ icon, children }) {
  return (
    <p className="mb-2.5 flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
      <span className="text-[#8B5A2B]">{icon}</span>
      {children}
    </p>
  )
}

function InfoRow({ label, value }) {
  return (
    <div className="flex items-start justify-between gap-4 py-1.5">
      <span className="flex-shrink-0 text-xs text-[#6B5C4E]">{label}</span>
      <span className="text-right text-sm font-semibold text-[#3B2314]">
        {value || '—'}
      </span>
    </div>
  )
}

/**
 * Full application review — everything the applicant submitted, so the
 * admin can verify the requirements before approving or rejecting.
 */
export default function ApplicationDetailModal({
  application,
  onClose,
  onApprove,
  onReject,
  approving,
  rejecting,
}) {
  if (!application) return null

  const idTypeLabel =
    ID_TYPE_LABELS[application.id_type] ??
    application.id_type ??
    'Not specified'

  const productPaths = Array.isArray(application.product_photo_urls)
    ? application.product_photo_urls
    : []

  const hasIdentity =
    !!application.id_document_url && !!application.selfie_url

  return (
    <Modal
      open
      onClose={onClose}
      title="Seller Application Review"
      size="xl"
      footer={
        <>
          {application.seller_status === 'pending' && (
            <>
              <button
                type="button"
                onClick={() => onReject(application)}
                disabled={rejecting}
                className="rounded-xl border border-[#D64545] px-4 py-2 text-sm font-semibold text-[#D64545] transition-colors hover:bg-red-50 disabled:opacity-50"
              >
                Reject
              </button>
              <button
                type="button"
                onClick={() => onApprove(application.id)}
                disabled={approving}
                className="rounded-xl bg-[#4ECDC4] px-4 py-2 text-sm font-semibold text-white transition-colors hover:bg-teal-600 disabled:opacity-50"
              >
                {approving ? 'Approving…' : 'Approve'}
              </button>
            </>
          )}
        </>
      }
    >
      <div className="space-y-5">
        {/* ── Applicant ─────────────────────────────────────────── */}
        <div className="flex items-center gap-3">
          <div className="flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-full bg-[#8B5A2B] text-lg font-bold text-white">
            {(application.full_name || application.email || 'U')
              .split(' ')
              .map((w) => w[0])
              .join('')
              .toUpperCase()
              .slice(0, 2)}
          </div>
          <div className="min-w-0">
            <p className="truncate text-sm font-bold text-[#3B2314]">
              {application.full_name || 'Unnamed User'}
            </p>
            <p className="truncate text-xs text-[#6B5C4E]">{application.email}</p>
            <p className="text-xs text-[#6B5C4E]">
              Applied {formatDate(application.created_at)}
              {application.phone ? ` · ${application.phone}` : ''}
            </p>
          </div>
        </div>

        {/* ── Identity ──────────────────────────────────────────── */}
        <div>
          <SectionTitle icon={<UserCheck size={13} />}>Identity verification</SectionTitle>
          <div className="rounded-xl border border-[#D9D0C7] bg-white p-4">
            {hasIdentity ? (
              <div className="flex flex-wrap gap-4">
                <VerificationDoc
                  storagePath={application.id_document_url}
                  bucket={PRIVATE_BUCKET}
                  label="Government ID"
                  size="h-24 w-24"
                />
                <VerificationDoc
                  storagePath={application.selfie_url}
                  bucket={PRIVATE_BUCKET}
                  label="Selfie"
                  size="h-24 w-24"
                />
                <div className="min-w-[160px]">
                  <InfoRow label="ID type" value={idTypeLabel} />
                </div>
              </div>
            ) : (
              <p className="text-xs text-[#6B5C4E]">
                No identity photos submitted (legacy application).
              </p>
            )}
          </div>
        </div>

        {/* ── Personal details + location ──────────────────────── */}
        {(application.birthday ||
          application.gender ||
          application.store_location) && (
          <div>
            <SectionTitle icon={<UserCheck size={13} />}>
              Personal details
            </SectionTitle>
            <div className="rounded-xl border border-[#D9D0C7] bg-white p-4">
              <InfoRow label="Birthday" value={application.birthday} />
              <InfoRow label="Gender" value={application.gender} />
              <InfoRow label="Store location" value={application.store_location} />
            </div>
          </div>
        )}

        {/* ── Business documents (required) ─────────────────────── */}
        {(() => {
          const biz =
            application.seller_business_docs &&
            !Array.isArray(application.seller_business_docs)
              ? application.seller_business_docs
              : Array.isArray(application.seller_business_docs) &&
                  application.seller_business_docs.length > 0
                ? application.seller_business_docs[0]
                : null
          return biz ? (
          <div>
            <SectionTitle icon={<FileText size={13} />}>
              Business documents
            </SectionTitle>
            <div className="rounded-xl border border-[#D9D0C7] bg-white p-4">
              <div className="flex flex-wrap gap-4">
                <VerificationDoc
                  storagePath={biz.dti_cert_url}
                  bucket={PRIVATE_BUCKET}
                  label="DTI cert"
                  size="h-24 w-24"
                />
                <VerificationDoc
                  storagePath={biz.bir_cor_url}
                  bucket={PRIVATE_BUCKET}
                  label="BIR COR"
                  size="h-24 w-24"
                />
                <VerificationDoc
                  storagePath={biz.permit_url}
                  bucket={PRIVATE_BUCKET}
                  label="Permit"
                  size="h-24 w-24"
                />
              </div>
              <p className="mt-3 flex items-center gap-1.5 text-xs text-[#6B5C4E]">
                <BadgeCheck size={13} className="text-[#4ECDC4]" />
                All three are required for approval.
              </p>
            </div>
          </div>
          ) : null
        })()}

        {/* ── Community proof ───────────────────────────────────── */}
        {(application.cufmai_member_id || application.barangay_proof_url) && (
          <div>
            <SectionTitle icon={<Landmark size={13} />}>Community proof</SectionTitle>
            <div className="rounded-xl border border-[#D9D0C7] bg-white p-4">
              {application.cufmai_member_id ? (
                <InfoRow
                  label="CUFMAI Member ID"
                  value={application.cufmai_member_id}
                />
              ) : (
                <div className="flex flex-wrap items-center gap-4">
                  <VerificationDoc
                    storagePath={application.barangay_proof_url}
                    bucket={PRIVATE_BUCKET}
                    label="Barangay proof"
                    size="h-24 w-24"
                  />
                  <p className="text-xs text-[#6B5C4E]">
                    Non-member — barangay certificate submitted as community
                    proof.
                  </p>
                </div>
              )}
            </div>
          </div>
        )}

        {/* ── Store ─────────────────────────────────────────────── */}
        <div>
          <SectionTitle icon={<Store size={13} />}>Store details</SectionTitle>
          <div className="rounded-xl border border-[#D9D0C7] bg-white p-4">
            <InfoRow label="Store name" value={application.store_name} />
            {Array.isArray(application.store_tags) &&
              application.store_tags.length > 0 && (
                <div className="border-t border-[#F5F0EB] py-2">
                  <p className="text-xs text-[#6B5C4E]">Tags</p>
                  <div className="mt-1.5 flex flex-wrap gap-1.5">
                    {application.store_tags.map((t) => (
                      <span
                        key={t}
                        className="rounded-full border border-[#D9D0C7] bg-[#F5F0EB] px-2.5 py-0.5 text-[11px] font-semibold text-[#8B5A2B]"
                      >
                        {tagLabel(t)}
                      </span>
                    ))}
                  </div>
                </div>
              )}
            {application.store_description && (
              <div className="border-t border-[#F5F0EB] py-2">
                <p className="text-xs text-[#6B5C4E]">Description</p>
                <p className="mt-0.5 text-sm text-[#3B2314]">
                  {application.store_description}
                </p>
              </div>
            )}
          </div>
        </div>

        {/* ── Store photos ──────────────────────────────────────── */}
        {(application.store_front_url || productPaths.length > 0) && (
          <div>
            <SectionTitle icon={<FileText size={13} />}>Store photos</SectionTitle>
            <div className="rounded-xl border border-[#D9D0C7] bg-white p-4">
              <div className="flex flex-wrap gap-4">
                <VerificationDoc
                  storagePath={application.store_front_url}
                  bucket={PUBLIC_BUCKET}
                  label="Store front"
                  size="h-24 w-24"
                />
                {productPaths.map((path, i) => (
                  <VerificationDoc
                    key={path}
                    storagePath={path}
                    bucket={PRIVATE_BUCKET}
                    label={`Product ${i + 1}`}
                    size="h-24 w-24"
                  />
                ))}
              </div>
              {productPaths.length === 0 && !application.store_front_url && (
                <p className="text-xs text-[#6B5C4E]">No store photos submitted.</p>
              )}
              <p className="mt-3 flex items-center gap-1.5 text-xs text-[#6B5C4E]">
                <BadgeCheck size={13} className="text-[#4ECDC4]" />
                The store-front photo doubles as the store banner after
                approval.
              </p>
            </div>
          </div>
        )}
      </div>
    </Modal>
  )
}
