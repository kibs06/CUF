-- Coverage receipt for the 360° foot scan: share of frame angle tags the
-- compass (not the elapsed-time prior) vouches for, 0–1.
--
-- The capture page fuses deviceorientation headings with time
-- (`createOrbitTracker`); this column is where that truthfulness number
-- lands so the results page and QA can tell a compass-tracked sweep from
-- a timer-tracked one. NULL/0 = timer only (old phone, denied
-- permission) — still a valid sweep, just a weaker receipt.
ALTER TABLE foot_scan_jobs
  ADD COLUMN IF NOT EXISTS heading_share DOUBLE PRECISION NOT NULL DEFAULT 0;
