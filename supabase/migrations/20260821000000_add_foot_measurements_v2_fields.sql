-- Add v2 fields to foot_measurements:
-- - Compensated measurements (post sock-thickness adjustment)
-- - Sizing foot side (which foot determined the size)
-- - Width-to-fit category
-- - Measurement source tracking
-- - Algorithm version
-- - Shoe category preference

ALTER TABLE foot_measurements
  ADD COLUMN foot_length_left_compensated_mm DOUBLE PRECISION,
  ADD COLUMN foot_width_left_compensated_mm DOUBLE PRECISION,
  ADD COLUMN foot_length_right_compensated_mm DOUBLE PRECISION,
  ADD COLUMN foot_width_right_compensated_mm DOUBLE PRECISION,
  ADD COLUMN sizing_foot_side TEXT,
  ADD COLUMN recommended_width_category TEXT,
  ADD COLUMN measurement_source TEXT DEFAULT 'paper',
  ADD COLUMN algorithm_version TEXT DEFAULT 'v2',
  ADD COLUMN shoe_category TEXT;
