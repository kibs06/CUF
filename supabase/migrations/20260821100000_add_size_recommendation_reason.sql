-- Add size recommendation reasoning text to foot_measurements.
-- Stores the human-readable rationale generated alongside the EU size recommendation.

ALTER TABLE foot_measurements
  ADD COLUMN size_recommendation_reason TEXT;
