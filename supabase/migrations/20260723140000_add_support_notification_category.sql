-- ══════════════════════════════════════════════════════════════════
-- Migration: Add 'support' notification category
-- Date: July 23, 2026
-- Purpose: Allow report response notifications to appear in the
--          customer/seller notifications feed under a "Support" category.
-- ══════════════════════════════════════════════════════════════════

-- 1. Add 'support' to the notification_category enum
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum e
        JOIN pg_type t ON e.enumtypid = t.oid
        WHERE t.typname = 'notification_category' AND e.enumlabel = 'support'
    ) THEN
        ALTER TYPE public.notification_category ADD VALUE 'support';
    END IF;
END $$;
