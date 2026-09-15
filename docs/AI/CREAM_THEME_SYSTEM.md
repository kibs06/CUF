# Cream Theme System — Surface Tokens, Usage Rules & the Guard Test

**Date:** September 15, 2026
**Scope:** The warm-cream surface language every screen shares — which token paints which surface, when to reach for each, and the automated guard that stops it drifting back to plain white.
**Audience:** Anyone adding or restyling a screen, card, sheet, chip or bar in `lib/`.
**Related:** `lib/constants/seller_theme_constants.dart` (the palette itself) · `lib/constants/app_constants.dart` (the shared aliases) · `test/utils/theme_surfaces_test.dart` (the guard) · `test/widgets/sole_bottom_nav_test.dart`, `test/widgets/color_thumbnail_swatch_test.dart` (adjacent guards) · **`docs/AI/DARK_MODE_AUDIT.md`** (what this system would need to become brightness-aware — read it before introducing a second palette).

---

## 1. The rule

**Every opaque surface in the app draws from one cream palette. Never hardcode a white, grey, or cream hex in a widget.**

The customer side, the seller side and the admin side share the same three tones. `AppConstants` does not duplicate them — it *points at* the `SellerTheme` values, so editing one constant re-themes the entire app:

```dart
// lib/constants/app_constants.dart
static const Color surfaceLight = SellerTheme.creamBg;   // page / card cream
static const Color sellerCardBg = SellerTheme.card;      // lighter raised cream
static const Color creamDeep    = Color(0xFFF0DFBB);     // grounded band cream
```

---

## 2. The tokens

| Token | Hex | Where it is defined | What it is for |
|---|---|---|---|
| `AppConstants.surfaceLight` (= `SellerTheme.creamBg`) | `#F3E9D8` | `app_constants.dart` → aliases `seller_theme_constants.dart` | **The page.** Scaffolds, sheets, dialogs, page-level backgrounds, and the default `SoleCard` fill. Also used as *light-on-dark text* (see §3). |
| `AppConstants.sellerCardBg` (= `SellerTheme.card`) | `#FBF5E9` | same | **The raised tone.** A card/chip/option card/menu that must sit visibly *above* a `surfaceLight` page. One step lighter than the page. |
| `AppConstants.creamDeep` | `#F0DFBB` | `app_constants.dart` | **The grounded band.** The bottom navigation bar (its default), i.e. a surface that should read as its own band rather than blending into the page behind it. |
| `AppConstants.surfaceDark` | `#1A1208` | `app_constants.dart` | Dark surfaces: the AR overlay and any "midnight canvas" treatment. |
| `AppConstants.borderGray` | `#D2C7BC` | `app_constants.dart` | Warm hairline borders/dividers, and the always-on ring on light colour swatches (§7). |
| `SellerTheme.cardBorder` | `#E7D8BC` | `seller_theme_constants.dart` | Seller card hairline (seller cards use a border instead of elevation). |
| `SellerTheme.cardHeroEnd` | `#F6E9D2` | `seller_theme_constants.dart` | Hero-card gradient end. |
| `SellerTheme.creamText` | `#F3E9D8` | `seller_theme_constants.dart` | Ink text on espresso fills. Same value as the page cream, on purpose. |
| `SellerTheme.gcashBgStart` / `gcashBgEnd` / `gcashBorder` | `#F6E9D2` / `#F1DEB8` / `#E3CC9C` | `seller_theme_constants.dart` | The GCash card gradient + border only. |

The ladder, lightest → deepest:

```
cards / chips   sellerCardBg  #FBF5E9
pages / sheets  surfaceLight  #F3E9D8
nav band        creamDeep     #F0DFBB
```

---

## 3. When to use which

| UI element | Use | Notes |
|---|---|---|
| Screen background | *nothing* | The theme maps `colorScheme.surface` → `surfaceLight`, so a plain `Scaffold` already inherits the cream. Only set it explicitly when you were setting it before (then `AppConstants.surfaceLight`). |
| Content sheet / bottom sheet | `surfaceLight` | Same as the page it slides over. |
| Card, panel, list tile surface | `SoleCard()` with **no** `color` | `SoleCard`'s default is `surfaceLight`; passing `color: Colors.white` is exactly the regression the guard catches. |
| Raised chip / unselected option card / "+ Other" chip | `sellerCardBg` | Must stay distinguishable from both the page *and* cream cards — this is the lighter tone. |
| Popup / dropdown surface (`dropdownColor:`) | `sellerCardBg` | |
| Input field fill | `surfaceLight` | Settings-family fields; seller-specific fields use the seller tokens. |
| Section band inside a settings-style page | `sellerCardBg` | |
| Bottom navigation bar | `AppConstants.creamDeep` | This is `SoleBottomNav`'s default; pass `backgroundColor:` only to override deliberately (the seller shell passes `SellerTheme.card`). |
| Dark header, AR overlay, photo scrim | `surfaceDark` or **translucent** white (`Colors.white.withValues(alpha: …)`) | Translucent whites are overlays, not fills — the guard skips them. |
| Foreground — icon/text/border on a dark, coloured or photographic background | `Colors.white` | Correct and deliberately untouched by the sweep. ~239 such lines remain in `lib/`. |
| Light-on-dark label (e.g. text on the primary button) | `AppConstants.surfaceLight` / `SellerTheme.creamText` | The theme already maps `onPrimary` / `onSecondary` / `onError` → `surfaceLight`. |

---

## 4. Two non-obvious rules

**The nav bar's badge ring must use the bar's own background.** The unread-count badge draws a cut-out ring so it reads as punched out of the bar. It used to look up `Theme.of(context).scaffoldBackgroundColor` (the *page* cream), which left a lighter halo once the bar moved to `creamDeep`. `SoleBottomNav` now threads its resolved background into `_NotificationBadgeIcon(barBackground: …)`. If you change the bar's background, the badge follows automatically — do not reintroduce a page-colour lookup.

**The seller shell overrides the nav background on purpose.** `SoleBottomNav(backgroundColor: …)` is honoured ahead of the default, because the seller dashboard's band is `SellerTheme.card`. That is asserted in `test/widgets/sole_bottom_nav_test.dart`.

---

## 5. The guard test

`test/utils/theme_surfaces_test.dart` — one test, `no hardcoded white or cold off-white surface fills in lib/`. Run it with:

```bash
flutter test test/utils/theme_surfaces_test.dart   # or the full `flutter test`
```

**What it scans.** Every `lib/**/*.dart` file, for a `color:` argument that is a *direct* hardcoded value, and only when the enclosing call paints a surface:

| Dimension | Values |
|---|---|
| Surface calls | `Container`, `BoxDecoration`, `DecoratedBox`, `SoleCard`, `Card`, `Material`, `ColoredBox` |
| Banned fills | `Colors.white` (not translucent), `Colors.grey.shade50` / `shade100` / `shade200`, and the legacy hexes `#FFF5F5F5`, `#FFF5F0EB`, `#FFF0F0F0`, `#FFF7F5F2`, `#FFFAF6F1` |

Those five hexes are the *old* cool greys the sweep removed: the settings-family page grey and section band (`#F5F5F5`, `#F0F0F0`), the previous `surfaceLight` (`#F5F0EB`), the size-chip fill (`#F7F5F2`) and the popup-menu fill (`#FAF6F1`). Re-introducing any of them fails the test.

**What it deliberately ignores.**

- **Translucent whites** — `Colors.white.withValues(alpha: …)`, `Colors.white24`. These are overlays on photos and dark surfaces.
- **Foreground colours** — a `color:` that is a text/icon colour on a non-surface call, or any `Colors.white` outside the calls above.
- **Non-`color:` parameters** — `fillColor:`, `iconTheme:`, `activeColor:` etc. are never matched.

**The one allowed exception.** `_allowedFills` in the test holds `'child: Container(color: Colors.white),'` — the shimmer's base canvas in `product_detail_screen.dart`, which is used purely as an alpha mask (the visible tone comes from the Seller shimmer palette). If you genuinely need a pure white fill, add its trimmed line to `_allowedFills` **with a comment explaining why**, exactly as that entry does. The failure message tells you all of this, and the three tokens to use instead.

---

## 6. Known blind spots — check these by hand

The guard matches a *direct* `color: <banned value>`. It cannot see:

1. **Ternary fills** — `color: isSelected ? AppConstants.accent : Colors.white,`
2. **Other widget parameters** — `fillColor: Colors.white`
3. **A banned value behind a constant or helper**

A hand-audit of every remaining `: Colors.white` in a ternary, September 15, 2026 — it is a complete list:

| Location | What | Verdict |
|---|---|---|
| `lib/screens/customer/foot_size_v2/foot_scan_setup_screen_v2.dart:359` | An unselected foot-width chip still fills `Colors.white` on a `surfaceLight` page | **Genuine leftover** — should be `sellerCardBg`. The same class of bug the sweep fixed elsewhere; the ternary hides it from the guard. |
| `lib/screens/customer/cart_screen.dart:607` and `lib/widgets/auth/terms_policy_tile.dart:122` | The two checkbox controls fill white when unchecked | **Intentional.** An empty checkbox is a *control*, not a surface — creaming it makes it vanish against the page. |
| `lib/screens/seller/add_edit_product_screen.dart:2312` | `if (n.contains('white')) return const Color(0xFFF5F5F5);` in the colour-name → hex map | **Intentional.** It is the displayed colour of a *swatch named "white"*, not a surface fill (and it is not a `color:` argument, so the guard never looks at it). |
| `lib/widgets/seller/seller_inventory_row.dart:386` | `enabled ? Colors.white : Colors.white60` | **Foreground** — an icon/text colour, not a surface. |
| `lib/screens/customer/ar_fitting_screen.dart:425` | `Colors.white24` border ring on the AR camera overlay | **Translucent**, so §5's ignore rule applies; not a fill at all. |

When you touch a ternary fill, apply the §3 table by hand — the guard will not remind you.

---

## 7. Also guarded (adjacent tests)

- **`test/widgets/sole_bottom_nav_test.dart`** — the bar paints `creamDeep` and is *not* the page cream; an explicit `backgroundColor` still overrides the default (protects the seller shell); the unread badge's ring matches the bar rather than the page.
- **`test/widgets/color_thumbnail_swatch_test.dart`** — a light colour swatch (`white`, `cream`, `beige`, …) must draw an always-on hairline ring (`AppConstants.borderGray` at ~0.5 alpha, 1 px) in a container that **wraps** the `ClipOval` so it cannot be clipped, keep the 40×40 thumbnail footprint, and still show the primary selection ring when selected. Without that ring a white swatch is invisible on a cream card — the customer-side companion of the same "light on light" problem.

---

## 8. Why it looks like this (short history)

- `surfaceLight` was `#F5F0EB` ("off-white suede"), documented as the app's light surface but visually indistinguishable from plain white on the customer home — the catalog read as white while the seller dashboard sat on cream.
- The fix was to **repoint the shared token** at `SellerTheme.creamBg` rather than override one screen: that one constant paints the home scaffold, the content sheet, the bottom nav default, the shells, and most customer/auth/admin screens, so a per-screen override would have left a visible seam against the shared nav bar.
- `creamDeep` was added afterwards, when the nav band turned out to need a distinct grounded tone instead of inheriting the page cream.
- A follow-up sweep then removed the hand-written near-white fills across **100 files** in `lib/` — 47 `SoleCard(color: Colors.white)` overrides, the whole cool-grey "settings family" (page `#F5F5F5`, bands `#F0F0F0`), leftover off-token hexes, and unselected `: Colors.white` chips/option cards (moved to `sellerCardBg`). 144 files now reference the tokens.
- `test/utils/theme_surfaces_test.dart` exists because this is a regression that returns silently: white reads as "normal" when you write a card by hand, and nothing else in the suite would notice.

**Docs that predate the sweep still quote `#F5F0EB` as `surfaceLight`** — for
example `docs/debug/*`, `docs/SESSION_LOG_*`, `docs/project_doc.md` and the
chapter deliverables. Those are point-in-time snapshots and were left alone on
purpose. The live references — `docs/AI_DEVELOPMENT_GUIDE.md`,
`docs/AI_PROJECT_SUMMARY.md`, `docs/CUSTOMER_ARCHITECTURE.md`,
`docs/AI/AR_TRY_ON_ARCHITECTURE.md`,
`docs/AI/SELLER_APPLICATION_UI_ARCHITECTURE.md` — were updated to `#F3E9D8` on
September 15, 2026. If you find the old hex in a doc that is *not* a snapshot,
fix it; the app has not used it since the sweep.

---

## 9. Checklist for new UI

- [ ] Did not write a white, grey or cream hex — used `surfaceLight`, `sellerCardBg` or `creamDeep`.
- [ ] Page/sheet = `surfaceLight` (usually just inherited); raised card/chip = `sellerCardBg`; nav band = `creamDeep`.
- [ ] Left `SoleCard`'s `color` unset, or passed a *raised* token deliberately.
- [ ] White is only used as foreground (icon/text/border on dark, coloured or photographic surfaces) or as a translucent overlay.
- [ ] If I changed the nav bar's background, the badge ring still resolves from the bar itself.
- [ ] Ran `flutter test test/utils/theme_surfaces_test.dart` — and, if I wrote a ternary fill, checked it by hand (§6).
