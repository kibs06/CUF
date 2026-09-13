-- ════════════════════════════════════════════════════════════════════
-- Bulk Reservation Deposits — step 1: lifecycle enum value
-- ════════════════════════════════════════════════════════════════════
-- `ALTER TYPE ... ADD VALUE` cannot have its new value USED inside the same
-- transaction that adds it (Postgres raises "unsafe use of a new value").
-- The deposit RPCs in 20260913140000 transition rows to 'awaiting_deposit',
-- so the enum change ships in its own committed migration — exactly the
-- pattern of 20260913110000_add_reservations_notification_category.sql.
--
-- Depends on: 20260913120000_add_bulk_reservations.sql (creates the type).
-- ════════════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'bulk_reservation_status'
  ) THEN
    RAISE EXCEPTION 'bulk_reservation_status type not found — apply 20260913120000_add_bulk_reservations.sql first';
  END IF;
END
$$;

ALTER TYPE bulk_reservation_status ADD VALUE IF NOT EXISTS 'awaiting_deposit' AFTER 'pending';
