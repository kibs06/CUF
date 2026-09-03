import { useEffect, useState } from 'react'
import { Ban, Eye, KeyRound, Package, RotateCcw, Store } from 'lucide-react'
import Badge from '../ui/Badge.jsx'
import Modal from '../ui/Modal.jsx'
import { useToast } from '../ui/Toast.jsx'
import { useUpdateUserRole, useUpdateUserStatus } from '../../hooks/useUsers.js'
import { useSellerPortfolio, useUserOrders } from '../../hooks/useUserDetail.js'
import { useUserDocuments } from '../../hooks/useUserDocuments.js'
import { formatCurrency, formatDate } from '../../lib/constants'

function getInitials(name) {
  return (name || 'U')
    .split(' ')
    .map((w) => w[0])
    .join('')
    .toUpperCase()
    .slice(0, 2)
}

const ROLE_META = {
  seller: { badge: 'bg-teal-100 text-teal-700', avatar: 'bg-[#4ECDC4]', header: 'bg-teal-50' },
  admin: { badge: 'bg-red-100 text-red-700', avatar: 'bg-[#D64545]', header: 'bg-red-50' },
  customer: { badge: 'bg-amber-100 text-amber-700', avatar: 'bg-[#E8A020]', header: 'bg-amber-50' },
}

function Stat({ label, value, sub }) {
  return (
    <div className="rounded-xl bg-[#F5F0EB] p-3">
      <p className="mb-1 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">{label}</p>
      <p className="font-mono text-sm font-bold text-[#3B2314]">{value}</p>
      {sub && <p className="mt-0.5 text-xs text-[#6B5C4E]">{sub}</p>}
    </div>
  )
}

export default function UserDetailModal({ user, onClose }) {
  const { showToast } = useToast()
  const updateStatus = useUpdateUserStatus()
  const updateRole = useUpdateUserRole()

  const [tab, setTab] = useState('account')
  const [suspendOpen, setSuspendOpen] = useState(false)
  const [suspendReason, setSuspendReason] = useState('')
  const [roleOpen, setRoleOpen] = useState(false)
  const [roleValue, setRoleValue] = useState('customer')
  const [busy, setBusy] = useState(false)

  // Always call hooks (they self-disable when user is null).
  const ordersQ = useUserOrders(user?.id)
  const portfolioQ = useSellerPortfolio(user?.id)
  const documentsQ = useUserDocuments(user?.id)

  useEffect(() => {
    setTab('account')
    setSuspendReason('')
    setRoleValue(user?.role ?? 'customer')
  }, [user?.id]) // eslint-disable-line react-hooks/exhaustive-deps

  if (!user) return null

  const isSuspended = !!user.suspended
  const isSeller = user.role === 'seller'
  const meta = ROLE_META[user.role] ?? ROLE_META.customer
  const initials = getInitials(user.full_name)

  const handleToggleSuspend = async () => {
    setBusy(true)
    try {
      if (!isSuspended) {
        await updateStatus.mutateAsync({
          userId: user.id,
          suspended: true,
          reason: suspendReason,
        })
        showToast('Account suspended')
      } else {
        await updateStatus.mutateAsync({ userId: user.id, suspended: false })
        showToast('Account reactivated')
      }
      setSuspendOpen(false)
    } catch (err) {
      showToast(err.message ?? 'Failed to update account', 'error')
    } finally {
      setBusy(false)
    }
  }

  const handleRoleChange = async () => {
    if (roleValue === user.role) {
      setRoleOpen(false)
      return
    }
    setBusy(true)
    try {
      await updateRole.mutateAsync({ userId: user.id, role: roleValue })
      showToast(`Role changed to ${roleValue}`)
      setRoleOpen(false)
    } catch (err) {
      showToast(err.message ?? 'Failed to update role', 'error')
    } finally {
      setBusy(false)
    }
  }

  const orders = ordersQ.data ?? []
  const portfolio = portfolioQ.data

  return (
    <Modal open onClose={onClose} title="User Details" size="xl">
      {/* ── Header ─────────────────────────────────────────────── */}
      <div className={`-mx-6 -mt-6 mb-5 flex items-start gap-4 px-6 py-5 ${meta.header}`}>
        {user.avatar_url ? (
          <img
            src={user.avatar_url}
            alt=""
            className="h-16 w-16 rounded-2xl border-2 border-white object-cover shadow-md"
          />
        ) : (
          <div
            className={`flex h-16 w-16 items-center justify-center rounded-2xl text-2xl font-bold text-white shadow-md ${meta.avatar}`}
          >
            {initials}
          </div>
        )}
        <div className="min-w-0 flex-1">
          <h2 className="font-display text-xl font-bold text-[#3B2314]">
            {user.full_name || 'Unnamed User'}
          </h2>
          <p className="mt-0.5 truncate text-sm text-[#6B5C4E]">{user.email}</p>
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <span className={`rounded-full px-3 py-1 text-xs font-bold ${meta.badge}`}>
              {user.role}
            </span>
            {isSuspended && <Badge label="Suspended" variant="suspended" dot />}
            {isSeller && user.seller_status && (
              <Badge label={user.seller_status} variant={user.seller_status} />
            )}
          </div>
        </div>
      </div>

      {/* ── Tabs ───────────────────────────────────────────────── */}
      <div className="mb-4 flex gap-2">
        <TabButton active={tab === 'account'} onClick={() => setTab('account')}>
          Account
        </TabButton>
        {!isSeller && (
          <TabButton
            active={tab === 'orders'}
            onClick={() => setTab('orders')}
            count={orders.length}
          >
            Orders
          </TabButton>
        )}
        {isSeller && (
          <TabButton
            active={tab === 'business'}
            onClick={() => setTab('business')}
            count={portfolio ? portfolio.totalOrders + portfolio.totalPosSales : null}
          >
            Business
          </TabButton>
        )}
        <TabButton
          active={tab === 'documents'}
          onClick={() => setTab('documents')}
        >
          Documents
        </TabButton>
      </div>

      {/* ── Account tab ────────────────────────────────────────── */}
      {tab === 'account' && (
        <div className="space-y-5">
          <div className="grid grid-cols-2 gap-3">
            <Stat label="Member Since" value={formatDate(user.created_at)} />
            <Stat label="User ID" value={`${String(user.id).slice(0, 8)}…`} />
            <Stat label="Phone" value={user.phone || '—'} />
            {isSeller ? (
              <Stat
                label="Seller Status"
                value={
                  <span className="capitalize">{user.seller_status ?? 'none'}</span>
                }
              />
            ) : (
              <Stat label="Role" value={user.role} />
            )}
          </div>

          {isSuspended && (
            <div className="rounded-xl border border-[#D64545]/30 bg-red-50 px-4 py-3">
              <p className="text-xs font-bold uppercase tracking-wider text-[#D64545]">
                Suspended {user.suspended_at ? formatDate(user.suspended_at) : ''}
              </p>
              <p className="mt-1 text-sm text-[#6B5C4E]">
                {user.suspended_reason || 'No reason recorded.'}
              </p>
            </div>
          )}

          {/* Actions */}
          <div className="rounded-xl border border-[#D9D0C7] bg-white p-4">
            <p className="mb-3 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
              Admin Actions
            </p>
            <div className="flex flex-wrap gap-2">
              <button
                type="button"
                onClick={() => setRoleOpen(true)}
                className="inline-flex items-center gap-2 rounded-lg border border-[#8B5A2B] px-3 py-2 text-sm font-semibold text-[#8B5A2B] transition-colors hover:bg-[#8B5A2B]/10"
              >
                <KeyRound size={15} />
                Change role
              </button>
              {isSuspended ? (
                <button
                  type="button"
                  onClick={() => setSuspendOpen(true)}
                  className="inline-flex items-center gap-2 rounded-lg bg-teal-600 px-3 py-2 text-sm font-semibold text-white transition-colors hover:bg-teal-700"
                >
                  <RotateCcw size={15} />
                  Reactivate account
                </button>
              ) : (
                <button
                  type="button"
                  onClick={() => setSuspendOpen(true)}
                  className="inline-flex items-center gap-2 rounded-lg border border-[#D64545] px-3 py-2 text-sm font-semibold text-[#D64545] transition-colors hover:bg-red-50"
                >
                  <Ban size={15} />
                  Suspend account
                </button>
              )}
            </div>
            <p className="mt-3 text-xs text-[#6B5C4E]">
              Suspended accounts lose all access immediately: they cannot sign in,
              place orders, message sellers, or manage products (enforced by RLS).
            </p>
          </div>
        </div>
      )}

      {/* ── Orders tab (customers) ─────────────────────────────── */}
      {tab === 'orders' && (
        <div className="space-y-2">
          {ordersQ.isLoading && <p className="py-6 text-center text-sm text-[#6B5C4E]">Loading orders…</p>}
          {!ordersQ.isLoading && orders.length === 0 && (
            <p className="py-6 text-center text-sm text-[#6B5C4E]">No orders yet.</p>
          )}
          {orders.map((order) => (
            <div
              key={order.id}
              className="flex items-center justify-between gap-3 rounded-xl border border-[#D9D0C7] bg-white px-4 py-3"
            >
              <div className="min-w-0">
                <p className="truncate text-sm font-semibold text-[#3B2314]">
                  {order.store_name}
                </p>
                <p className="text-xs text-[#6B5C4E]">
                  {formatDate(order.created_at)} · {order.items_count} item(s)
                  {order.payment_method ? ` · ${order.payment_method}` : ''}
                </p>
              </div>
              <div className="flex flex-shrink-0 items-center gap-3">
                <Badge label={order.status} variant={order.status} />
                <span className="font-mono text-sm font-bold text-[#3B2314]">
                  {formatCurrency(order.total_amount)}
                </span>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* ── Business tab (sellers) ─────────────────────────────── */}
      {tab === 'business' && portfolioQ.isLoading && (
        <p className="py-6 text-center text-sm text-[#6B5C4E]">Loading business data…</p>
      )}
      {tab === 'business' && portfolioQ.data && (
        <div className="space-y-5">
          {/* Stores */}
          {portfolio.stores.length > 0 && (
            <div className="space-y-2">
              <SectionTitle>Stores</SectionTitle>
              {portfolio.stores.map((store) => (
                <div
                  key={store.id}
                  className="flex items-center justify-between rounded-xl border border-[#D9D0C7] bg-white px-4 py-3"
                >
                  <div className="flex items-center gap-3">
                    <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-[#8B5A2B]/10 text-[#8B5A2B]">
                      <Store size={16} />
                    </div>
                    <div>
                      <p className="text-sm font-semibold text-[#3B2314]">{store.name}</p>
                      <p className="text-xs text-[#6B5C4E]">{store.location}</p>
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    {store.is_open ? (
                      <Badge label="Open" variant="active" dot />
                    ) : (
                      <Badge label="Closed" variant="inactive" dot />
                    )}
                    {!store.is_active && <Badge label="Deactivated" variant="rejected" />}
                  </div>
                </div>
              ))}
            </div>
          )}

          {/* KPIs */}
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
            <Stat label="Online Orders" value={portfolio.totalOrders} />
            <Stat label="Online Revenue" value={formatCurrency(portfolio.revenue)} />
            <Stat label="POS Sales" value={portfolio.totalPosSales} />
            <Stat label="POS Revenue" value={formatCurrency(portfolio.posRevenue)} />
            <Stat label="Products" value={portfolio.products.length} />
            <Stat label="Total Revenue" value={formatCurrency(portfolio.totalRevenue)} />
          </div>

          {/* Product listings */}
          <div>
            <SectionTitle>
              Product Listings ({portfolio.products.length})
            </SectionTitle>
            <div className="overflow-hidden rounded-xl border border-[#D9D0C7] bg-white">
              {portfolio.products.length === 0 ? (
                <p className="px-4 py-6 text-center text-sm text-[#6B5C4E]">
                  No products yet.
                </p>
              ) : (
                portfolio.products.slice(0, 30).map((p, idx) => (
                  <div
                    key={p.id}
                    className={`flex items-center gap-3 px-4 py-2.5 ${
                      idx > 0 ? 'border-t border-[#F5F0EB]' : ''
                    }`}
                  >
                    {p.thumbnail ? (
                      <img
                        src={p.thumbnail}
                        alt=""
                        className="h-9 w-9 flex-shrink-0 rounded-lg object-cover"
                      />
                    ) : (
                      <div className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-lg bg-[#F5F0EB] text-[#6B5C4E]">
                        <Package size={15} />
                      </div>
                    )}
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium text-[#3B2314]">{p.name}</p>
                      <p className="text-xs text-[#6B5C4E]">{p.category}</p>
                    </div>
                    <span className="hidden font-mono text-xs text-[#6B5C4E] sm:block">
                      stock {p.total_stock}
                    </span>
                    <div className="flex flex-shrink-0 items-center gap-2">
                      {p.is_published === false && <Badge label="Hidden" variant="inactive" />}
                      <span className="w-20 text-right font-mono text-sm font-bold text-[#3B2314]">
                        {formatCurrency(p.sale_price ?? p.price)}
                      </span>
                    </div>
                  </div>
                ))
              )}
            </div>
          </div>
        </div>
      )}

      {/* ── Documents tab ─────────────────────────────────────── */}
      {tab === 'documents' && documentsQ.isLoading && (
        <p className="py-6 text-center text-sm text-[#6B5C4E]">Loading documents…</p>
      )}
      {tab === 'documents' && documentsQ.data && (
        <div className="space-y-6">
          {/* Personal Information */}
          <DocumentSection title="Personal Information">
            <div className="grid grid-cols-2 gap-3">
              <InfoField label="Full Name" value={documentsQ.data.personal.fullName} />
              <InfoField label="Email" value={documentsQ.data.personal.email} />
              <InfoField label="Phone" value={documentsQ.data.personal.phone} />
              <InfoField label="Birthday" value={documentsQ.data.personal.birthday ? formatDate(documentsQ.data.personal.birthday) : null} />
              <InfoField label="Gender" value={documentsQ.data.personal.gender} />
              <InfoField label="Member Since" value={formatDate(documentsQ.data.personal.createdAt)} />
            </div>
          </DocumentSection>

          {/* Store Information */}
          <DocumentSection title="Store Information">
            <div className="grid grid-cols-2 gap-3">
              <InfoField label="Store Name" value={documentsQ.data.store.name} />
              <InfoField label="Location" value={documentsQ.data.store.location} />
              {documentsQ.data.store.lat && documentsQ.data.store.lng && (
                <InfoField
                  label="Coordinates"
                  value={`${documentsQ.data.store.lat}, ${documentsQ.data.store.lng}`}
                />
              )}
            </div>
            {documentsQ.data.store.description && (
              <div className="mt-3">
                <p className="text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Description</p>
                <p className="mt-1 text-sm text-[#3B2314]">{documentsQ.data.store.description}</p>
              </div>
            )}
            {documentsQ.data.store.tags.length > 0 && (
              <div className="mt-3">
                <p className="text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">Tags</p>
                <div className="mt-1 flex flex-wrap gap-2">
                  {documentsQ.data.store.tags.map((tag, idx) => (
                    <span
                      key={idx}
                      className="rounded-full bg-[#8B5A2B]/10 px-2.5 py-1 text-xs font-medium text-[#8B5A2B]"
                    >
                      {tag}
                    </span>
                  ))}
                </div>
              </div>
            )}
            {documentsQ.data.application.rejectionReason && (
              <div className="mt-3 rounded-xl border border-[#D64545]/30 bg-red-50 p-3">
                <p className="text-xs font-bold uppercase tracking-wider text-[#D64545]">Rejection Reason</p>
                <p className="mt-1 text-sm text-[#6B5C4E]">{documentsQ.data.application.rejectionReason}</p>
              </div>
            )}
          </DocumentSection>

          {/* Identity Documents */}
          <DocumentSection title="Identity Documents">
            <DocumentGrid>
              <DocumentCard
                label={documentsQ.data.identity.idDocument.label}
                url={documentsQ.data.identity.idDocument.url}
                subtitle={documentsQ.data.identity.idDocument.type ? `Type: ${documentsQ.data.identity.idDocument.type}` : null}
                sensitive={true}
              />
              <DocumentCard
                label={documentsQ.data.identity.selfie.label}
                url={documentsQ.data.identity.selfie.url}
                sensitive={true}
              />
              <DocumentCard
                label={documentsQ.data.identity.barangay.label}
                url={documentsQ.data.identity.barangay.url}
                sensitive={true}
              />
            </DocumentGrid>
            {documentsQ.data.identity.cufmaiMemberId && (
              <div className="mt-3">
                <InfoField label="CUFMAI Member ID" value={documentsQ.data.identity.cufmaiMemberId} />
              </div>
            )}
          </DocumentSection>

          {/* Business Documents (Tier 2) */}
          <DocumentSection title="Business Documents (Tier 2)">
            {documentsQ.data.business ? (
              <>
                <div className="mb-3">
                  <Badge
                    label={`Status: ${documentsQ.data.business.status}`}
                    variant={documentsQ.data.business.status}
                  />
                </div>
                <DocumentGrid>
                  <DocumentCard
                    label={documentsQ.data.business.dti.label}
                    url={documentsQ.data.business.dti.url}
                    sensitive={true}
                  />
                  <DocumentCard
                    label={documentsQ.data.business.bir.label}
                    url={documentsQ.data.business.bir.url}
                    sensitive={true}
                  />
                  <DocumentCard
                    label={documentsQ.data.business.permit.label}
                    url={documentsQ.data.business.permit.url}
                    sensitive={true}
                  />
                </DocumentGrid>
                {documentsQ.data.business.submittedAt && (
                  <p className="mt-3 text-xs text-[#6B5C4E]">
                    Submitted: {formatDate(documentsQ.data.business.submittedAt)}
                    {documentsQ.data.business.verifiedAt && (
                      <> · Verified: {formatDate(documentsQ.data.business.verifiedAt)}</>
                    )}
                  </p>
                )}
              </>
            ) : (
              <p className="text-sm text-[#6B5C4E]">No business documents submitted.</p>
            )}
          </DocumentSection>

          {/* Store Photos */}
          <DocumentSection title="Store Photos">
            <DocumentGrid>
              <DocumentCard
                label={documentsQ.data.store.storefront.label}
                url={documentsQ.data.store.storefront.url}
                bucket="store-assets"
              />
              {documentsQ.data.store.products.map((product, idx) => (
                <DocumentCard
                  key={idx}
                  label={product.label}
                  url={product.url}
                />
              ))}
            </DocumentGrid>
            {documentsQ.data.store.products.length === 0 && !documentsQ.data.store.storefront.url && (
              <p className="text-sm text-[#6B5C4E]">No store photos submitted.</p>
            )}
          </DocumentSection>
        </div>
      )}

      {/* ── Suspend / reactivate confirmation ──────────────────── */}
      <Modal
        open={suspendOpen}
        onClose={() => {
          setSuspendOpen(false)
          setSuspendReason('')
        }}
        title={isSuspended ? 'Reactivate account?' : 'Suspend account?'}
        footer={
          <>
            <button
              type="button"
              onClick={() => setSuspendOpen(false)}
              className="rounded-xl border border-[#D9D0C7] px-4 py-2 text-sm text-[#6B5C4E] hover:bg-[#F5F0EB]"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleToggleSuspend}
              disabled={busy}
              className={`rounded-xl px-4 py-2 text-sm font-semibold text-white transition-colors disabled:opacity-50 ${
                isSuspended
                  ? 'bg-teal-600 hover:bg-teal-700'
                  : 'bg-[#D64545] hover:bg-red-700'
              }`}
            >
              {busy ? 'Working…' : isSuspended ? 'Reactivate' : 'Suspend'}
            </button>
          </>
        }
      >
        <p className="mb-4 text-sm text-[#6B5C4E]">
          {isSuspended ? (
            <>
              Allow <strong className="text-[#3B2314]">{user.full_name}</strong> back
              into the app? They regain sign-in, ordering, and selling access
              immediately.
            </>
          ) : (
            <>
              Ban <strong className="text-[#3B2314]">{user.full_name}</strong> from
              the app? They will be blocked from signing in and all API writes the
              moment this is saved.
            </>
          )}
        </p>
        {!isSuspended && (
          <>
            <label className="mb-1.5 block text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
              Reason (recommended)
            </label>
            <textarea
              value={suspendReason}
              onChange={(e) => setSuspendReason(e.target.value)}
              rows={3}
              autoFocus
              className="w-full rounded-xl border border-[#D9D0C7] bg-[#F5F0EB] px-3 py-2 text-sm text-[#3B2314] outline-none transition-colors focus:border-[#8B5A2B] focus:ring-2 focus:ring-[#8B5A2B]/20"
              placeholder="e.g. Spam listings, chargeback risk, abusive messages…"
            />
          </>
        )}
      </Modal>

      {/* ── Role change confirmation ───────────────────────────── */}
      <Modal
        open={roleOpen}
        onClose={() => setRoleOpen(false)}
        title="Change account role"
        footer={
          <>
            <button
              type="button"
              onClick={() => setRoleOpen(false)}
              className="rounded-xl border border-[#D9D0C7] px-4 py-2 text-sm text-[#6B5C4E] hover:bg-[#F5F0EB]"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={handleRoleChange}
              disabled={busy || roleValue === user.role}
              className="rounded-xl bg-[#8B5A2B] px-4 py-2 text-sm font-semibold text-white transition-colors hover:bg-[#6B4520] disabled:opacity-50"
            >
              {busy ? 'Working…' : 'Save role'}
            </button>
          </>
        }
      >
        <p className="mb-4 text-sm text-[#6B5C4E]">
          Change <strong className="text-[#3B2314]">{user.full_name}</strong>'s role.
          Making someone an admin grants full console access — and the database
          refuses to demote or suspend the last active admin.
        </p>
        <div className="space-y-2">
          {[
            { value: 'customer', label: 'Customer', desc: 'Standard shopper account' },
            { value: 'seller', label: 'Seller', desc: 'Can run a store, manage products, take POS sales' },
            { value: 'admin', label: 'Admin', desc: 'Full admin portal access' },
          ].map((opt) => (
            <label
              key={opt.value}
              className={`flex cursor-pointer items-start gap-3 rounded-xl border px-4 py-3 transition-colors ${
                roleValue === opt.value
                  ? 'border-[#8B5A2B] bg-[#8B5A2B]/5'
                  : 'border-[#D9D0C7] bg-white hover:bg-[#FDFAF7]'
              }`}
            >
              <input
                type="radio"
                name="role"
                value={opt.value}
                checked={roleValue === opt.value}
                onChange={() => setRoleValue(opt.value)}
                className="mt-1 accent-[#8B5A2B]"
              />
              <span>
                <span className="block text-sm font-semibold text-[#3B2314]">{opt.label}</span>
                <span className="block text-xs text-[#6B5C4E]">{opt.desc}</span>
              </span>
            </label>
          ))}
        </div>
      </Modal>
    </Modal>
  )
}

function TabButton({ active, onClick, children, count }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`rounded-lg px-3 py-1.5 text-sm font-semibold transition-colors ${
        active
          ? 'bg-[#8B5A2B] text-white shadow-sm'
          : 'border border-[#D9D0C7] bg-white text-[#6B5C4E] hover:bg-[#F5F0EB]'
      }`}
    >
      {children}
      {typeof count === 'number' && count > 0 && (
        <span className={`ml-1.5 font-mono text-xs ${active ? 'text-white/80' : 'text-[#6B5C4E]'}`}>
          {count}
        </span>
      )}
    </button>
  )
}

function SectionTitle({ children }) {
  return (
    <p className="mb-2 text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">
      {children}
    </p>
  )
}

function DocumentSection({ title, children }) {
  return (
    <div>
      <SectionTitle>{title}</SectionTitle>
      {children}
    </div>
  )
}

function DocumentGrid({ children }) {
  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
      {children}
    </div>
  )
}

function DocumentCard({ label, url, subtitle, bucket, sensitive = false }) {
  const [showModal, setShowModal] = useState(false)
  const [isRevealed, setIsRevealed] = useState(false)

  if (!url) {
    return (
      <div className="rounded-xl border border-dashed border-[#D9D0C7] bg-[#F5F0EB] p-3">
        <p className="text-xs font-medium text-[#6B5C4E]">{label}</p>
        <p className="mt-1 text-xs text-[#6B5C4E]/60">Not submitted</p>
      </div>
    )
  }

  // Sensitive document - show blur overlay with reveal button
  if (sensitive && !isRevealed) {
    return (
      <div className="relative rounded-xl border border-[#D64545]/30 bg-white p-3">
        <div className="mb-2 aspect-square overflow-hidden rounded-lg bg-[#F5F0EB] blur-md">
          <img
            src={url}
            alt={label}
            className="h-full w-full object-cover"
            loading="lazy"
          />
        </div>
        <p className="text-xs font-medium text-[#3B2314]">{label}</p>
        {subtitle && (
          <p className="mt-0.5 text-xs text-[#6B5C4E]">{subtitle}</p>
        )}
        <div className="absolute inset-0 flex flex-col items-center justify-center rounded-xl bg-black/5">
          <div className="rounded-full bg-[#D64545] p-2 mb-2">
            <Eye size={16} className="text-white" />
          </div>
          <p className="text-xs font-semibold text-[#D64545]">Sensitive</p>
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation()
              setIsRevealed(true)
            }}
            className="mt-2 rounded-lg bg-[#D64545] px-3 py-1.5 text-xs font-semibold text-white transition-colors hover:bg-[#B33A3A]"
          >
            Reveal
          </button>
        </div>
      </div>
    )
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setShowModal(true)}
        className="group rounded-xl border border-[#D9D0C7] bg-white p-3 text-left transition-colors hover:border-[#8B5A2B] hover:shadow-sm"
      >
        <div className="mb-2 aspect-square overflow-hidden rounded-lg bg-[#F5F0EB]">
          <img
            src={url}
            alt={label}
            className="h-full w-full object-cover transition-transform group-hover:scale-105"
            loading="lazy"
          />
        </div>
        <p className="text-xs font-medium text-[#3B2314]">{label}</p>
        {subtitle && (
          <p className="mt-0.5 text-xs text-[#6B5C4E]">{subtitle}</p>
        )}
        {sensitive && (
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation()
              setIsRevealed(false)
            }}
            className="mt-2 text-xs font-semibold text-[#D64545] hover:text-[#B33A3A]"
          >
            Hide
          </button>
        )}
      </button>

      {/* Full-screen modal */}
      {showModal && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4"
          onClick={() => setShowModal(false)}
        >
          <div className="relative max-h-[90vh] max-w-[90vw]">
            <img
              src={url}
              alt={label}
              className="max-h-[85vh] rounded-lg object-contain shadow-2xl"
            />
            <div className="absolute left-4 top-4 rounded-full bg-black/60 px-3 py-1 text-sm text-white">
              {label}
            </div>
            <button
              type="button"
              onClick={() => setShowModal(false)}
              className="absolute right-4 top-4 flex h-8 w-8 items-center justify-center rounded-full bg-black/60 text-white transition-colors hover:bg-black/80"
            >
              ×
            </button>
          </div>
        </div>
      )}
    </>
  )
}

function InfoField({ label, value }) {
  if (!value) {
    return (
      <div>
        <p className="text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">{label}</p>
        <p className="mt-1 text-sm text-[#6B5C4E]/60">—</p>
      </div>
    )
  }

  return (
    <div>
      <p className="text-xs font-semibold uppercase tracking-wider text-[#6B5C4E]">{label}</p>
      <p className="mt-1 text-sm font-medium text-[#3B2314]">{value}</p>
    </div>
  )
}
