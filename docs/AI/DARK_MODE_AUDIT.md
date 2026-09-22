# Dark Mode Audit — What Exists, Where Cream Breaks, What It Would Take

**Date:** September 15, 2026
**Scope:** Does the app support a dark theme today, which surfaces already have dark treatments, where the cream palette would fail on a dark background, and what a real dark theme would require.
**Method:** Every number below is measured from the working tree (`grep` + a call-site classifier over `lib/**/*.dart`), not estimated. Counts are *references*, not files.
**Related:** `docs/AI/CREAM_THEME_SYSTEM.md` (the light surface system this would have to extend) · `lib/constants/app_constants.dart`, `lib/constants/seller_theme_constants.dart` (the palette) · `test/utils/theme_surfaces_test.dart` (the surface guard) · `lib/main.dart` (the only `ThemeData`s).

---

## 1. Verdict

**There is no dark mode, and there is no plumbing for one.** `darkTheme:` does not exist, `ThemeMode` is never set, `MediaQuery.platformBrightness` / `Brightness.dark` appear **zero** times in `lib/`, and `Brightness.light` is hardcoded in **both** `ThemeData`s (`main.dart:164` and the fallback app at `main.dart:388`). A dark-mode device gets the cream app.

What *does* exist is **dark as a design device**: fourteen files paint a `Colors.black` / `surfaceDark` scaffold for immersive screens (AR, the Carcar foot-scan family, both camera scanners, the auth video entry, the document viewer), and three more are black photo lightboxes. That is a per-screen aesthetic, chosen by the author, not a brightness preference — and it is why "dark mode" feels half-built when you use the AR screen and plain-white-cream everywhere else.

The good news is the surface layer is genuinely tokenised: **1,113 of 1,212 surface fills (92 %) already come from tokens**, so a dark palette would repaint the app's backgrounds in one place. The hard part is the **foreground and role layer**, which is context-free and light-bound.

| Layer | State | Why it blocks dark mode |
|---|---|---|
| Surface fills | **92 % tokenised** (1,113 / 1,212) | Mostly ready — but the tokens are literals, not roles. |
| Text | **1,928 call sites** through `bodyStyle` / `headlineStyle` / `monoStyle`, all `static` (no `BuildContext`) with `color: secondary` defaults | Cannot be flipped by the theme; 1,422 of them pass an explicit colour. |
| "Muted" text | **338** `secondary.withValues(alpha: 0.4–0.7)` sites | Fading a dark brown over a light page; on dark this inverts and goes muddy/invisible. |
| Hairlines | **120** `borderGray.withValues(alpha: 0.3/0.5)` sites | Disappear on a dark surface. |
| Tints / callouts | **74** `primary.withValues(alpha: 0.08/0.1)` sites | Becomes mud on dark; needs a dark-mode tint. |
| Black | **220** refs (70 fills = shadows/scrims, 150 fg = text/icons) | Black text is invisible on dark; black shadows are invisible on dark. |
| Shadows | **82** `BoxShadow(` sites, incl. `warmShadow` | Elevation must invert (light surfaces read as raised, not shadowed). |
| Status colours | pastel `{bg, fg}` pairs, seller-side only | Their light backgrounds need dark counterparts. |
| Charts | **fl_chart** in 4 files, 16 config sites | Grid/axis/tooltip colours are literal. |
| System chrome | **0** `SystemUiOverlayStyle` / `AnnotatedRegion` | Status-bar icons never adapt, even on the black AR screen. |
| Native launch | Android `values-night/styles.xml` still `Theme.Light.NoTitleBar` with a **white** window background | Dark-mode users see a white flash before the cream first frame. |

---

## 2. What exists today

### 2.1 One palette, light only

`AppConstants` holds literal brand colours (`primary #8B5A2B`, `secondary #3B2314`, `accent #4ECDC4`, `success`, `error`, `borderGray`, `surfaceLight`, `creamDeep`, `sellerCardBg`) plus exactly **one** dark token:

```dart
static const Color surfaceDark = Color(0xFF1A1208);   // "Midnight Canvas (dark mode / AR overlay)"
```

It is used in 14 files, always as a *local* treatment for an immersive screen — never as a theme background. Note there are **no role tokens at all**: no `onSurface`, `onPrimary`, `muted`, `scrim`, `hairline` or `overlay` constant exists in `AppConstants`; the theme compensates by mapping `onPrimary` / `onSecondary` / `onError` → `surfaceLight` (cream) in a `ColorScheme` that hardcodes `brightness: Brightness.light`.

The seller palette is *not* a dark theme either — it is the same light cream surfaces with espresso/rust/sage accents. It does, however, contain the one pattern a dark status palette would copy: **paired {background, text} tokens** (`sageBg` / `sageDark`, `amberBg` / `amberDark`, `blueBg`).

### 2.2 Where dark already works

| Screen / widget | Treatment |
|---|---|
| `lib/screens/customer/ar_fitting_screen.dart` | `surfaceDark` scaffold, glass panels, `Colors.white` chrome |
| `lib/screens/customer/foot_ar_scan_screen.dart`, `foot_capture_screen.dart`, `foot_floor_detection_screen.dart`, `foot_manual_measure_screen.dart`, `foot_processing_screen.dart`, `foot_size_v2/foot_scan_session_screen_v2.dart` | Black / `surfaceDark` camera & processing surfaces |
| `lib/screens/seller/gcash_ref_scanner_screen.dart`, `pos_barcode_scanner.dart` | `Colors.black` camera surfaces |
| `lib/screens/auth/account_entry_screen.dart` | `surfaceDark` base behind the full-bleed video |
| `lib/widgets/admin/verification_doc_viewer.dart` | Dark document viewer |
| `product_detail_screen.dart`, `chat_view.dart`, `sole_review_card.dart` | Black **photo lightboxes** (full-screen image view), not dark screens |

The closest thing to a brightness switch that already ships is `lib/widgets/auth/signup_scaffold.dart`:

```dart
// Dark base when lightContent so there is never a cream flash before
// the video/backdrop paints (and a safe fallback if it fails to load).
backgroundColor: lightContent ? AppConstants.surfaceDark : AppConstants.surfaceLight,
```

That is a per-screen, hand-rolled dual treatment — proof the pattern works, and the reason it should become a first-class role (`isDarkSurface`) instead of a constructor flag on one widget.

### 2.3 Native chrome

| Platform | State |
|---|---|
| Android `values/styles.xml` | `LaunchTheme` + `NormalTheme` parent `Theme.Light.NoTitleBar`; `windowBackground` → `@drawable/launch_background` = **`@android:color/white`** |
| Android `values-night/styles.xml` | Same **light** parent and the same **white** background — night mode is not differentiated |
| iOS `Info.plist` | No `UIUserInterfaceStyle` key (app is not locked to light, and the launch storyboard is not configured for dark) |
| System UI | No `SystemUiOverlayStyle` / `AnnotatedRegion` anywhere → status-bar icon brightness is whatever the OS picked |

---

## 3. Where the cream palette would look wrong

Ordered by blast radius. Each is a *measured* count.

### 3.1 The `surfaceLight` role collision — 404 fills vs 98 foreground uses
`AppConstants.surfaceLight` means **two incompatible things** at once: the page cream *and* "light ink drawn on a dark surface" (`onPrimary` buttons, AR chrome, dark headers). The dark palette would need the page to go dark while those 98 sites stay light. Repointing the token flips both. `docs/AI/CREAM_THEME_SYSTEM.md` §3 already lists it as light-on-dark text — that is this collision, and dark mode is what turns it from a naming smell into a blocker.

### 3.2 The text colour is a literal dark brown — 993 refs (931 foreground)
`AppConstants.secondary` (`#3B2314`) *is* the body text colour, because `bodyStyle` / `headlineStyle` / `monoStyle` default `color: secondary`. Those helpers are `static` and take no `BuildContext`, so the theme cannot reach them: **506** call sites use the default, **1,422** pass an explicit colour (often `surfaceLight`, `Colors.white` or a status colour). Dark mode has to either thread context through the helpers or migrate text to `Theme.of(context).textTheme`.

### 3.3 The "muted text" idiom inverts — 338 sites
`secondary.withValues(alpha: 0.6)` ×127, `0.5` ×121, `0.4` ×49, `0.7` ×41. Fading a dark brown toward a light page = grey; fading it toward a *dark* page = mud. Every one of these renders "correctly" (no crash, no warning) and simply loses contrast — which is exactly the failure QA does not catch without dark goldens.

### 3.4 Hairlines that vanish — 120 sites
`borderGray.withValues(alpha: 0.5)` ×69 and `0.3` ×51, plus the solid `borderGray` borders (`#D2C7BC`). On `#1A1208` these read as faint warm smudges; a dark theme needs a lighter hairline role.

### 3.5 Tinted callouts become mud — 74 sites
`primary.withValues(alpha: 0.1)` ×41 and `0.08` ×33 (chips, info boxes, empty states). A 10 % clay wash over cream is a soft tint; over dark it is a murky brown patch with dark text on it.

### 3.6 Black as shadow *and* as text — 220 refs
70 black fills (scrims, lightboxes, shadows) and 150 black foregrounds (text/icons on light chips). The 82 `BoxShadow(` sites include `AppConstants.warmShadow`, an espresso-tinted shadow tuned for cream. On dark, elevation has to read as **lighter surface**, not darker shadow, or every card flattens.

### 3.7 Chrome and bands
The bottom nav band (`creamDeep #F0DFBB`, asserted by `test/widgets/sole_bottom_nav_test.dart`), the badge cut-out ring, `noiseOverlay` (a paper-grain texture, 46 refs, tuned to 3–4 % over cream), the seller GCash card gradients (`gcashBgStart/End/Border`) and `cardHeroEnd` all assume a light page.

### 3.8 Content, not chrome
- **Product photography.** The home masonry and catalog place photos of shoes on cream cards. On dark, images with white studio backgrounds glare; there is no `scrim` token and no image-tint strategy.
- **Charts.** `fl_chart` in `admin_analytics_screen.dart`, `seller_revenue_doughnut.dart`, `seller_revenue_line_chart.dart`, `seller_revenue_columns_chart.dart` — configuration sites with literal grid/axis/tooltip colours. (The seller trend card's *channel* fills are already tokenised as `SellerTheme.channelOnline` / `channelInStore`; its grid, axis labels and tooltip are not.)
- **Status pills.** `statusPendingColor` (9 fills / 52 fg), `statusConfirmedColor` (9 / 23), plus `success` (80 / 172) and `error` (166 / 321) — mostly `{colour, colour @ 0.1}` pairs expecting a light backdrop.
- **An off-token cream** — `Color(0xFFF5EDE4)` ×33, used as icon/label colour on dark headers. It would *survive* dark mode, but it shows the palette has already grown literal exceptions the surface guard does not track.

---

## 4. What a dark theme would need

### Stage 0 — decide the product question first
Three options, in increasing cost:

1. **Immersive-only (status quo, made deliberate).** Keep cream for the app, keep the black treatments for camera/AR. Cost: documentation + the `SystemUiOverlayStyle` fix so the AR screen's status bar matches. This is what the app does now — the value is in *saying* it.
2. **System-follow dark mode** for the whole app (`themeMode: system`). This is the real project described below.
3. **Manual toggle** (a setting + `ThemeMode.dark`). Same work as (2) plus persistence and a settings row — trivial once (2) exists, pointless before.

### Stage 1 — a role palette, not more literals
Introduce a `ThemeExtension<AppColors>` (or an `AppColors.light` / `AppColors.dark` pair) and express the palette as **roles**: `page`, `raised`, `band`, `hairline`, `onPage`, `onRaised`, `muted`, `onAccent`, `accentSoft` (tint), `scrim`, `shadow`. Keep the hexes in `app_constants.dart` / `seller_theme_constants.dart` exactly once. Light values are the current ones; dark values are new. The 92 % tokenised fills then follow — *provided* the names are roles, not tones (`surfaceLight` cannot have a dark variant with that name).

### Stage 2 — theme plumbing
`darkTheme:` + `themeMode: ThemeMode.system`, `colorscheme.brightness: Brightness.dark`, and removal of the two hardcoded `Brightness.light`s. Also: a `Brightness`-aware `noiseOverlay` opacity and a rebuilt `warmShadow`/elevation strategy (dark surfaces read as raised by being *lighter*, so most `BoxShadow`s should drop to ~0 opacity and card borders should carry the separation).

### Stage 3 — brightness-aware typography (the big one)
`bodyStyle` / `headlineStyle` / `monoStyle` must resolve their default colour per brightness. Options:

| Option | Effect |
|---|---|
| `bodyStyle(context, …)` / `AppColors.of(context)` | Correct, but touches all **1,928** call sites' signatures. |
| Keep the signature, read a global `AppBrightness.current` | Zero call-site churn, but a hidden global state that must be kept in sync with the theme (and breaks widget-test isolation unless reset). |
| Migrate to `Theme.of(context).textTheme` | The Flutter-native answer; largest diff, best long-term. |

Whichever is chosen, the **98 `surfaceLight`-as-foreground** sites and the **338 alpha "muted"** sites must be re-expressed as roles (`onDark`, `muted`) — those are the ones no mechanical change will get right.

### Stage 4 — the literal and alpha layer
99 literal surface fills — 70 blacks, 22 (mostly translucent) whites, 6 greys, 1 one-off brown — plus 120 hairlines, 74 tints and 82 shadows. Each needs a role decision, not a `sed`.

### Stage 5 — status colours and charts
Give every status colour a dark `{bg, fg}` pair, copying the seller palette's `sageBg`/`sageDark` shape into the shared constants. Re-key the 16 fl_chart config sites to role colours (grid, axis label, tooltip, series) — charts are the most common place a dark theme is shipped broken.

### Stage 6 — chrome and native surfaces
- `SystemUiOverlayStyle` per surface (light icons over dark surfaces) — currently absent, so the black AR/scanner screens already show the wrong status-bar icons.
- Android: a real `values-night` launch theme (dark parent + dark `launch_background`). Today both values folders point at white, so *even the light app* flashes white before the cream frame.
- iOS: decide launch-storyboard colours and whether to keep following the system.
- Re-check the espresso sellers screens in dark mode: the espresso/cream pair is inverted relative to the rest of the app, so it will need its own dark mapping rather than inheriting.

### Stage 7 — make the guard test earn its keep
`test/utils/theme_surfaces_test.dart` bans **white/grey/legacy-hex surface fills**. That rule is brightness-blind: a fully broken dark theme (dark fills, invisible text) passes it silently. To cover both modes it should become:

1. **No literal colours in a surface fill at all** — fill must be a role token, which is a stronger and simpler rule than today's white-only ban.
2. **A dark-theme companion check** — e.g. render the main shells under `Brightness.dark` and assert nothing painted is a light-only literal, plus a small golden set for contrast (the alphas in §3.3 are exactly what goldens catch and unit tests do not).
3. Keep the legacy-hex list: those five values stay wrong in both themes.

---

## 5. Effort, risk, and a definition of done

**Rough shape.** Stages 1–2 are days, not weeks, and they are the only way to *measure* the fallout — a single screen spiked under `ThemeMode.dark` will show immediately how much of the foreground layer is light-bound. Stage 3 is the long pole (1,928 call sites), Stage 4–5 is careful bulk work, Stage 6 is platform config that must be verified on a dark-mode device, and Stage 7 is the part that keeps it from decaying.

**The dominant risk is invisible breakage, not crashes.** Almost every dark-mode defect here is low contrast: `secondary` text on a dark page, 338 faded "muted" strings, 120 vanished hairlines, 74 muddy tints, black shadows on black. Nothing throws. That is precisely why Stage 7 (role-based guard + dark goldens) is not optional — without it the first regression ship will be silent.

**Definition of done** — a dark theme is done when: `themeMode: system` flips the whole app; no screen contains a literal surface fill; text/hairline/muted/tint roles resolve per brightness; status and chart colours have dark variants; the launch screen and status bar match in both modes; and the guard + golden set fail if any of that regresses.

---

## 6. Recommendation

Ship **Stage 0 option 1** now (name the immersive-dark treatment as intentional, fix the status bar on those screens and the white launch flash — both are bugs in the *current* app), and treat full dark mode as a scoped project starting at **Stage 1**. The tokenised surface layer makes it plausible; the context-free text helpers and the `surfaceLight` double meaning are what make it a real migration rather than a theme swap. Spike Stages 1–2 on one shell (customer home) to get a credible number before committing to the full sweep.
