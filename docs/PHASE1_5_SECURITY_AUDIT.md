# SoleVision — Phase 1.5: Security & Safety Audit

**Date:** July 20, 2026  
**Status:** IN PROGRESS  

---

## 1. Database Backup Verification

### Finding
⚠️ **MANUAL ACTION REQUIRED** — Cannot verify backup status from code alone.

**What to check in Supabase Dashboard:**
1. Go to **Settings → Database → Backups**
2. Verify "Daily Backups" is enabled (available on Pro plan and above)
3. If on Free tier, daily backups are NOT automatic — you must create manual backups

**If backups are NOT enabled, create one now:**
```bash
# Using Supabase CLI (if installed):
supabase db dump --db-url postgresql://postgres:[PASSWORD]@db.psczvbfoybqhjeqssimw.supabase.co:5432/postgres > backup_$(date +%Y%m%d).sql

# Or via Supabase Dashboard:
# Settings → Database → Backups → Create backup
```

**Restore procedure (documented for emergency):**
1. In Supabase Dashboard → Settings → Database → Backups
2. Select the backup to restore
3. Click "Restore" — this overwrites the current database
4. Alternative: `psql postgresql://... < backup_20260720.sql`

**PASS/FAIL:** ⏳ PENDING MANUAL VERIFICATION

---

## 2. RLS Policy Audit

### Complete Table-by-Table Audit

| Table | RLS Enabled | Policies | Assessment |
|-------|-------------|----------|------------|
| `profiles` | ✅ | SELECT: public, INSERT: self, UPDATE: self+admin | ✅ PASS — but see note below |
| `stores` | ✅ | SELECT: public, INSERT/UPDATE: owner, ALL: admin | ✅ PASS |
| `story_entries` | ✅ | SELECT: public, ALL: store owner+admin | ✅ PASS |
| `store_follows` | ✅ | SELECT/INSERT/DELETE: self only | ✅ PASS |
| `products` | ✅ | SELECT: public, INSERT/UPDATE/DELETE: seller+admin | ⚠️ SEE NOTE |
| `product_images` | ✅ | SELECT: public, ALL: seller+admin | ⚠️ SEE NOTE |
| `product_variants` | ✅ | SELECT: public, ALL: seller+admin | ⚠️ SEE NOTE |
| `product_customizations` | ✅ | SELECT: public, ALL: seller+admin | ⚠️ SEE NOTE |
| `inventory` | ✅ | SELECT: public, ALL: seller+admin | ⚠️ SEE NOTE |
| `orders` | ✅ | SELECT: customer+seller+admin, INSERT: customer, UPDATE: seller+admin, DELETE: customer(pending) | ✅ PASS |
| `order_items` | ✅ | SELECT: via order owner, INSERT: order owner | ✅ PASS |
| `sales_transactions` | ✅ | SELECT/INSERT: store owner, SELECT: admin | ✅ PASS |
| `sales_transaction_items` | ✅ | SELECT: via transaction owner | ✅ PASS |
| `cart_items` | ✅ | SELECT/INSERT/UPDATE/DELETE: self only | ✅ PASS |
| `customization_requests` | ✅ | SELECT/INSERT: customer, SELECT: store owner, UPDATE: seller+admin | ✅ PASS |

### Critical Issues Found

#### Issue A: `products` RLS — Seller Can Modify ANY Seller's Products
**SEVERITY: HIGH**

The current policies in `schema.sql`:
```sql
CREATE POLICY "Sellers and Admins can insert products"
    ON public.products FOR INSERT WITH CHECK (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND (role = 'seller' OR role = 'admin'))
    );
```

**Problem:** Any seller can insert/update/delete products in ANY store — not just their own. The migration `20260712_tighten_products_rls.sql` tightened this by checking `store_id` ownership, but the `schema.sql` file still shows the old permissive policy.

**Status:** The migration file `20260712_tighten_products_rls.sql` SHOULD have fixed this. **Must verify on live DB.**

**Verification query (run on live DB):**
```sql
-- Check if the tightened policies are applied
SELECT policyname, cmd, qual, with_check 
FROM pg_policies 
WHERE tablename = 'products' 
ORDER BY cmd;
```

#### Issue B: `profiles` RLS — Public SELECT Exposes All Data
**SEVERITY: MEDIUM**

```sql
CREATE POLICY "Public profiles are viewable by everyone"
    ON public.profiles FOR SELECT USING (true);
```

This allows ANY user (including unauthenticated/anon) to read ALL profiles, including email addresses. While this is needed for display purposes, the email column should ideally be restricted.

**Recommendation:** Consider restricting email visibility:
```sql
-- Future: Create a view that excludes sensitive columns
CREATE VIEW public_profiles AS
SELECT id, full_name, avatar_url, role, seller_status, created_at
FROM profiles;
```

### RLS Test Queries

Run these against the live database to verify each scenario:

```sql
-- ═══════════════════════════════════════════════════════════════
-- SCENARIO 1: Customer cannot read another Customer's orders
-- ═══════════════════════════════════════════════════════════════
-- As customer A, try to read customer B's orders
SET ROLE authenticated;
SET request.jwt.claims = '{"sub":"CUSTOMER_A_UUID","role":"authenticated"}';

SELECT * FROM orders WHERE customer_id = 'CUSTOMER_B_UUID';
-- Expected: 0 rows (RLS blocks access)

-- ═══════════════════════════════════════════════════════════════
-- SCENARIO 2: Seller cannot read another Seller's products
-- ═══════════════════════════════════════════════════════════════
SET ROLE authenticated;
SET request.jwt.claims = '{"sub":"SELLER_A_UUID","role":"authenticated"}';

-- Try to update another seller's product
UPDATE products SET name = 'HACKED' WHERE id = 'SELLER_B_PRODUCT_ID';
-- Expected: 0 rows affected (RLS blocks)

-- ═══════════════════════════════════════════════════════════════
-- SCENARIO 3: Anonymous cannot read orders
-- ═══════════════════════════════════════════════════════════════
SET ROLE anon;
RESET request.jwt.claims;

SELECT * FROM orders;
-- Expected: 0 rows (RLS blocks anon access)

-- ═══════════════════════════════════════════════════════════════
-- SCENARIO 4: Admin can read all profiles
-- ═══════════════════════════════════════════════════════════════
SET ROLE authenticated;
SET request.jwt.claims = '{"sub":"ADMIN_UUID","role":"authenticated"}';

SELECT count(*) FROM profiles;
-- Expected: all profiles returned

-- ═══════════════════════════════════════════════════════════════
-- SCENARIO 5: Customer cannot update another Customer's addresses
-- ═══════════════════════════════════════════════════════════════
SET ROLE authenticated;
SET request.jwt.claims = '{"sub":"CUSTOMER_A_UUID","role":"authenticated"}';

UPDATE customer_addresses SET label = 'HACKED' WHERE user_id = 'CUSTOMER_B_UUID';
-- Expected: 0 rows affected

-- ═══════════════════════════════════════════════════════════════
-- SCENARIO 6: Customer cannot read another Customer's messages
-- ═══════════════════════════════════════════════════════════════
SET ROLE authenticated;
SET request.jwt.claims = '{"sub":"CUSTOMER_A_UUID","role":"authenticated"}';

SELECT * FROM messages WHERE conversation_id IN (
    SELECT id FROM conversations WHERE customer_id = 'CUSTOMER_B_UUID'
);
-- Expected: 0 rows

-- ═══════════════════════════════════════════════════════════════
-- CLEANUP: Reset role after testing
-- ═══════════════════════════════════════════════════════════════
RESET ROLE;
RESET request.jwt.claims;
```

**PASS/FAIL:** ⏳ PENDING MANUAL EXECUTION OF TEST QUERIES

---

## 3. Edge Function Security Review

### `send-message-push/index.ts`

| Check | Status | Notes |
|-------|--------|-------|
| Caller auth validation | ⚠️ **MISSING** | No JWT verification — anyone with the URL can invoke |
| Input validation | ⚠️ **PARTIAL** | Validates `sender_type` but not `conversation_id` format |
| Service role key exposure | ✅ Safe | Key stored as Supabase secret, never exposed to client |
| Rate limiting | ⚠️ **MISSING** | No rate limit — could be abused for spam |
| Payload size limit | ⚠️ **MISSING** | No explicit size check |

### `send-notification-push/index.ts`

| Check | Status | Notes |
|-------|--------|-------|
| Caller auth validation | ⚠️ **MISSING** | No JWT verification |
| Input validation | ✅ Good | Checks required fields (`recipientUserId`, `title`, `body`, `type`) |
| Service role key exposure | ✅ Safe | Key stored as Supabase secret |
| Rate limiting | ⚠️ **MISSING** | No rate limit |
| Payload size limit | ⚠️ **MISSING** | No explicit size check |

### `shared/push.ts`

| Check | Status | Notes |
|-------|--------|-------|
| Service role key | ✅ Safe | Reads from `SUPABASE_SERVICE_ROLE_KEY` env |
| FCM credentials | ✅ Safe | Reads from `FCM_SERVICE_ACCOUNT_KEY` and `FIREBASE_PROJECT_ID` env |
| Token cleanup | ✅ Good | Removes invalid FCM tokens |
| Error handling | ✅ Good | Catches and logs errors |

### Recommended Fixes

**Add JWT verification to both Edge Functions:**
```typescript
// Add at the top of each edge function's serve handler:
const authHeader = req.headers.get("Authorization");
if (!authHeader || !authHeader.startsWith("Bearer ")) {
  return new Response(
    JSON.stringify({ error: "Missing or invalid authorization" }),
    { status: 401, headers: corsHeaders }
  );
}

// Verify the JWT (Supabase provides this via the auth header)
const token = authHeader.replace("Bearer ", "");
const { data: { user }, error: authError } = await supabase.auth.getUser(token);
if (authError || !user) {
  return new Response(
    JSON.stringify({ error: "Unauthorized" }),
    { status: 401, headers: corsHeaders }
  );
}
```

**Add payload size limit:**
```typescript
const contentLength = Number(req.headers.get("content-length") || 0);
if (contentLength > 10240) { // 10KB max
  return new Response(
    JSON.stringify({ error: "Payload too large" }),
    { status: 413, headers: corsHeaders }
  );
}
```

**PASS/FAIL:** ⚠️ FAIL — Missing auth validation, rate limiting

---

## 4. Sentry Integration (Task 4)

### Recommendation
Integrate Sentry for error monitoring. This is a code change that requires:

**Flutter App (Customer + Seller):**
```yaml
# Add to pubspec.yaml:
dependencies:
  sentry_flutter: ^8.0.0
```

```dart
// In main.dart, before runApp():
await SentryFlutter.init(
  (options) {
    options.dsn = 'YOUR_SENTRY_DSN';
    options.environment = kDebugMode ? 'development' : 'production';
    options.tracesSampleRate = 1.0;
  },
  appRunner: () => runApp(const SoleVisionApp()),
);
```

**Admin Portal (React):**
```bash
npm install @sentry/react
```

```javascript
// In main.jsx:
import * as Sentry from "@sentry/react";

Sentry.init({
  dsn: "YOUR_SENTRY_DSN",
  environment: import.meta.env.DEV ? "development" : "production",
  integrations: [Sentry.browserTracingIntegration()],
  tracesSampleRate: 1.0,
});
```

**PASS/FAIL:** ⏳ PENDING — Requires Sentry account + DSN

---

## 5. Staging Environment (Task 5)

### Lightweight Setup Plan

1. **Create a second Supabase project** (can be on Free tier for staging)
2. **Use `--dart-define` to switch environments:**

```json
// dart_defines.json (development/staging)
{
  "SUPABASE_URL": "https://staging-project.supabase.co",
  "SUPABASE_ANON_KEY": "staging-anon-key",
  "SENTRY_DSN": "staging-sentry-dsn",
  "ENVIRONMENT": "staging"
}

// dart_defines.json (production)
{
  "SUPABASE_URL": "https://psczvbfoybqhjeqssimw.supabase.co",
  "SUPABASE_ANON_KEY": "production-anon-key",
  "SENTRY_DSN": "production-sentry-dsn",
  "ENVIRONMENT": "production"
}
```

3. **Apply all migrations to staging:**
```bash
supabase db push --project-ref staging-project-ref
```

**PASS/FAIL:** ⏳ PENDING — Requires second Supabase project

---

## 6. Git History Credential Exposure

### Finding
🔴 **CONFIRMED: Hardcoded credentials exist in git history.**

The following credentials were committed in `lib/constants/app_constants.dart`:
- **Supabase URL:** `https://psczvbfoybqhjeqssimw.supabase.co`
- **Anon Key:** `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...`

### Immediate Mitigation
**ROTATE THE ANON KEY NOW:**
1. Go to Supabase Dashboard → Settings → API
2. Click "Regenerate" next to the anon key
3. Update `dart_defines.json` with the new key
4. Deploy the updated app to all users

The anon key is designed to be public (it's in the client bundle), so rotation doesn't break anything — just update the key everywhere it's used.

### Full History Cleanup (Optional)
To remove credentials from git history:
```bash
# Using BFG Repo Cleaner (recommended):
bfg --replace-text credentials.txt
git reflog expire --expire=now --all && git gc --prune=now --aggressive

# Or using git filter-repo:
pip install git-filter-repo
git filter-repo --path lib/constants/app_constants.dart --invert-paths
```

⚠️ **WARNING:** History rewriting requires force-pushing and coordination with all collaborators.

**PASS/FAIL:** 🔴 FAIL — Credentials exposed, key rotation recommended

---

## 7. Phase 1 Fix Verification

### Re-run Phase 1 Verification Queries

```sql
-- Check for non-numeric sizes
SELECT COUNT(*) AS non_numeric_count
FROM product_variants
WHERE size !~ '^[0-9]+(\.[0-9]+)?$';

-- Check for duplicate product_variants
SELECT product_id, size, color, COUNT(*) as cnt
FROM product_variants
GROUP BY product_id, size, color
HAVING COUNT(*) > 1;

-- Check for orphaned inventory
SELECT COUNT(*) AS orphaned_count
FROM inventory i
LEFT JOIN products p ON p.id = i.product_id
WHERE p.id IS NULL;

-- Check schema drift: compare schema.sql tables vs live
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
ORDER BY table_name;
```

**PASS/FAIL:** ⏳ PENDING MANUAL EXECUTION

---

## Summary Checklist

- [ ] ⏳ Verified/created a working database backup + documented restore steps
- [ ] ⏳ RLS policies audited and tested per role (Seller / Customer / anon / Admin)
- [ ] ⚠️ Edge Functions reviewed — auth validation MISSING, needs fix
- [ ] ⏳ Sentry (or equivalent) integrated across Flutter apps + admin portal
- [ ] ⏳ Minimal staging environment stood up and documented
- [ ] 🔴 Git history checked — credentials EXPOSED, key rotation recommended
- [ ] ⏳ Phase 1 fixes (migrations, dedup, orphaned rows, schema sync) re-verified
