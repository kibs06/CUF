-- ══════════════════════════════════════════════════════════════════
-- 18. REPORTS — Unified reporting system
-- ══════════════════════════════════════════════════════════════════

-- Enum types for reports
DO $$ BEGIN
  CREATE TYPE report_type AS ENUM ('message', 'product', 'seller', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE report_status AS ENUM ('pending', 'under_review', 'resolved', 'dismissed');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE report_action AS ENUM ('none', 'warning_issued', 'content_removed', 'seller_suspended', 'refund_issued', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS public.reports (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id           UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  reporter_role         TEXT NOT NULL CHECK (reporter_role IN ('customer', 'seller')),
  type                  report_type NOT NULL,
  category              TEXT NOT NULL,
  priority              TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('high', 'normal')),
  target_message_id     UUID,
  target_order_id       BIGINT,
  target_seller_id      UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  target_store_id       UUID,
  target_product_id     TEXT,
  conversation_id       UUID,
  status                report_status NOT NULL DEFAULT 'pending',
  action_taken          report_action DEFAULT 'none',
  admin_notes           TEXT,
  reporter_notified     BOOLEAN DEFAULT false,
  reporter_notification_text TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_reports_reporter_id ON public.reports(reporter_id);
CREATE INDEX idx_reports_status ON public.reports(status);
CREATE INDEX idx_reports_priority ON public.reports(priority);
CREATE INDEX idx_reports_type ON public.reports(type);
CREATE INDEX idx_reports_created_at ON public.reports(created_at DESC);
CREATE INDEX idx_reports_target_seller_id ON public.reports(target_seller_id);

-- RLS
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

-- Reporters can read their own reports
CREATE POLICY "Reporters can read own reports"
  ON public.reports FOR SELECT
  USING (auth.uid() = reporter_id);

-- Any authenticated user can insert reports (they set reporter_id = auth.uid())
CREATE POLICY "Users can submit reports"
  ON public.reports FOR INSERT
  WITH CHECK (auth.uid() = reporter_id);

-- Reporters can update their own reports (limited fields)
CREATE POLICY "Reporters can update own reports"
  ON public.reports FOR UPDATE
  USING (auth.uid() = reporter_id)
  WITH CHECK (auth.uid() = reporter_id);

-- Admins have full access
CREATE POLICY "Admins can read all reports"
  ON public.reports FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "Admins can update all reports"
  ON public.reports FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "Admins can delete reports"
  ON public.reports FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Auto-compute priority from category on insert/update
-- HIGH_PRIORITY_CATEGORIES: spam_scam, never_received, scam_fraud, counterfeit
CREATE OR REPLACE FUNCTION public.compute_report_priority()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.category IN ('spam_scam', 'never_received', 'scam_fraud', 'counterfeit') THEN
    NEW.priority := 'high';
  ELSE
    NEW.priority := 'normal';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_compute_report_priority ON public.reports;
CREATE TRIGGER trg_compute_report_priority
  BEFORE INSERT OR UPDATE OF category ON public.reports
  FOR EACH ROW
  EXECUTE FUNCTION public.compute_report_priority();

-- Duplicate prevention: prevent same reporter+target+category within 24 hours
CREATE OR REPLACE FUNCTION public.check_duplicate_report()
RETURNS TRIGGER AS $$
DECLARE
  existing_count INTEGER;
BEGIN
  -- Skip check for 'other' type (no specific target)
  IF NEW.type = 'other' THEN
    RETURN NEW;
  END IF;

  -- Check for duplicate within 24 hours using type-specific target columns
  SELECT COUNT(*) INTO existing_count
  FROM public.reports
  WHERE reporter_id = NEW.reporter_id
    AND category = NEW.category
    AND type = NEW.type
    AND created_at > now() - INTERVAL '24 hours'
    AND (
      (NEW.type = 'message' AND target_message_id = NEW.target_message_id)
      OR (NEW.type = 'product' AND target_order_id = NEW.target_order_id)
      OR (NEW.type = 'seller' AND target_seller_id = NEW.target_seller_id)
    );

  IF existing_count > 0 THEN
    RAISE EXCEPTION 'duplicate_report: You have already reported this recently. Our team is reviewing it.';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_check_duplicate_report ON public.reports;
CREATE TRIGGER trg_check_duplicate_report
  BEFORE INSERT ON public.reports
  FOR EACH ROW
  EXECUTE FUNCTION public.check_duplicate_report();
