# Neutral Theme Migration Plan — Cream → White / Gray / Black

**Date:** September 16, 2026
**Status:** **PLAN ONLY — nothing implemented yet.** Awaiting approval of this document before any code changes.
**Scope:** Replace the app-wide warm-cream surface language with a neutral white/gray/black one, keeping the brand clay and teal as accents.
**Supersedes once executed:** `docs/AI/CREAM_THEME_SYSTEM.md` (its rules describe the palette this plan removes).
**Audience:** Anyone who will execute or review this migration.

---

## 1. Approved decisions

| # | Question | Decision |
|---|---|---|
| 1 | How far does the neutral sweep go? | **White/gray surfaces, keep clay (`#8B5A2B`) + teal (`#4ECDC4`) accents.** Status colors stay semantic. |
| 2 | Which surfaces flip? | **Whole app in one pass** — customer, seller, admin, auth, shared. |
| 3 | How do cards stay visible on white? | **White cards with hairline borders.** No gray card fill by default. |

---

## 2. Why this is mostly a repointing job

The palette is centralized, so the visual change is decided by a handful of constants, not by 155 files of hand-picked colors:

```dart
// lib/constants/app_constants.dart — the shared aliases
static const Color surfaceLight = SellerTheme.creamBg;  // page  #F3E9D8
static const Color sellerCardBg = SellerTheme.card;     // raised #FBF5E9
static const Color creamDeep    = Color(0xFFF0DFBB);    // nav band
static const Color borderGray   = Color(0xFFD2C7BC);    // warm hairline
static const Color secondary    = Color(0xFF3B2314);    // espresso body text
```

`lib/main.dart` maps `colorScheme.surface → AppConstants.surfaceLight`, and **no screen sets `ThemeData.scaffoldBackgroundColor`** (0 occurrences in `lib/`). A plain `Scaffold` therefore already inherits the page tone — repointing one constant repaints every page that doesn't explicitly override it.

**Blast radius (measured, September 16, 2026):**

| Symbol | References in `lib/` |
|---|---|
| `surfaceLight` | 521 |
| `secondary` (body text / espresso) | 1053 |
| `primary` (clay accent — kept) | 922 |
| `borderGray` | 354 |
| `accent` (teal — kept) | 236 |
| `sellerCardBg` | 57 |
| `sellerSurface` | 23 |
| `creamDeep` | 13 |
| `SellerTheme.creamBg` / `.card` / `.creamText` | 5 / 22 / 4 |
| **Files referencing any cream token** | **155 of 297** |
| Files with hardcoded warm hexes | **13** (46 lines) |

Only 13 files carry hardcoded warm hexes — that is the entire hand-audit surface (§6). Everything else moves by token.

---

## 3. The core visual problem: the ladder has to invert

Today the cream ladder gets **lighter as it rises**:

```
cards / chips   sellerCardBg  #FBF5E9   ← lightest
pages / sheets  surfaceLight  #F3E9D8
nav band        creamDeep     #F0DFBB   ← deepest
```

On a pure-white page there is nothing lighter than the page, so the ladder must **invert**: the page is the lightest surface and anything that sits *on* it is either bordered (cards, decision 3) or filled with a **subtle gray** (chips, inputs, bands).

```
pages / sheets  surfaceLight  #FFFFFF   ← lightest (new page tone)
cards / raised  #FFFFFF + 1px #E5E5E5 hairline
subtle fills    #F5F5F5        (chips, inputs, section bands)
nav band        #F5F5F5 + top hairline #E5E5E5
```

This inversion is the whole migration. It is also the part most likely to need a visual second pass, because a white card with a `#E5E5E5` hairline on a white page is a **1.2:1** boundary — legible on a good screen, weak on a cheap one outdoors. If it reads too flat, the fallback is the rejected decision-3 option (a `#F7F7F8` card fill); that is a one-line change to the card token, so it is worth trying the clean version first.

---

## 4. Target token table

### Surfaces

| Role | Token | Today | Target |
|---|---|---|---|
| Page / scaffold / sheet / dialog | `surfaceLight` (= `SellerTheme.creamBg`) | `#F3E9D8` | `#FFFFFF` |
| Raised card / chip / popup | `sellerCardBg` (= `SellerTheme.card`) | `#FBF5E9` | `#FFFFFF` |
| Subtle fill (input, unselected chip, section band) | *new* `surfaceSubtle` | — | `#F5F5F5` |
| Grounded band (nav bar) | `creamDeep` | `#F0DFBB` | `#F5F5F5` |
| Hero card gradient end | `SellerTheme.cardHeroEnd` | `#F6E9D2` | `#F5F5F5` |
| Dark surfaces (AR overlay, "midnight canvas") | `surfaceDark` | `#1A1208` | `#111111` |

### Lines

| Role | Token | Today | Target |
|---|---|---|---|
| Hairline border / divider | `borderGray` | `#D2C7BC` | `#E5E5E5` |
| Seller card hairline | `SellerTheme.cardBorder` | `#E7D8BC` | `#E8E8E8` |

### Text

| Role | Token | Today | Target |
|---|---|---|---|
| Body / headline | `secondary` | `#3B2314` espresso | `#111111` near-black |
| Secondary body | `SellerTheme.textSecondary` | `#6B5645` | `#4A4A4A` |
| Muted / caption / eyebrow | `SellerTheme.textMuted` | `#8B7355` | `#6B6B6B` |
| Ink on clay / espresso / black fills | `SellerTheme.creamText` + `AppConstants.surfaceLight`-as-foreground | `#F3E9D8` | `#FFFFFF` (**new `inkInverse` token**, §5) |

### Kept deliberately

- `primary` clay `#8B5A2B` — CTAs, icons, brand.
- `accent` teal `#4ECDC4` — AR mode and highlights.
- Status colors and their tinted backgrounds (`statusPendingColor`, `sage*`, `amber*`, `blue*`, `lowStockColor`, `okStockColor`).
- The **GCash card gradient** (`gcashBgStart` / `gcashBgEnd` / `gcashBorder`) — that gold treatment is GCash branding, not app chrome.
- The product colour-name → hex map in `add_edit_product_screen.dart` (line ~2312), including `'cream'` / `'beige'` → `#F1E8DC`. Those describe a **product's actual colour**; they are data, not theme. Changing them would misreport products.

### Recommended shimmer inversion

`lib/widgets/shimmer_group.dart` defaults to `baseColor: creamDeep` with the sweep brightening to the card cream, and its comment states the old greys "read as cold grey slabs against the cream page". The rationale now runs the other way: on a white page the neutral tones are the correct ones and warm tones would read as dingy. Invert the pair — base `#EDEDED`, highlight `#F5F5F5` — and rewrite that comment rather than leaving a stale justification in the file.

---

## 5. The overloaded-token problem (the main correctness risk)

`AppConstants.surfaceLight` currently does **two jobs**:

1. **Page fill** — scaffolds, sheets, dialogs, `SoleCard`'s default (`sole_card.dart:36`).
2. **Light-on-dark foreground** — `main.dart` `onPrimary` / `onSecondary` / `onError`, `SoleBadge.textColor`, `SolePrimaryButton.textColor`, `tag_selector.onColor`, plus `SellerTheme.creamText` in the seller widgets.

Those two jobs only coincided because the page cream and the ink cream were the same value. Flipping `surfaceLight` to pure white silently repaints every foreground site too.

**Contrast is not the problem** — it improves. White on clay `#8B5A2B` is ≈ 5.9:1 (cream was ≈ 4.9:1) and white on espresso `#3B2314` is ≈ 14:1 (cream was ≈ 11.7:1). Both already cleared AA; white clears it by more.

**The problem is intent.** A single token that means both "the page" and "text on a dark button" cannot be reasoned about after the flip. So:

- Add `AppConstants.inkInverse = #FFFFFF`.
- Classify all 521 `surfaceLight` references into **fill** vs **foreground** and repoint the foreground ones at `inkInverse` (and the seller `creamText` usages likewise).
- Only then change `surfaceLight`'s value.

This classification is the bulk of the work and the part a find-and-replace must not shortcut. Getting it wrong is silent: everything still compiles, and the only symptom is text that looks slightly off on dark surfaces.

**Blind spots that must be hand-checked (same categories the old guard could not see):** ternary fills (`color: isSelected ? X : surfaceLight`), non-`color:` parameters (`fillColor:`), and values hidden behind helpers. `docs/AI/CREAM_THEME_SYSTEM.md` §6 lists the known ones; that list is the starting checklist, with each verdict re-decided for the neutral palette (e.g. the unchecked-checkbox fill was "intentional white" under cream — under white it must become a **bordered** control instead, or it vanishes).

---

## 6. Hardcoded warm hexes — the hand-audit list

All 13 files carrying warm hexes. The two constant files are the source; the rest need individual judgement:

| File | What to decide |
|---|---|
| `lib/constants/seller_theme_constants.dart` | The source of truth — repalette per §4. |
| `lib/constants/app_constants.dart` | The shared aliases — repalette + add `surfaceSubtle` / `inkInverse`. |
| `lib/widgets/chat/chat_view.dart` | `#F5EDE4` incoming-bubble tone → neutral fill; bubbles must stay distinguishable from the white page. |
| `lib/screens/seller/add_edit_product_screen.dart` | Form card cream → white + border. **Leave the colour-name swatch map alone** (§4). |
| `lib/screens/shared/about_cufmai_screen.dart` | Local `_cream #F3E2C2` hero/illustration palette — decide keep-warm (brand illustration) vs neutral. |
| `lib/screens/customer/product_detail_screen.dart` | The shimmer base canvas exception + swatch handling. |
| `lib/screens/customer/my_reports_screen.dart` | Warm surface → token. |
| `lib/screens/shared/faq_screen.dart`, `help_menu_screen.dart`, `support_chat_screen.dart`, `whats_new_screen.dart` | **The "settings family"** — all four were swept to the same cream bands; they flip as one group. |
| `lib/widgets/lockout_overlay.dart`, `lib/widgets/update_overlay.dart` | Full-screen overlays; verify the scrim still reads over the new page tone. |

Also re-check the warm treatments that have no hardcoded hex but were **designed around** cream: `hanging_sale_tag.dart` (cream paper gradient + amber pulse), `sale_price_tape.dart` (frosted warm-cream fill), `signup_scaffold.dart` + `dark_auth_text_field.dart` (cream chrome over video), `app_error_toast.dart` (`#F3ECE1` / `#D9CBB8` on espresso — kept-warm by default since they sit on the dark toast), `sole_bottom_nav.dart` indicator + badge ring, and `seller_weekly_bar.dart` / `seller_revenue_columns_chart.dart` (cream-card-specific contrast notes).

---

## 7. Test changes

| Test | Today | Required change |
|---|---|---|
| `test/utils/theme_surfaces_test.dart` | **Bans** `Colors.white`, `grey.shade50/100/200` and five near-white hexes as surface fills — i.e. it enforces cream. | **Invert it.** Ban the warm hexes (`#F3E9D8`, `#FBF5E9`, `#F0DFBB`, `#F6E9D2`, `#E7D8BC`, `#D2C7BC`, `#F5EDE4`, `#F1DEB8`) as direct fills, and separately ban raw `Colors.grey.shade*` / raw gray `Color(0xFF…)` literals so every neutral comes from a token. Rewrite the header comment — it currently explains why white is forbidden. |
| `test/widgets/sole_bottom_nav_test.dart` | Asserts the bar paints `creamDeep` and is **not** `surfaceLight`; asserts the badge ring resolves from the bar. | Update to the new band token. Keep the two real invariants: bar ≠ page, explicit `backgroundColor` still overrides, badge ring follows the bar. |
| `test/widgets/color_thumbnail_swatch_test.dart` | Asserts a light swatch gets an always-on hairline ring, justified as "a white swatch is invisible on a cream card". | The mechanism survives, but the justification flips: on a **white** card a *white* swatch is still invisible, so the ring is more necessary than before. Widen the light-colour threshold if needed and rewrite the comment. |
| **New:** theme contract test | — | Assert `surfaceLight == Color(0xFFFFFFFF)`, that no `lib/` file references a removed cream token name, and that `colorScheme.surface` maps to the page token. This is what stops the palette drifting back. |

No test currently hardcodes a warm hex value — all guards reference tokens symbolically, which is why this is a smaller change than it looks.

---

## 8. Execution plan (5 commits)

Ordered so that each step is independently reviewable and revertible.

**Commit 1 — neutralise the values (values only, names unchanged).**
Repalette `seller_theme_constants.dart` + `app_constants.dart` per §4, add `surfaceSubtle` / `inkInverse`. Keep the `cream*` **names** for now. Touches ~4 files, so `git revert` restores the cream look exactly. This is the commit to react to visually.

**Commit 2 — classify fill vs foreground.**
Add `inkInverse`, repoint the light-on-dark call sites (§5), hand-audit the ternary/`fillColor` blind spots. No value changes.

**Commit 3 — sweep the 13 hardcoded files + the designed-around-cream widgets (§6).**
After this, no warm hex remains outside the kept-deliberately list.

**Commit 4 — tests (§7).**
Invert the guard, update the two adjacent guards, add the theme contract test. Land this *with* commits 1–3 as far as possible — an inverted guard that lands late cannot catch the sweep's mistakes.

**Commit 5 — rename tokens to neutral names.**
`creamBg` → `surfacePage`, `creamDeep` → `surfaceBand`, `SellerTheme.card` → `surfaceCard`, `creamText` → `inkInverse`, `cardBorder` → `borderHairline`. Mechanical, ~155 files, zero visual change — deliberately separated so the rename churn does not bury the visible diff in review.

**Docs land throughout:** rewrite `docs/AI/CREAM_THEME_SYSTEM.md` (or replace it with the file you are reading), and fix the live references in `docs/AI_DEVELOPMENT_GUIDE.md`, `docs/AI_PROJECT_SUMMARY.md`, `docs/CUSTOMER_ARCHITECTURE.md`, `docs/AI/AR_TRY_ON_ARCHITECTURE.md`, `docs/AI/SELLER_APPLICATION_UI_ARCHITECTURE.md`, `docs/AI/HOME_MASONRY_GRID_WIDGETS.md`, `docs/AI/STORE_SCREEN_SOURCE.md`, `docs/AI/GCASH_CANCEL_DIAGNOSTICS_AND_SCREEN_SOURCE.md`, `docs/AI/DARK_MODE_AUDIT.md`. Point-in-time snapshots (`docs/debug/*`, `docs/SESSION_LOG_*`, chapter deliverables) stay untouched — they are dated records, and `SoleVision_Project_Documentation2.md` already quotes a palette the app stopped using.

---

## 9. Verification

1. `flutter analyze` — clean.
2. `flutter test test/utils/theme_surfaces_test.dart test/widgets/sole_bottom_nav_test.dart test/widgets/color_thumbnail_swatch_test.dart`
3. Full `flutter test` (89 test files in the suite).
4. **Visual pass on a fixed screenshot list**, since no test can judge the look — customer home / product detail / cart / checkout / profile+settings / chat / notifications; seller dashboard / order card / add-edit product / inventory row; admin verification viewer; dark auth signup + video background; AR fitting overlay; sale tag + price tape; lockout and update overlays.
5. Contrast spot-check on the pairs that changed: white-on-clay (≈5.9:1 ✓), `#111111` on white and on `#F5F5F5` (✓), muted `#6B6B6B` on white (≈5.7:1 ✓), hairline `#E5E5E5` on white (1.2:1 — intentional, cards only).

**Rollback:** commit 1 alone reverts the entire look. Commits 2–5 are inert without it.

---

## 10. Open items to settle during execution

- **Does the white-card + hairline treatment read cleanly on a real device outdoors?** If not, switch the card token to `#F7F7F8` (decision 3's rejected option) — one line.
- **`about_cufmai_screen.dart`'s local warm hero palette** — brand illustration (keep warm) or neutral (consistent with the new language)?
- **`surfaceDark` `#1A1208` → `#111111`** is proposed for a true neutral black; confirm the AR overlay and dark auth screens still read as designed.
- **`AppConstants.noiseOverlay`** paints clay speckles at low opacity for texture. On white it will read as brown grain — decide neutralised or dropped.
- **Dark mode is still absent** (`main.dart` sets no `darkTheme`). If a dark theme is coming, `docs/AI/DARK_MODE_AUDIT.md` says the right move is brightness-aware tokens — worth building the neutral tokens with that shape now, so the second palette does not require a second migration.
