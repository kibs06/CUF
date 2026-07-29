-- Store Auto-Schedule: adds fields for automatic daily open/close scheduling.
-- Timezone assumption: Asia/Manila (UTC+8). Store times are local wall-clock time.
-- Overnight schedules supported: close_time < open_time means e.g. 6 PM – 2 AM.

ALTER TABLE public.stores
  ADD COLUMN IF NOT EXISTS auto_schedule_enabled BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS open_time  TIME,   -- e.g. '09:00:00' (local wall-clock)
  ADD COLUMN IF NOT EXISTS close_time TIME,   -- e.g. '21:00:00' (local wall-clock)
  ADD COLUMN IF NOT EXISTS manual_override BOOLEAN DEFAULT false;
  -- manual_override = true means seller manually forced a state that
  -- differs from what the schedule would currently say; the Edge Function
  -- is responsible for clearing this flag at the next natural schedule transition.

COMMENT ON COLUMN public.stores.auto_schedule_enabled IS 'When true, is_open is controlled automatically by the cron job based on open_time/close_time.';
COMMENT ON COLUMN public.stores.open_time IS 'Daily open time in local wall-clock (Asia/Manila). Ignored if auto_schedule_enabled is false.';
COMMENT ON COLUMN public.stores.close_time IS 'Daily close time in local wall-clock. If close_time < open_time, the schedule spans midnight.';
COMMENT ON COLUMN public.stores.manual_override IS 'When true, the seller manually toggled is_open while auto_schedule is on. The cron job clears this at the next natural transition.';
