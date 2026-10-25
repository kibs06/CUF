-- 360° foot scan jobs (own-build measurement-first pass).
--
-- Capture happens in the customer portal (`/foot-scan`): the browser
-- auto-captures angle-tagged frames around the foot and uploads them to
-- the private `foot-scans` bucket. A row here tracks one sweep from
-- upload through cloud reconstruction to measured numbers. The
-- reconstruction worker itself is pluggable (managed photogrammetry API
-- first) — this table is the stable contract whatever worker runs.
--
-- Privacy: frames are biometric-adjacent. Bucket is PRIVATE, RLS is
-- owner-only on both table and objects, frames are expected to be
-- purged ~30 days after processing (retention job is a later pass;
-- `frames_purged_at` records it). Meshes live until the user deletes
-- the job row.

CREATE TABLE IF NOT EXISTS foot_scan_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- queued → uploading → processing → done | failed
  status TEXT NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'uploading', 'processing', 'done', 'failed')),

  -- Capture evidence: how many gated frames, what orbit they covered.
  frame_count INTEGER NOT NULL DEFAULT 0,
  angle_coverage_deg DOUBLE PRECISION,

  -- Reconstruction output.
  mesh_path TEXT,
  measurements JSONB,

  -- Failure surface: machine code + customer-safe sentence.
  error_code TEXT,
  error_message TEXT,

  frames_purged_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE foot_scan_jobs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own foot scan jobs" ON foot_scan_jobs;
CREATE POLICY "Users can view own foot scan jobs"
  ON foot_scan_jobs FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own foot scan jobs" ON foot_scan_jobs;
CREATE POLICY "Users can insert own foot scan jobs"
  ON foot_scan_jobs FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own foot scan jobs" ON foot_scan_jobs;
CREATE POLICY "Users can update own foot scan jobs"
  ON foot_scan_jobs FOR UPDATE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own foot scan jobs" ON foot_scan_jobs;
CREATE POLICY "Users can delete own foot scan jobs"
  ON foot_scan_jobs FOR DELETE
  USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_foot_scan_jobs_user_created
  ON foot_scan_jobs (user_id, created_at DESC);

-- ──────────────────────────────────────────────────────────────
-- The foot-scans bucket (PRIVATE — never public: scan frames are
-- biometric-adjacent and the mesh is personal geometry).
-- 50 MB cap: ~60 JPEG frames at the 1280px client budget land well
-- under it; the cap is the "something went wrong" line, not a target.
-- ──────────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'foot-scans',
  'foot-scans',
  false,
  52428800, -- 50 MB
  ARRAY['image/jpeg', 'model/gltf-binary']
)
ON CONFLICT (id) DO UPDATE
  SET public = EXCLUDED.public,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Owner-scoped object access. First path segment must be the caller's
-- own user id (`<uid>/frames/...`, `<uid>/mesh/...`), compared as text
-- so a malformed path can never raise a cast error inside a policy.
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE policyname = 'Users can manage own foot scans' AND tablename = 'objects'
    ) THEN
        CREATE POLICY "Users can manage own foot scans"
            ON storage.objects FOR ALL
            USING (
                bucket_id = 'foot-scans'
                AND (storage.foldername(name))[1] = auth.uid()::text
            )
            WITH CHECK (
                bucket_id = 'foot-scans'
                AND (storage.foldername(name))[1] = auth.uid()::text
            );
    END IF;
END $$;
