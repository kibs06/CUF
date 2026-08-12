# Share Product Architecture

> **Purpose:** How "share a product" works in the app — a **text + URL share** from the customer product detail screen whose URL points at a **server-rendered Open Graph endpoint** (`product-preview` Supabase Edge Function), so WhatsApp / Messenger / Facebook render a Shopee/Lazada-style rich preview card. A **deep-link handler** (Phase B, domain-gated) can open the app directly to the product.
> **Last updated:** August 11, 2026

## 1. Overview

Sharing is **outbound-first**: the customer taps a share icon on `ProductDetailScreen`, the app composes a promo line **plus the product's public URL**, and hands both to the native share sheet. The URL is the magic ingredient — the **receiving app** fetches it and renders a preview card from the page's Open Graph (`og:*`) / Twitter Card meta tags.

```
ProductDetailScreen (customer)
  SliverAppBar actions → Share icon button
        │  onPressed → _shareProduct()
        ▼
  Compose text: "Check out {name} — only ₱{effectivePrice} at {storeName}!\n{shareUrl}"
        │
        ▼
  SharePlus.instance.share(ShareParams(text, subject))   // share_plus ^13.3.0
        │
        ▼
  Receiving app (WhatsApp/Messenger/Facebook/SMS…)
        │  fetches {shareUrl} anonymously
        ▼
  product-preview Edge Function (supabase/functions/product-preview/index.ts)
        │  queries products + stores + product_images (service role)
        │  computes sale-aware effective price (ported from sale_price.dart)
        ▼
  Server-rendered HTML with og:title / og:description / og:image / og:url
        ▼
  Rich preview card in chat (or plain text+URL fallback in SMS)
```

**Key facts:**

- **Dependency:** `share_plus: ^13.3.0` (`pubspec.yaml`). Used in **exactly one place** — `lib/screens/customer/product_detail_screen.dart`. No `XFile` is attached; the URL triggers the preview, not an image.
- **Share URL:** `AppConstants.productShareUrl(productId)` →
  `https://psczvbfoybqhjeqssimw.supabase.co/functions/v1/product-preview/{productId}`.
- **Price is sale-aware in BOTH places:** `_shareProduct` uses `effectivePrice()` from `lib/utils/sale_price.dart`, and the edge function **ports the same rule** (see §5). They must never drift.
- **Phase B (tap-to-open-app) is app-side-ready but domain-gated.** `DeepLinkService` + `DeepLinkHost` already parse product links and navigate to `ProductDetailScreen`, but Android App Links / iOS Universal Links cannot activate until the team owns a custom domain (`*.supabase.co` can't host the `.well-known` verification files). Config templates live in `web/.well-known/` and the manifests/entitlements.
- **Deep-link service now handles two link families:** GCash return links (`solvision://checkout/gcash/*`) **and** product links (`/p/{id}` or the edge-function URL). The GCash flow is untouched.

## 2. File Map

| Layer | File | Role |
|-------|------|------|
| Screen | `lib/screens/customer/product_detail_screen.dart` | Share button + `_shareProduct()` (~:479) — builds text + URL, calls SharePlus |
| Constants | `lib/constants/app_constants.dart` | `productShareBaseUrl` + `productShareUrl(productId)` |
| Edge fn | `supabase/functions/product-preview/index.ts` | Server-renders OG HTML per product; also serves `og-placeholder.png` fallback |
| Util | `lib/utils/sale_price.dart` | `isOnSale`/`effectivePrice` — client-side sale truth (**must mirror §5 port**) |
| Service | `lib/services/supabase_service.dart` | `fetchProductById()` (:165) — single-product fetch in customer shape for deep links |
| Service | `lib/services/deep_link_service.dart` | `productIdFromLink(Uri)` / `isProductLink(Uri)` matchers (additive to GCash) |
| Host | `lib/main.dart` | `DeepLinkHost._onLink` → `_openSharedProduct()` pushes `ProductDetailScreen` |
| Android | `android/app/src/main/AndroidManifest.xml` | GCash intent-filter (active); App Links intent-filter (**commented out**, domain-gated) |
| iOS | `ios/Runner/Runner.entitlements` | Associated Domains template (**not yet wired into Xcode**, domain-gated) |
| Static | `web/.well-known/assetlinks.json`, `web/.well-known/apple-app-site-association`, `web/README.md` | Platform verification files (placeholder fingerprints/team ID) |

## 3. Data Flow

### 3.1 `_shareProduct()` (product_detail_screen.dart)

```dart
final name      = widget.product['name']      ?? 'CUFMAI Footwear';
final price     = effectivePrice(widget.product);              // sale-aware
final priceStr  = '₱${price.toStringAsFixed(2)}';
final storeName = widget.product['store_name'] ?? 'CUFMAI';
final shareUrl  = AppConstants.productShareUrl(widget.product['id'].toString());

final text = 'Check out $name — only $priceStr at $storeName!\n$shareUrl';

await SharePlus.instance.share(ShareParams(text: text, subject: name));
// failures are caught + debug-printed only ('[Share] Failed to share product: $e')
```

- No `XFile`, no `sharePositionOrigin` — text-only. SMS/clipboard targets fall back to the plain text + URL (reads fine).
- The `subject` is the product name (email/SMS targets).

### 3.2 The OG endpoint (`product-preview/index.ts`)

- Route: `GET /functions/v1/product-preview/{productId}`; also `GET /functions/v1/product-preview/og-placeholder.png` (branded 1200×630 PNG, base64-embedded — no storage setup).
- Queries with the **service role** (bypasses RLS): `products(id, name, description, price, sale_price, sale_starts_at, sale_ends_at, is_active, stores(name, logo_url), product_images(image_url, display_order))`.
- Renders meta tags: `og:title` = product name, `og:description` = `₱{effectivePrice} at {storeName}`, `og:image` = first image (by `display_order`) → store `logo_url` → embedded placeholder, `og:url` = the same share URL, `og:type=product`, `twitter:card=summary_large_image`.
- HTML-escapes all dynamic strings (names can contain emoji/special chars); `og:image` is always absolute HTTPS.
- **Missing/inactive product** → HTTP 404 with a clean "Product no longer available" page (never a 500, never broken OG tags).
- Headers: `Cache-Control: public, max-age=3600`.

### 3.3 Inbound deep link (Phase B, app-side active today)

```dart
// deep_link_service.dart — matches both URL shapes:
//   https://…supabase.co/functions/v1/product-preview/{id}   (current)
//   https://<domain>/p/{id}                                   (future custom domain)
static String? productIdFromLink(Uri uri) { … }   // validates id loosely
static bool isProductLink(Uri uri) => productIdFromLink(uri) != null;
```

`DeepLinkHost._onLink` (main.dart): product links (before the GCash check) wait briefly for the Supabase session restore, then `SupabaseService.fetchProductById(id)` and push `ProductDetailScreen(product: …)`. A missing product or fetch failure shows a SnackBar — never a crash.

## 4. Boundaries / What is NOT implemented

1. **No custom domain.** Share links live on `*.supabase.co`. The card renders, but links look less branded and **tap-to-open-app cannot activate** (see §6).
2. **No marketing/web storefront.** The OG page body is intentionally minimal — there's no web store, so "View in app" is the only CTA (it points back at the OG URL until a storefront exists).
3. **No store / collection / cart sharing.** Only the product detail screen shares.
4. **No analytics/tracking** on share taps.
5. **Preview caching is platform-controlled.** WhatsApp/Facebook cache OG data per-URL; after a price/image change the old card may persist until their caches expire. This is inherent to every link-preview system (Shopee/Lazada included) — do not try to "fix" it.
6. **Placeholder image is a solid brand-color block** (base64 PNG) — acceptable fallback, not a designed asset. Swap by replacing `PLACEHOLDER_PNG_B64` in the function.

## 5. Gotchas for AI Agents

1. **The shared price must be the EFFECTIVE (sale) price in BOTH layers.** `_shareProduct` uses `sale_price.dart`; the edge function **ports** that rule in `effectivePrice()` (`index.ts:60`). The rule: on sale only when `sale_price` is set, **strictly less than** `price`, `sale_starts_at` (if set) in the past, and `sale_ends_at` (if set) in the future. Keep the two implementations identical — this is the one real drift risk in the feature.
2. **`og:image` must be a public, unauthenticated, absolute HTTPS URL.** The `product-images` and `store-assets` buckets are public-read, so `getPublicUrl()` URLs already qualify. Never use signed URLs or relative paths here.
3. **`SharePlus.instance.share` is fire-and-forget** — no result handling; errors are swallowed with `debugPrint`. Add handling there if you add post-share behavior.
4. **The deep-link matcher is intentionally loose** (any `https` host whose path is `/p/{id}` or the function shape). The DB fetch is the real authority. Do not tighten it to a specific host — the host will change when a custom domain lands.
5. **Deploying the function:** `supabase functions deploy product-preview`. The function reads `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` (auto-injected on the hosted platform). Until it's deployed, shared links 404 and show no preview.
6. **`web/.well-known/*` files contain placeholders** (`REPLACE_WITH_SIGNING_CERT_SHA256`, `TEAMID`) — they must be filled with real values when the domain is set up, and the Android intent-filter is **commented out** until then.
7. **Do not regress the GCash flow** — `solvision://checkout/gcash/*` handling in `DeepLinkService`/`DeepLinkHost`/`gcash_payment_screen.dart` is untouched; product-link handling is purely additive.

## 6. Roadmap (what's left for full Shopee/Lazada parity)

| Step | Requirement | Status |
|------|-------------|--------|
| OG card on shared links | Edge function deployed | ✅ built — **needs `supabase functions deploy product-preview`** |
| Tap-to-open-app (Android) | Custom domain + `assetlinks.json` w/ real SHA-256 + intent-filter + reinstall | ⏳ templates ready, domain-gated |
| Tap-to-open-app (iOS) | Custom domain + `apple-app-site-association` w/ Team ID + Associated Domains in Xcode + TestFlight | ⏳ templates ready, domain-gated |
| Branded share links | Point `AppConstants.productShareBaseUrl` at `https://<domain>/p` | ⏳ one-line change when domain lands |

## Related Docs

- `docs/AI/SHARE_PRODUCT_ARCHITECTURE.md` (this file, previous text-only revision)
- `docs/AI/CHECKOUT_AND_GCASH_ARCHITECTURE.md` — the GCash deep-link flow that shares `DeepLinkService`
- `docs/AI/DELIVERY_FEE_AND_MAP_ARCHITECTURE.md` — example of the docs/AI house style
