-- ════════════════════════════════════════════════════════════════════
-- Bulk Reservations — step 1: notification category enum value
-- ════════════════════════════════════════════════════════════════════
-- `ALTER TYPE ... ADD VALUE` cannot have its new value USED inside the same
-- transaction that adds it (Postgres raises "unsafe use of a new value").
-- The bulk-reservation RPCs in 20260913120000 insert 'reservations'
-- notifications, so the enum change ships in its own committed migration.
-- ════════════════════════════════════════════════════════════════════

ALTER TYPE notification_category ADD VALUE IF NOT EXISTS 'reservations' AFTER 'returns';
