-- Store auto-schedule cron: flips stores.is_open every 5 minutes based on
-- open_time/close_time so the DB flag never goes stale. Previously the
-- `apply-store-schedules` edge function existed but no cron job ever invoked
-- it — stores stayed stuck at whatever is_open they were created/set with
-- (e.g. a store created open kept showing "Open Now" hours after its posted
-- close time).
--
-- Mirrors the guarded pg_cron pattern used by the GCash expiry sweeps:
-- pure SQL (no net.http_post / edge-function dependency), idempotent, and
-- degrades to a NOTICE when pg_cron is unavailable instead of failing.
--
-- Timezone: Asia/Manila (UTC+8). open_time/close_time are local wall-clock.
-- Overnight schedules: close_time < open_time means the window spans midnight.

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
     AND to_regclass('cron.job') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'apply-store-schedules') THEN
    PERFORM cron.schedule(
      'apply-store-schedules',
      '*/5 * * * *',
      $cron$
        -- 1) Schedule-driven stores (no manual override): apply the schedule directly.
        UPDATE public.stores s
        SET is_open = calc.should_be_open
        FROM (
          SELECT id,
                 CASE
                   WHEN open_time <= close_time
                     THEN (now() AT TIME ZONE 'Asia/Manila')::time >= open_time
                      AND (now() AT TIME ZONE 'Asia/Manila')::time < close_time
                   ELSE (now() AT TIME ZONE 'Asia/Manila')::time >= open_time
                     OR  (now() AT TIME ZONE 'Asia/Manila')::time < close_time
                 END AS should_be_open
          FROM public.stores
          WHERE auto_schedule_enabled = true
            AND open_time IS NOT NULL
            AND close_time IS NOT NULL
        ) calc
        WHERE s.id = calc.id
          AND s.manual_override = false;

        -- 2) Overridden stores: once the schedule agrees with the manual
        --    state, the override is moot — clear it and resume auto control.
        UPDATE public.stores s
        SET is_open = calc.should_be_open,
            manual_override = false
        FROM (
          SELECT id,
                 CASE
                   WHEN open_time <= close_time
                     THEN (now() AT TIME ZONE 'Asia/Manila')::time >= open_time
                      AND (now() AT TIME ZONE 'Asia/Manila')::time < close_time
                   ELSE (now() AT TIME ZONE 'Asia/Manila')::time >= open_time
                     OR  (now() AT TIME ZONE 'Asia/Manila')::time < close_time
                 END AS should_be_open
          FROM public.stores
          WHERE auto_schedule_enabled = true
            AND open_time IS NOT NULL
            AND close_time IS NOT NULL
        ) calc
        WHERE s.id = calc.id
          AND s.manual_override = true
          AND s.is_open = calc.should_be_open;
      $cron$
    );
    RAISE NOTICE 'Scheduled pg_cron job: apply-store-schedules (every 5 min)';
  ELSE
    RAISE NOTICE 'pg_cron unavailable or apply-store-schedules job already exists — store schedules not maintained automatically.';
  END IF;
EXCEPTION
  WHEN undefined_table OR insufficient_privilege OR undefined_function THEN
    RAISE NOTICE 'pg_cron unavailable — apply-store-schedules NOT scheduled. Fallback: external cron or manual invocation of the edge function.';
END
$$;
