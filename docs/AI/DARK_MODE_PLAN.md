# Dark Mode Plan — Brightness-Aware Tokens, System/Light/Dark, Whole App

**Date:** September 17, 2026
**Status:** **Phases 1–2 and the Settings control are IMPLEMENTED** (September 17, 2026 — see §9 for what shipped and the deviations from this plan). A chrome-ink pass and a page-token-ink pass landed September 22, 2026 (§11). Phase 0 is open, Phase 3 is partly done, Phase 5 is partly done.
**Scope:** A real dark theme for every role (customer, seller, POS, admin, auth), selected from Settings as System / Light / Dark.
**Supersedes:** the counts in `docs/AI/DARK_MODE_AUDIT.md` (measured Sept 15, before the neutral sweep landed). Its **analysis** still stands; its **numbers and hexes** are stale — see §2.
**Related:** `docs/AI/NEUTRAL_THEME_PLAN.md` (executed — the white/gray ladder now live) · `docs/AI/CREAM_THEME_SYSTEM.md` (the rules it replaced) · `lib/constants/app_constants.dart`, `lib/constants/seller_theme_constants.dart` · `lib/main.dart` · `test/utils/theme_surfaces_test.dart`

---

## 1. Approved decisions

| # | Question | Decision |
|---|---|---|
| 1 | How does colour reach widgets? | **Brightness-aware tokens.** Keep every token name; resolve its value per brightness through one app-owned brightness. Zero call-site churn. |
| 2 | What is the user-facing control? | **System / Light / Dark** row in `lib/screens/shared/settings_screen.dart`, default **System**. |
| 3 | How much does the first dark version cover? | **Whole app, all roles**, in one pass. |
| 4 | Phase 0 bug fixes? | Folded in — they are bugs in today's light-only app. |
| 5 | Light-mode fidelity | **Hard constraint: light mode must stay pixel-identical.** It is the safety property that makes this change reviewable. |

---

## 2. Measured state (working tree, September 17, 2026)

Counts are references, not files, measured over `lib/**/*.dart` (300 files).

| Symbol / pattern | Refs | Why it matters |
|---|---|---|
| `bodyStyle` / `headlineStyle` / `monoStyle` | 2,065 | `static`, take **no `BuildContext`**, default `color: secondary`. The theme cannot reach them. |
| `AppConstants.secondary` (`#111111` ink) | 1,061 | On a dark page, near-black text is invisible. Note the audit called this espresso `#3B2314` — the neutral sweep changed it. |
| `AppConstants.surfaceLight` (`#FFFFFF` page) | 516 | Means **two things**: page fill *and* light ink on dark fills. |
| `AppConstants.borderGray` (`#E5E5E5`) | 358 | Hairlines vanish on dark. |
| `withValues(alpha: 0.3–0.7)` | 957 | The "muted text" idiom. Fading ink toward a *dark* page is not the same as fading it toward a light one. |
| `Colors.black` | 220 | 70 fills (scrims/lightboxes), 150 foregrounds. |
| `BoxShadow(` | 82 | Incl. `warmShadow` — a warm tint on black is nothing. |
| `const` line + palette token | **137** | The entire compile-break surface of §3. |
| `Theme.of(context)` | **6** | The app is theme-blind; it paints from tokens. |
| `scaffoldBackgroundColor` / `MaterialApp(` | 1 / 2 | Scaffolds already inherit `colorScheme.surface`; the fallback error app is the second app. |
| `AppConstants.surfaceDark` (`#111111`) | 9 | Used by the already-dark screens — **pinned**, never brightness-resolved (§4.3). |
| `static const Color` in the two palette files | 43 | The whole palette. |

**Inference:** the surface layer is tokenised enough that a single flip repaints the app — *provided* the tokens stop being `const` and start being roles, and *provided* the ink tokens flip with the pages. That is the whole plan.

---

## 3. The mechanism

### 3.1 One brightness, owned by the theme

```dart
// lib/constants/app_brightness.dart
/// The brightness the token getters resolve against. Written ONLY by
/// CUFMAIApp when the theme mode or the OS brightness changes; reset by the
/// test config. Widgets never read this — they read AppConstants.*, unchanged.
class AppBrightness {
  static Brightness _current = Brightness.light;
  static Brightness get current => _current;
  static bool get isDark => _current == Brightness.dark;
  static void set(Brightness value) => _current = value;
  static void reset() => _current = Brightness.light; // tests
}
```

### 3.2 Tokens become getters over light/dark role values

```dart
// lib/constants/app_constants.dart
static Color get surfaceLight => AppPalette.of(Brightness).page;   // page role
static Color get surfaceSubtle => AppPalette.of(Brightness).subtle;
static Color get borderGray   => AppPalette.of(Brightness).hairline;
static Color get secondary    => AppPalette.of(Brightness).onPage; // ink role
```

`AppPalette` holds the two role sets with the hexes written exactly once (light values = today's, so light mode cannot drift). The 43 palette constants move behind it; the names stay.

### 3.3 Text defaults resolve per brightness

`bodyStyle` keeps its signature (2,065 call sites untouched) — its default becomes `color: color ?? AppConstants.secondary`, which already resolves per brightness. The 1,422 sites that pass an explicit colour mostly pass tokens, so they follow for free.

### 3.4 Forcing a repaint on toggle (the subtle one)

Because the app reads *static* tokens rather than `Theme.of(context)`, changing `themeMode` does **not** rebuild widgets that don't depend on `Theme` — most of the app. So:

```dart
// lib/main.dart
final mode = context.watch<ThemeProvider>().mode;                 // user choice
final os = MediaQuery.platformBrightnessOf(context);              // live OS flip
final dark = mode == ThemeMode.dark ||
             (mode == ThemeMode.system && os == Brightness.dark);
AppBrightness.set(dark ? Brightness.dark : Brightness.light);
return MaterialApp(key: ValueKey(dark), theme: light, darkTheme: dark_,
                   themeMode: mode, ...);
```

The `ValueKey(dark)` rebuilds the whole tree on a brightness change — the intended behaviour, and it happens only on toggle or an OS flip. This is the honest cost of decision 1 (the audit's "hidden global state" trade-off); §7 pins it with tests.

### 3.5 Persistence and the Settings row

Mirror the existing `SaleTagProvider` / `SaleTagService` shape: a `ThemeService` (SharedPreferences key, e.g. `app_theme_mode`) plus a `ThemeProvider` (`ChangeNotifier`, `mode`, `load()`, `setMode()`), registered in `main.dart`'s `MultiProvider`. The Settings row is a drop-in: `_settingsRow(...)` already takes `subtitle` + `trailing`, and an "Appearance" section above "Legal" reaches every role (both entry points — `customer_shell.dart:151` and `shared/profile_screen.dart:349` — land on this one screen). Show the resolved state in the subtitle ("Dark", "System · Dark").

---

## 4. What the token flip does NOT fix by itself

These are the three places the mechanical change gets it wrong, and each needs a role decision rather than a `sed`.

### 4.1 Alpha encodes a lightness assumption — hairlines are the worst case

`borderGray.withValues(alpha: 0.5)` (×69 in the audit, plus solid uses) works on white because a *light* token faded toward white stays visible. On dark it does not: a dark hairline at 50% over a dark page is nothing. The 358 `borderGray` refs therefore split into two roles with different dark values — `hairline` (solid uses) and `hairlineSoft` (already-faded uses) — and the same split applies to `secondary.withValues(...)` muted text (a `muted` role) where the fade lands below AA. **This is the main Phase 3 workload and the main reason dark mode is not a one-day change.**

### 4.2 `surfaceLight` as ink — the 98-site collision

`surfaceLight` is used both as the page fill and as light ink on clay/black/teal fills. Once the token means *page*, those foreground uses paint a dark page colour onto a dark fill. The replacement token already exists (`AppConstants.inkInverse`, aliasing `SellerTheme.creamText`) — the work is finding them. Findable mechanically: `surfaceLight` inside a `color:` for text/icon on a dark-accent surface, plus `bodyStyle(color: AppConstants.surfaceLight)`.

### 4.3 Screens that are dark on purpose must be pinned

The AR, foot-scan, both scanners, the auth video entry and the three photo lightboxes are deliberately dark in *both* modes. They keep literal `surfaceDark` / `Colors.black`, which stay `const` and are explicitly exempt from the sweep. Document this in the palette so a future "cleanup" doesn't repaint them.

---

## 5. Proposed dark palette (values to verify, not final)

Every role must clear **AA 4.5:1** for body text and **3:1** for large text/icons against its own background; each value below is a candidate to be checked, not a claim.

| Role | Light (today) | Dark (candidate) | Note |
|---|---|---|---|
| Page | `#FFFFFF` | `#111111` | Matches the existing `surfaceDark` "midnight canvas" tone. |
| Raised (card/popup) | `#FFFFFF` | `#1C1C1C` | **Lighter** than the page — on dark, elevation reads as raised, not shadowed. |
| Band (nav) | `#F5F5F5` | `#171717` | Plus a top hairline. |
| Subtle (input/chip) | `#F5F5F5` | `#1F1F1F` | |
| Hairline / hairlineSoft | `#E5E5E5` / faded | `#2E2E2E` / white @ ~10% | The two roles from §4.1. |
| On page (ink) | `#111111` | `#F5F5F5` | Drives all 2,065 text defaults. |
| Muted | ink @ 0.5–0.7 | `#A3A3A3` (solid) | Replaces the alpha idiom where it lands under AA. |
| Ink on clay/black/teal | `#FFFFFF` | unchanged | `inkInverse` — pinned. |
| Primary clay | `#8B5A2B` | fill unchanged; **lifted variant for text/icons** | Clay on `#111` is roughly 3:1 — fine for large marks, short of AA for body text. Needs a lifted accent role. |
| Accent teal | `#4ECDC4` | unchanged or slightly deepened | Already high contrast on dark. |
| Shadow | `warmShadow` | **collapse to ~none** | Dark depth comes from the raised tone + hairline; the product cards just standardized on exactly that. |
| Status pills | pastel bg + dark fg | colour @ ~18% bg + lifted fg | Keep the semantic hue; copy the seller palette's `{bg, fg}` pair shape. |
| Charts (16 sites) | literal grid/axis/tooltip | role colours | The most commonly shipped-broken dark surface. |

**Product photography:** do **not** tint or scrim the product images. A white-studio shoe photo is the product's appearance — the same principle that keeps the colour-name → hex map out of theming. The chrome around it (page, raised, hairline) goes dark so the photo reads as a bright plate; if glare is a real problem, the tool is a hairline/rounded inset, not an overlay on the product.

**Explicitly not themed:** GCash card gradient (partner branding), the seller status/stock colours' semantics (only their surfaces adapt), the product colour-name map, and `surfaceDark` on the pinned screens.

---

## 6. Phases

| Phase | Status | Work | Exit criteria |
|---|---|---|---|
| **0** — real bugs, half a day | ⬜ open | `SystemUiOverlayStyle`/`AnnotatedRegion` for the always-dark screens; Android `values-night` launch theme + dark `launch_background` (today both values folders point at white, so *light* users flash white too) | AR/scanner status-bar icons are legible; no white launch flash on a dark-mode device |
| **1** — palette as roles | ✅ done | `AppPalette` light + dark role sets; split `surfaceLight`'s two meanings via `inkInverse`; status pairs; chart roles; contrast check each pair | Light mode byte-identical; every role documented with a contrast ratio |
| **2** — plumbing | ✅ done | `AppBrightness`, token getters, helper defaults, `ThemeService` + `ThemeProvider` in `MultiProvider`, `darkTheme` + `themeMode`, remove both hardcoded `Brightness.light`s | Toggling repaints the whole app; choice survives a restart; `system` follows a live OS flip |
| **3** — the sweep | ◐ partial (chrome + notifications feed done, §11) | `hairline`/`hairlineSoft` splits (358), `muted` role for the worst of the 957 fades, shadow collapse, dark status pills, chart re-key, pinned-screen audit | Every screen checked in both modes at device size; no unreadable text or invisible divider |
| **4** — Settings | ✅ done | "Appearance" section, System/Light/Dark, subtitle showing resolved state | Reachable for all roles; applies live; persisted |
| **5** — guards | ◐ partial (an ink-token-fill guard landed, §11) | Dual-brightness `theme_surfaces_test`, `test/flutter_test_config.dart` reset, theme tests (§7), optional dark goldens for the main shells | The guard fails if a brightness-blind literal is reintroduced |

---

## 7. Tests and guards

- **Isolation.** There is no `test/flutter_test_config.dart` today. Add one that calls `AppBrightness.reset()` before each test, so the 93 existing files keep asserting light values unchanged.
- **New tests.** Token resolution per brightness (every role has a dark value, no role returns light in dark); `AppBrightness` agrees with the resolved `ThemeMode`/OS brightness; `ThemeService` round-trips the mode and defaults to `system`; the Settings row applies and displays the choice; a widget rebuilt under `Brightness.dark` receives dark tokens without a manual rebuild.
- **Extend the guard.** `theme_surfaces_test.dart` bans literal white/grey *fills* — it is brightness-blind and would pass a completely broken dark theme. Make it assert role tokens in both modes.
- **Regression list to run after every phase.** `flutter analyze lib test`, then `flutter test` (93 files). The card hairline test from the current work session is a useful canary: it asserts the border equals a *token*, so it keeps passing only if resolution stays consistent.
- **Optional but recommended:** a small golden set (customer home, product detail, settings, POS) — every dark defect here is invisible contrast, which unit tests do not catch.

---

## 8. Risks

| Risk | Mitigation |
|---|---|
| **Invisible breakage** — low contrast, not crashes. Nothing throws. | Phase 5 goldens + the dual-brightness guard, before the sweep spreads. |
| Light mode regresses during the token conversion | Decision 5 (pixel-identical) + `theme_surfaces_test` + the 221 widget tests. |
| The 137 `const` breaks cascade | Compiler-guided and safe: each is a mechanical `const` removal the analyzer names. |
| Global brightness drifts from the actual theme | One writer (`CUFMAIApp`), one reset hook, pinned by a test. |
| Charts and status pills ship broken | Phase 3 owns them explicitly rather than inheriting. |
| The always-dark screens get "fixed" by a later sweep | §4.3 pinned-token convention, documented in the palette. |

## 9. What shipped (September 17, 2026)

### New files

| File | Role |
|---|---|
| `lib/constants/app_palette.dart` | The role palette: light + dark values for `page`, `raised`, `subtle`, `band`, `hairline`, `hairlineSoft`, `hairlineOnRaised`, `onPage`, `muted`, `mutedStrong`, `inkInverse`, `primaryInk`, `accentSoft`, `scrim`, `shadow` |
| `lib/constants/app_brightness.dart` | The published brightness. `publish()` reports whether a repaint is needed; `reset()` exists for tests |
| `lib/constants/app_theme.dart` | `buildAppTheme(Brightness)` (the Material layer, moved out of `main.dart`) and `AppThemeRefresh.rebuildAll()` |
| `lib/services/theme_service.dart` | `app_theme_mode` in SharedPreferences; unknown values fall back to `system` |
| `lib/providers/theme_provider.dart` | The user's choice, applied optimistically and persisted in the background |

### Changed

- `app_constants.dart` / `seller_theme_constants.dart`: surfaces, ink, hairlines, the two shimmer tones and both shadow recipes are brightness-aware; brand, status, `surfaceDark` and `inkInverse` are pinned `const`. The three text helpers take `Color?` and resolve `color ?? secondary`.
- `main.dart`: `CUFMAIApp` became stateful, owns the `ThemeProvider`, observes the platform brightness, publishes the resolved brightness, and supplies `theme` + `darkTheme` + `themeMode`. The persisted mode is read *before* `runApp`, so there is no light flash at launch.
- `settings_screen.dart`: an **Appearance** section whose row shows the resolved state ("System · Light (device)") and opens a System / Light / Dark sheet.
- **163 `const` expressions** dropped `const` across ~85 files — unavoidable once tokens became getters. 25 more sites needed real decisions (nullable parameter defaults resolved in `build`, four `const` declarations that became `final`, the two tag-group ink roles).

### Deviations from the plan, and why

1. **The `ValueKey` rebuild is gone — it would have reset the navigator.** §3.4 proposed keying the app on the resolved brightness. That replaces the root element and therefore throws away the route stack: toggling in Settings would have bounced the user back to Splash. `AppThemeRefresh.rebuildAll()` marks every element dirty instead, which repaints everything and disposes nothing. Verified by `test/widgets/dark_mode_repaint_test.dart`, which asserts a route pushed *before* the toggle repaints and keeps its `State` identity.
2. **Dark `hairline` is a mid grey (`#555555`), not a subtle near-page tone.** The 358 hairline call sites still consume the token both solid *and* faded at 0.3–0.7 alpha, so a value tuned for the solid case alone would leave every faded hairline invisible on dark. Phase 3 splits the two uses, after which this can drop.
3. **"Light ink on a fill" had to be pinned, not flipped.** `surfaceLight`-as-ink and the camel/olive tag chips' `onColor` now use `inkInverse` / the new pinned `AppConstants.inkOnLightAccent`; both are visually identical to the light values they replaced, so light mode did not move. The chip colour-name/data map is untouched, as planned.
4. **The four `_NotificationBadgeIcon` / `SoleBadge` / `SolePrimaryButton` / `SellerMetricCard` colour defaults became nullable** rather than resolving in a const constructor (which cannot read a runtime value). Their public *fields* are nullable now; nothing outside the widgets reads them, and existing call sites are unaffected.

### Verified

`flutter analyze lib test` clean; **1,034 tests pass**, including the pre-existing suite unchanged (light mode is asserted against the original hexes by `test/utils/dark_mode_test.dart`).

### Still open (Phase 3 and friends)

The 957 alpha-encoded "muted" fades and the 358 hairline fades resolve acceptably on dark but are not yet roles; status pills keep their light pastel fills; the 16 fl_chart colour sites are still literal; product photography is untouched (deliberately); the always-dark AR/camera screens are pinned but still have no `SystemUiOverlayStyle`; and `theme_surfaces_test.dart` is still brightness-blind.

---

## 10. Definition of done

`themeMode` flips the whole app from Settings; light stays pixel-identical; no screen contains a brightness-blind literal fill, hairline or ink; text, muted, hairline, tint, status and chart roles all resolve per brightness; the always-dark screens stay dark in both modes; the launch screen and status bar match in both; and the guard plus golden set fail if any of that regresses.

---

## 11. The chrome pass (September 22, 2026)

**Reported:** "this didn't pass dark mode — the text are not visible" (customer → Notifications).

**Root cause.** `AppConstants.secondary` is the *page ink* (`#111111` light, `#F5F5F5` dark), but **37 sites used it as a fill** for dark chrome whose ink is pinned light — `AppBar(backgroundColor: AppConstants.secondary)` on the seller shell and every seller/shared detail screen, both notification swipe actions, the search submit button, the auth CTA, the error toast, the order-ID SnackBar. On dark those fills resolved to near-white with white or cream labels on them, so the text was not low-contrast, it was *gone*. The notification feed had the same shape in a second notation: its read cards were `Colors.white` under page ink, and its unread wash was a 4% clay fade over a card that is near-black on dark.

**What shipped**

| Change | Where |
|---|---|
| `AppPalette.chrome` — the dark bar/control fill. Light `#111111` (byte-identical to the espresso it replaces), dark `#262626`: dark enough for the pinned white ink (≈15:1) yet still a band above the `#111111` page (1.25:1) | `app_palette.dart`, `AppConstants.chrome` |
| `AppPalette.unreadTint` (clay 4% light / 34% dark — the wash lands on the page, so the dark value has to be strong enough to separate an unread row from the `#1C1C1C` a read one paints) and `AppConstants.surfaceRaised` (the raised card under its customer-side name) | same |
| 35 fill sites moved onto `chrome`; 1 SnackBar that pinned white content text moved with them | the sweep |
| Notification cards: `Colors.white` → `surfaceRaised`, `primary.withValues(alpha: 0.04)` → `unreadTint`, swipe `View`/`Chat` → `chrome` | `notifications_screen.dart`, `seller_notification_center_screen.dart` |
| New guard: no opaque `AppConstants.secondary` fill in a `Container` / `BoxDecoration` / `SoleCard` / `AppBar` / `SlidableAction` / filled button. Exceptions opt out in place with a `theme-guard:` comment (the RECOMMENDED badge, whose label flips with it, and the timeline's active-dot core, which has no ink on it) | `test/utils/theme_surfaces_test.dart` |
| `dark_mode_test`: chrome keeps its tone in both modes, white ink clears AA on it, the dark unread wash is distinguishable (≥1.2:1) from the card it sits on and light's stays the whisper it was | `test/utils/dark_mode_test.dart` |

**Second report, same session:** "the login where the links are not seen". `AppConstants.surfaceLight` is the *page* tone, and the pinned-dark screens were using it as **ink** — white on light, `#111111` on dark. So on the auth hero (dark in both modes) "Apply to sell", "Sign in" and "Forgot password?" turned near-black, and the same notation sat on the camera overlays, the store hero, the clay CTAs and the success checkmarks.

| Change | Where |
|---|---|
| 33 ink sites moved onto `inkInverse` — the pinned light role. It is the same white on light, so this is a light-mode no-op | `account_entry_screen` (the reported links, the CUFMAI wordmark, the Forgot-password link, the biometric Enable label), `dark_auth_text_field`'s floating label, `onboarding_screen`'s CTA, `dev_mode_badge`, `signup_scaffold`'s light-content eyebrow, the AR / foot-capture / foot-processing overlays and their outlined buttons, `store_hero_card`, the store header's foreground plus its stat icons, outline button and follow pill/chips, the two `Icons.check` marks, the toast's dismiss, the timeline's check |
| New guard: no text/icon colour drawn in `AppConstants.surfaceLight` (ink calls only — `Icon`, `IconThemeData`, `TextStyle`, the three text helpers, `CircularProgressIndicator`). The one deliberate exception opts out in place: the RECOMMENDED pill flips its fill *and* its ink together | `test/utils/theme_surfaces_test.dart` |
| `_enclosingCall` reports the last dot segment, so a qualified helper (`AppConstants.bodyStyle`) is matched by the name the call sets use | same |

**Third report, same session:** "do we have light and dark mode on the seller side?" — the theme was already global (the seller module resolves the same `AppConstants` / `SellerTheme` tokens, which is why every §11 fix shows up there too), but a seller had **no way to choose it**: the seller profile's top-right settings icon was wired `onPressed: null`, and `SettingsScreen` carried customer-only rows, so it was never opened for that role. Phase 4's exit criterion — "reachable for all roles" — was therefore unmet.

| Change | Where |
|---|---|
| The settings icon on the seller profile is live and opens Settings. Path: seller → Profile → top-right settings → **Appearance → Theme** (System / Light / Dark), the same three-way sheet the customer side uses | `seller_shell.dart` (the shell's own app bar), `profile_screen.dart` (its own app-bar branch, kept in step) |
| `SettingsScreen` gates its customer-only rows (`Size Your Foot`, `My Addresses`) on `roleCustomer`, so the seller — and an admin — get Account & Security, Appearance, Legal and Support without rows that lead into empty customer screens | `settings_screen.dart` |
| Tests: a seller sees Appearance and *not* the customer rows; a customer still gets both | `test/widgets/appearance_setting_test.dart` |

**Verified.** `flutter analyze` clean; **1,596 tests pass**, including the full suite unchanged. Light mode is a no-op at every swept site: `chrome`'s light value is exactly the light `secondary`, `unreadTint`'s is clay at 4% (the alpha the rows already painted) and `inkInverse` is white.

**Still open in this phase.** The 957 alpha-encoded muted fades and the 358 hairline fades; status pills keep their light pastel fills; the 16 fl_chart colour sites are still literal; the seller notification rows still use a 4% blue fade for unread (they carry a bold title as a second cue, which is why they were left); charts and the always-dark AR/camera screens still have no `SystemUiOverlayStyle`. **The next class is `surfaceLight` used as a *fill or border* on a pinned-dark surface** — the hero pills, outlines and sheets that intend plain white in both modes — which both guards are blind to by design, because on a normal screen that token is a correct page fill. It needs a screen pass over the pinned-dark heroes rather than a literal ban.
