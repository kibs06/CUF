/**
 * Audit logs — the pure half of the admin portal's audit trail.
 *
 * Five sources. Four are written server-side so no client can bypass them;
 * the fifth (sessions) cannot be, and says so:
 *
 *   seller   `seller_application_audit_log` — a trigger appends one row per
 *            profiles.seller_status change (submitted / approved / rejected /
 *            status_changed), with actor, previous/new status and the reviewer
 *            note on reject. Admins SELECT; nobody writes.
 *   payment  `gcash_payment_decision_audit` — one row per seller confirm/reject
 *            on a manual GCash submission, with the reference number and the
 *            server-side amount shown at decision time. Admins SELECT; only the
 *            trigger/RPCs write.
 *   security `failed_logins` — one row per account under brute-force watch,
 *            with attempt count, lockout window, IP, device and the
 *            approximate city-level location. Admins SELECT all.
 *   sessions `account_session_log` — one row per sign-in / sign-out, written
 *            BY THE CLIENTS (portal + app) best-effort. A trigger is
 *            impossible here: sign-ins touch no public table. These rows are
 *            claims, not proof — a tampered client could skip them, and
 *            sessions from before this logging shipped leave no rows.
 *   activity `seller_activity_log` — one row per seller-side product / store /
 *            order-status write, trigger-written and immutable. Admins SELECT;
 *            nobody writes.
 *
 * What this page deliberately does NOT show: live GoTrue events
 * (`auth.audit_log_entries` is not readable from the anon client — the
 * per-account timeline lives behind the `admin_account_security_overview`
 * RPC), and suspensions (the `suspended` flag has no history table; a status
 * change there leaves no trail yet).
 */

export const AUDIT_TABS = [
  { id: 'seller', label: 'Seller decisions' },
  { id: 'payment', label: 'Payment decisions' },
  { id: 'security', label: 'Sign-in security' },
  { id: 'sessions', label: 'Seller sessions' },
  { id: 'activity', label: 'Seller activity' },
]

export const SELLER_ACTIONS = [
  { value: 'all', label: 'All actions' },
  { value: 'submitted', label: 'Submitted' },
  { value: 'approved', label: 'Approved' },
  { value: 'rejected', label: 'Rejected' },
  { value: 'status_changed', label: 'Status changed' },
]

export const PAYMENT_DECISIONS = [
  { value: 'all', label: 'All decisions' },
  { value: 'confirmed', label: 'Confirmed' },
  { value: 'rejected', label: 'Rejected' },
]

export const LOCKOUT_STATUSES = [
  { value: 'all', label: 'All states' },
  { value: 'active', label: 'Active' },
  { value: 'locked', label: 'Locked' },
  { value: 'expired', label: 'Expired' },
]

export const SESSION_EVENTS = [
  { value: 'all', label: 'All events' },
  { value: 'sign_in', label: 'Sign-ins' },
  { value: 'sign_out', label: 'Sign-outs' },
]

export const ACTIVITY_ACTIONS = [
  { value: 'all', label: 'All actions' },
  { value: 'store_created', label: 'Store created' },
  { value: 'store_updated', label: 'Store updated' },
  { value: 'product_created', label: 'Product created' },
  { value: 'product_updated', label: 'Product updated' },
  { value: 'product_removed', label: 'Product removed' },
  { value: 'order_status_changed', label: 'Order status changed' },
]

/** Badge variant keys that already exist — no new tones invented here. */
export function toneFor(action, row) {
  const key = String(action ?? '').toLowerCase()
  if (key === 'submitted') return 'pending'
  if (key === 'status_changed') return 'under_review'
  if (key === 'locked') return 'failed'
  if (key === 'sign_in') return 'active'
  if (key === 'sign_out') return 'expired'
  if (key === 'store_created' || key === 'product_created') return 'confirmed'
  if (key === 'store_updated' || key === 'product_updated') return 'under_review'
  if (key === 'product_removed') return 'cancelled'
  if (key === 'order_status_changed') {
    // Reuse the order-status tone for the status it moved TO — those keys
    // (placed, preparing, ready, …) already exist as badge variants.
    return String(row?.newStatus ?? row?.raw?.new_status ?? 'processing').toLowerCase()
  }
  return key
}

function displayName(person) {
  if (!person) return 'Unknown account'
  if (person.full_name) return person.full_name
  if (person.email) return person.email
  return 'Unknown account'
}

/**
 * One seller-audit row → the shape the table and modal render.
 * `names` maps profile id → { full_name, email }.
 */
export function mapSellerAuditRow(row, names = {}) {
  const actor = names[row.actor_id]
  const subject = names[row.profile_id]
  return {
    id: row.id,
    at: row.created_at,
    action: row.action,
    actor: displayName(actor),
    actorEmail: actor?.email ?? '',
    subject: displayName(subject),
    subjectEmail: subject?.email ?? '',
    previousStatus: row.previous_status ?? '—',
    newStatus: row.new_status ?? '—',
    notes: row.notes ?? '',
    raw: row,
  }
}

/** One payment-decision row → the table shape. */
export function mapPaymentAuditRow(row, names = {}) {
  const seller = names[row.seller_id]
  return {
    id: String(row.id),
    at: row.created_at,
    action: row.decision,
    actor: displayName(seller),
    actorEmail: seller?.email ?? '',
    subject: row.order_id ? `Order ${shortId(row.order_id)}` : 'Deleted order',
    subjectEmail: '',
    reference: row.reference_number ?? '—',
    amount: row.amount_shown_to_seller,
    source: row.source ?? '—',
    notes: '',
    raw: row,
  }
}

/**
 * One failed-logins row → the table shape.
 *
 * The location is city-level by construction (see the migration that added
 * it): an IP address identifies a network, not a person, and a mobile pool
 * can resolve to a different city than the device is in. Rendered with the
 * "(approximate)" qualifier everywhere — never as an address.
 */
export function mapFailedLoginRow(row, names = {}) {
  const account = names[row.user_id]
  const place = row.location ? `${row.location} (approximate)` : '—'
  return {
    id: row.id,
    at: row.failed_at,
    action: row.status,
    actor: displayName(account),
    actorEmail: account?.email ?? '',
    subject: `${row.attempt_count ?? 0} attempt${row.attempt_count === 1 ? '' : 's'}`,
    subjectEmail: '',
    ip: row.ip_address ?? '—',
    device: row.user_agent ?? '—',
    place,
    lockedUntil: row.locked_until ?? null,
    notes: '',
    raw: row,
  }
}

/**
 * One session-log row → the table shape.
 *
 * The account column is the profile; the subject column is the client that
 * recorded the event (a tampered client could lie about it — it is shown
 * for debugging, never as proof).
 */
export function mapSessionRow(row, names = {}) {
  const account = names[row.user_id]
  return {
    id: row.id,
    at: row.created_at,
    action: row.event,
    actor: displayName(account),
    actorEmail: account?.email ?? '',
    subject: row.source ?? '—',
    subjectEmail: '',
    role: row.role ?? '—',
    device: row.user_agent ?? '—',
    notes: '',
    raw: row,
  }
}

/**
 * One seller-activity row → the table shape.
 *
 * Orders render as "Order abcdef…" (the detail carries the transition);
 * products and stores render by name (the detail carries the name).
 */
export function mapActivityRow(row, names = {}) {
  const actor = names[row.actor_id]
  const subject = row.entity === 'order'
    ? `Order ${shortId(row.entity_id)}`
    : (row.detail || humanizeAction(row.entity))
  return {
    id: row.id,
    at: row.created_at,
    action: row.action,
    actor: displayName(actor),
    actorEmail: actor?.email ?? '',
    subject,
    subjectEmail: '',
    entity: row.entity ?? '—',
    detail: row.detail ?? '—',
    previousStatus: row.previous_status ?? '—',
    newStatus: row.new_status ?? '—',
    notes: '',
    raw: row,
  }
}

function humanizeAction(value) {
  return String(value ?? '').replace(/[_]/g, ' ')
}

export function shortId(id) {
  const s = String(id ?? '')
  return s.length > 8 ? `${s.slice(0, 8)}…` : s || '—'
}

export function auditTimeAgo(dateStr) {
  const diff = Date.now() - new Date(dateStr).getTime()
  const mins = Math.floor(diff / 60000)
  if (mins < 1) return 'just now'
  if (mins < 60) return `${mins}m ago`
  const hrs = Math.floor(mins / 60)
  if (hrs < 24) return `${hrs}h ago`
  const days = Math.floor(hrs / 24)
  if (days < 7) return `${days}d ago`
  if (days < 30) return `${Math.floor(days / 7)}w ago`
  if (days < 365) return `${Math.floor(days / 30)}mo ago`
  return `${Math.floor(days / 365)}y ago`
}

export function formatAuditDateTime(value) {
  if (!value) return '—'
  return new Date(value).toLocaleString('en-PH', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

function escCsv(value) {
  const s = String(value ?? '')
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
}

/**
 * Rows → a downloadable CSV. One exporter per tab because the columns differ;
 * the shared contract is only the BOM prefix (Excel reads it as UTF-8) and
 * the filename shape, both copied from the Transactions exporter.
 */
export function sellerAuditCsv(rows) {
  const header = ['At', 'Action', 'Actor', 'Actor email', 'Applicant', 'Applicant email', 'From', 'To', 'Reviewer note']
  const lines = rows.map((r) =>
    [r.at, r.action, r.actor, r.actorEmail, r.subject, r.subjectEmail, r.previousStatus, r.newStatus, r.notes]
      .map(escCsv)
      .join(','),
  )
  return `\uFEFF${[header.join(','), ...lines].join('\n')}`
}

export function paymentAuditCsv(rows) {
  const header = ['At', 'Decision', 'Seller', 'Seller email', 'Order', 'Reference', 'Amount (PHP)', 'Source']
  const lines = rows.map((r) =>
    [r.at, r.action, r.actor, r.actorEmail, r.raw?.order_id ?? '', r.reference, r.amount ?? '', r.source]
      .map(escCsv)
      .join(','),
  )
  return `\uFEFF${[header.join(','), ...lines].join('\n')}`
}

export function securityAuditCsv(rows) {
  const header = ['At', 'State', 'Account', 'Email', 'Attempts', 'IP address', 'Device', 'Location', 'Locked until']
  const lines = rows.map((r) =>
    [r.at, r.action, r.actor, r.actorEmail, r.raw?.attempt_count ?? '', r.ip, r.device, r.raw?.location ?? '', r.lockedUntil ?? '']
      .map(escCsv)
      .join(','),
  )
  return `\uFEFF${[header.join(','), ...lines].join('\n')}`
}

export function sessionAuditCsv(rows) {
  const header = ['At', 'Event', 'Account', 'Email', 'Role', 'Source', 'Device']
  const lines = rows.map((r) =>
    [r.at, r.action, r.actor, r.actorEmail, r.role, r.subject, r.device]
      .map(escCsv)
      .join(','),
  )
  return `\uFEFF${[header.join(','), ...lines].join('\n')}`
}

export function activityAuditCsv(rows) {
  const header = ['At', 'Action', 'Actor', 'Actor email', 'Entity', 'Item', 'From', 'To']
  const lines = rows.map((r) =>
    [r.at, r.action, r.actor, r.actorEmail, r.entity, r.detail, r.previousStatus, r.newStatus]
      .map(escCsv)
      .join(','),
  )
  return `\uFEFF${[header.join(','), ...lines].join('\n')}`
}

export function downloadCsv(filename, csv) {
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}
