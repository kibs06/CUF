-- Foot measurements table for the AR Foot Sizing feature.
-- Supports both paper-based scans and live ARCore scans.
-- The 'paper_size_used' column distinguishes: 'ar' (live AR), 'a4', or 'letter'.

CREATE TABLE IF NOT EXISTS foot_measurements (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Raw measurements (millimeters)
  foot_length_left_mm DOUBLE PRECISION,
  foot_width_left_mm DOUBLE PRECISION,
  foot_length_right_mm DOUBLE PRECISION,
  foot_width_right_mm DOUBLE PRECISION,

  -- Recommended sizes (derived from the larger foot)
  recommended_eu_size TEXT,
  recommended_us_size TEXT,
  recommended_uk_size TEXT,

  -- Scan metadata
  paper_size_used TEXT NOT NULL DEFAULT 'a4', -- 'ar', 'a4', or 'letter'
  foot_condition TEXT, -- 'bare' or 'socks'

  -- User-adjusted size (nullable — null means user accepted the recommendation)
  user_adjusted_eu_size TEXT,

  -- Confidence signals (0.0–1.0)
  paper_detection_confidence DOUBLE PRECISION,
  lighting_quality DOUBLE PRECISION,

  -- Live AR confidence (§7 of the implementation prompt)
  -- Stores numeric spread (IQR), not just High/Med/Low label,
  -- so thresholds can be tuned later without a migration.
  length_confidence_left DOUBLE PRECISION,
  length_confidence_right DOUBLE PRECISION,
  overall_confidence_score DOUBLE PRECISION,
  confidence_level TEXT, -- 'high', 'medium', 'low'
  raw_sample_count INTEGER,
  final_sample_count INTEGER,

  -- Timestamps
  scan_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Row-level security: users can only access their own measurements
ALTER TABLE foot_measurements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own foot measurements"
  ON foot_measurements FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own foot measurements"
  ON foot_measurements FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own foot measurements"
  ON foot_measurements FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own foot measurements"
  ON foot_measurements FOR DELETE
  USING (auth.uid() = user_id);

-- Index for quick lookup of user's latest measurement
CREATE INDEX IF NOT EXISTS idx_foot_measurements_user_date
  ON foot_measurements (user_id, scan_date DESC);
