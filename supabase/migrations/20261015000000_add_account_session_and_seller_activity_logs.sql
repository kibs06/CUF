-- ══════════════════════════════════════════════════════════════════
-- Migration: Seller login/logout + activity logs
-- Date: 2026-10-15
--
-- Problem: the admin Audit Logs page answers "who approved what", but not
-- "when did this seller last sign in" or "what has this seller been doing".
-- Successful sign-ins touch no public table (GoTrue owns them, and
-- `auth.audit_log_entries` is not client-readable), and product/store/order
-- writes leave no who-when trail (`order_status_history` records the status
-- but not the actor).
--
-- FIX (two tables, two different write paths — deliberately):
--
--   1. `account_session_log` — one row per sign-in / sign-out, written BY
--      THE CLIENTS (customer portal, admin portal, app) best-effort after a
--      successful sign-in and before sign-out. A trigger cannot do this:
--      there is no public-table write at login for a trigger to fire on.
--      These rows are CLAIMS, not proof — a modified client could skip them.
--      Brute-force protection stays where it is (`failed_logins`, written
--      server-side). No backfill is possible: past sessions left no trace.
--
--   2. `seller_activity_log` — one row per seller-side product / store /
--      order-status write, written ONLY by database triggers (the same
--      unbypassable pattern as `seller_application_audit_log`). No client
--      can skip or rewrite these.
--
-- Access model:
--   • account_session_log — users INSERT their own rows and SELECT their own
--     history; admins SELECT all. No UPDATE/DELETE for anyone.
--   • seller_activity_log — admins SELECT; NOBODY writes (not even
--     service_role) — only the SECURITY DEFINER trigger functions.
-- ══════════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────────
-- 1. Session log (client-written)
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.account_session_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Who signed in/out. NULL + SET NULL (not CASCADE): a deleted account's
    -- session history must outlive its profile row, and the admin UI already
    -- renders unresolvable ids as "Unknown account".
    user_id         UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    -- sign_in | sign_out
    event           TEXT NOT NULL CHECK (event IN ('sign_in', 'sign_out')),
    -- The role the client saw on the profile at sign-in time
    -- (customer | seller | admin). A claim, used only for filtering.
    role            TEXT,
    -- Which client recorded it: customer-portal | admin-portal | app
    source          TEXT,
    user_agent      TEXT,
    created_at      TIMESTAMP WITH TIME ZONE
                        DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE public.account_session_log IS
    'Best-effort sign-in / sign-out history, written by the clients '
    '(sign-in is logged after success, sign-out before signOut). '
    'Claims, not proof — brute-force security still lives in failed_logins.';

CREATE INDEX IF NOT EXISTS account_session_log_user_idx
    ON public.account_session_log (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS account_session_log_role_idx
    ON public.account_session_log (role, created_at DESC);

ALTER TABLE public.account_session_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can log their own sessions"
    ON public.account_session_log;
CREATE POLICY "Users can log their own sessions"
    ON public.account_session_log FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can read their own sessions"
    ON public.account_session_log;
CREATE POLICY "Users can read their own sessions"
    ON public.account_session_log FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins can read all sessions"
    ON public.account_session_log;
CREATE POLICY "Admins can read all sessions"
    ON public.account_session_log FOR SELECT
    USING (public.is_admin());

-- No UPDATE/DELETE policy exists, and the grants below withhold those
-- verbs entirely: history is append-only.
REVOKE ALL ON public.account_session_log FROM PUBLIC;
GRANT SELECT, INSERT ON public.account_session_log TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- 2. Seller activity log (trigger-written, immutable)
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.seller_activity_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Who did it (auth.uid() at statement time). NULL for system writes
    -- (cron, service_role backfills) — never for client statements.
    actor_id        UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    -- store_created | store_updated |
    -- product_created | product_updated | product_removed |
    -- order_status_changed
    action          TEXT NOT NULL,
    -- product | store | order
    entity          TEXT NOT NULL,
    -- Polymorphic on purpose (one log, three tables) — hence no FK.
    entity_id       UUID,
    store_id        UUID REFERENCES public.stores(id) ON DELETE SET NULL,
    -- Human summary: the product/store name, or "placed → preparing".
    detail          TEXT,
    previous_status TEXT,
    new_status      TEXT,
    created_at      TIMESTAMP WITH TIME ZONE
                        DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE public.seller_activity_log IS
    'Immutable trail of seller-side product / store / order-status writes. '
    'Writeable ONLY by the log_seller_activity triggers — all direct '
    'INSERT/UPDATE/DELETE/TRUNCATE grants are revoked, including '
    'from service_role.';

CREATE INDEX IF NOT EXISTS seller_activity_log_actor_idx
    ON public.seller_activity_log (actor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS seller_activity_log_store_idx
    ON public.seller_activity_log (store_id, created_at DESC);
CREATE INDEX IF NOT EXISTS seller_activity_log_entity_idx
    ON public.seller_activity_log (entity, entity_id, created_at DESC);

ALTER TABLE public.seller_activity_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can read seller activity log"
    ON public.seller_activity_log;
CREATE POLICY "Admins can read seller activity log"
    ON public.seller_activity_log FOR SELECT
    USING (public.is_admin());

-- Belt-and-suspenders at the grant level (same pattern as
-- seller_application_audit_log): even service_role, which bypasses RLS,
-- must not write — only the owner-running triggers may.
REVOKE ALL ON public.seller_activity_log FROM PUBLIC;
GRANT SELECT ON public.seller_activity_log TO authenticated;

-- ────────────────────────────────────────────────────────────────
-- Trigger functions — the single write path to seller_activity_log
-- ────────────────────────────────────────────────────────────────
-- One function for all three tables (TG_TABLE_NAME / TG_OP decide the
-- action), SECURITY DEFINER so the INSERT runs as the table owner and is
-- not blocked by RLS / the revoked grants. search_path pinned.
CREATE OR REPLACE FUNCTION public.log_seller_activity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_action text;
    v_entity text;
    v_entity_id uuid;
    v_store_id uuid;
    v_detail text;
    v_prev text;
    v_new text;
BEGIN
    IF TG_TABLE_NAME = 'products' THEN
        v_entity := 'product';
        IF TG_OP = 'DELETE' THEN
            v_action := 'product_removed';
            v_entity_id := OLD.id;
            v_store_id := OLD.store_id;
            v_detail := OLD.name;
        ELSE
            v_action := CASE WHEN TG_OP = 'INSERT'
                THEN 'product_created' ELSE 'product_updated' END;
            v_entity_id := NEW.id;
            v_store_id := NEW.store_id;
            v_detail := NEW.name;
        END IF;
    ELSIF TG_TABLE_NAME = 'stores' THEN
        v_entity := 'store';
        v_action := CASE WHEN TG_OP = 'INSERT'
            THEN 'store_created' ELSE 'store_updated' END;
        v_entity_id := NEW.id;
        v_store_id := NEW.id;
        v_detail := NEW.name;
    ELSIF TG_TABLE_NAME = 'orders' THEN
        -- Fires only on status change (see the UPDATE OF status trigger).
        v_entity := 'order';
        v_action := 'order_status_changed';
        v_entity_id := NEW.id;
        v_store_id := NEW.store_id;
        v_prev := OLD.status;
        v_new := NEW.status;
        v_detail := OLD.status || ' → ' || NEW.status;
    ELSE
        RETURN COALESCE(NEW, OLD);
    END IF;

    INSERT INTO public.seller_activity_log (
        actor_id, action, entity, entity_id, store_id,
        detail, previous_status, new_status
    ) VALUES (
        auth.uid(), v_action, v_entity, v_entity_id, v_store_id,
        v_detail, v_prev, v_new
    );

    RETURN COALESCE(NEW, OLD);
END;
$$;

COMMENT ON FUNCTION public.log_seller_activity IS
    'Trigger writer for seller_activity_log (products INSERT/UPDATE/DELETE, '
    'stores INSERT/UPDATE, orders status change). SECURITY DEFINER so the '
    'insert bypasses RLS/grants — the triggers are the only write path.';

DROP TRIGGER IF EXISTS trg_log_product_activity ON public.products;
CREATE TRIGGER trg_log_product_activity
    AFTER INSERT OR UPDATE OR DELETE ON public.products
    FOR EACH ROW EXECUTE FUNCTION public.log_seller_activity();

DROP TRIGGER IF EXISTS trg_log_store_activity ON public.stores;
CREATE TRIGGER trg_log_store_activity
    AFTER INSERT OR UPDATE ON public.stores
    FOR EACH ROW EXECUTE FUNCTION public.log_seller_activity();

DROP TRIGGER IF EXISTS trg_log_order_activity ON public.orders;
CREATE TRIGGER trg_log_order_activity
    AFTER UPDATE OF status ON public.orders
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION public.log_seller_activity();
