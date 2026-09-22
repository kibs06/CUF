# Branding — the C mark

The app's mark is a **C for CUFMAI** with a loafer inside it, drawn in champagne
gold on a deep brown tile. It ships as the launcher icon on Android and iOS.

Both the assets and the icons are generated. Nothing here is hand-edited:

```bash
node assets/branding/build-icons.mjs   # 1024 sources, from the render
dart run flutter_launcher_icons        # every icon, from the sources
```

`flutter_launcher_icons` is configured at the bottom of `pubspec.yaml`. It writes
all five Android densities (48 / 72 / 96 / 144 / 192 px), the adaptive icon's
three layers, and the complete iOS `AppIcon.appiconset` — 21 PNGs, flattened to
RGB because App Store validation rejects an alpha channel in an AppIcon. There is
no web target in this project (`web/` has no `index.html`), so no web icons are
generated.

## Files

| File | What it is |
|---|---|
| `source/cufmai-c-mark-1254.png` | The original render, kept verbatim. Everything else derives from it. |
| `cufmai-c-mark-1024.png` | The launcher source: full-bleed, opaque, RGB. |
| `cufmai-c-mark-adaptive-background-1024.png` | Android background layer — the tile's gradient with the mark removed. |
| `cufmai-c-mark-adaptive-foreground-1024.png` | Android foreground layer — the mark alone, on transparency. |
| `cufmai-c-mark-adaptive-monochrome-*` | Not stored; `flutter_launcher_icons` reuses the foreground for themed icons. |
| `sole-mark-04-c-loafer.svg` | The editable vector of the shipped mark. |
| `sole-mark-01..03-*.svg` | The earlier welt-stitch concepts, kept for reference. |
| `build-icons.mjs` | The generator. Documented at its top; see "Regenerating" below. |
| `preview.html` | Open it in a browser to see everything at real sizes, light and dark. |
| `DESIGN_BRIEF.md` | The one-pager for a designer — now scope for the *remaining* work. |

`pubspec.yaml` lists its assets explicitly and nothing here is referenced from
`lib/`, so adding files to this folder does not change the build.

## The render had three problems, all solved in the generator

1. **It arrived with baked rounded corners** (~25% radius) on a **fully
   transparent** canvas. iOS rejects alpha outright, and Android wants the art
   and the background as separate layers. `build-icons.mjs` squares the tile off
   by extending each row's edge pixels outwards, so the fill continues the tile's
   own gradient instead of inventing a corner colour. Both platforms mask the
   corners themselves, so the fill is never actually seen — it only has to be
   plausible. Note that cropping *inwards* to dodge the corners is not an option
   here: the mark runs to within a couple of pixels of the tile edge.
2. **The mark spans nearly the whole tile**, so a plain brightness threshold
   cannot separate it from the background. The generator estimates the background
   as a smooth gradient in two passes — a coarse low-percentile pass locates the
   mark, then the field is re-fit from only the pixels that pass called background,
   excluding everything within a few pixels of the ink. Averaging the render's soft
   rim back in is what produces a ghost of the C in the background layer; that is
   why the exclusion is spatial rather than threshold-based.
3. **The artwork is a raster with no vector original.** `sole-mark-04-c-loafer.svg`
   is therefore not hand-traced — the mark's silhouette is contoured out of the
   alpha matte with marching squares and simplified with Douglas-Peucker, so it is
   the render's real shape, flat rather than beveled. Rendering that SVG back over
   the mask it was cut from gives a silhouette IoU of **0.978**; the residual is
   the contour's half-pixel convention, not a wrong shape.

## Palette — the mark's own

Sampled from the shipped `cufmai-c-mark-1024.png` and its foreground layer. These
are **not** the app's five tokens; the mark reads warmer than the UI around it.

| Role | Hex | Notes |
|---|---|---|
| Tile, top-left | `#734225` | The render's light falls from the upper left. |
| Tile, mid | `#250D02` | |
| Tile, bottom-right | `#160700` | |
| Mark, shadow | `#401F0C` | The bevel's shaded flank. |
| Mark, mid | `#BC9163` | |
| Mark, body | `#F3D2A2` | The champagne the eye reads as "the gold". |
| Mark, highlight | `#FCF9EE` | Nearly white where the bevel catches light. |
| Mark, flat fill | `#E4BE8F` | What the SVG uses — the median of the mark's solid core, since a vector cannot carry the bevel. |

For reference, the app's own tokens (`lib/constants/app_constants.dart`) are
Burnished Clay `#8B5A2B`, Espresso `#3A2415`, Rust `#B5622E`, Celadon Teal
`#4ECDC4` and cream `#F5EDE4`. The mark deliberately sits outside that set:
comparison of `#F3D2A2` with the cream token shows how much warmer and more
saturated the render is. Keep the two palettes apart — the UI did not change when
the logo did.

## Regenerating

```bash
node assets/branding/build-icons.mjs                       # sources
node assets/branding/build-icons.mjs --debug               # + ink/background maps
node assets/branding/build-icons.mjs --dump-mask           # + the 512 silhouette the SVG was traced from
node assets/branding/build-icons.mjs some/other/render.png # a different source
dart run flutter_launcher_icons                            # icons
```

**`flutter_launcher_icons` corrupts `ios/Runner.xcodeproj/project.pbxproj` on every
run.** Its iOS step rewrites *every* line containing `ASSETCATALOG` inside an
`XCBuildConfiguration` block to `= AppIcon;`, which is correct for
`ASSETCATALOG_COMPILER_APPICON_NAME` but wrong for
`ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS`, which expects
`YES`/`NO`. Restore it after each run:

```bash
perl -pi -e 's/^(.*ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = )AppIcon;/$1YES;/' \
  ios/Runner.xcodeproj/project.pbxproj
```

Use `perl` rather than `sed -i`: the file is checked out with CRLF endings, and
`sed -i` rewrites it with LF, which shows up as a phantom whole-file change to the
next person who runs `git status`. `perl -pi` leaves the endings alone.

The generator script has no dependencies beyond Node's `zlib`, and it verifies its
own output: it reads the PNGs back and fails if they are not the expected size or
colour type. `--debug` prints an ink-density map (where the mark is) and a
luminance map of the background field — if that second map ever traces the shape
of the C, the field has swallowed the mark and the adaptive icon will show it
twice. Regenerate the preview after changing any of this:

```bash
chrome --headless=new --window-size=1600,1400 \
  --screenshot=.artifacts/branding-preview.png assets/branding/preview.html
```

## Two growth levers

The mark's long edge sits at 72% of the foreground canvas. That is not arbitrary:
`flutter_launcher_icons` writes `android:inset="16%"` on the foreground, so the
art is drawn into 68% of the 108 dp layer, and Material's safe keyline is a 66 dp
circle. 72% is the largest value that keeps the mark's circumscribed circle at
66 dp, which is what stops a circular launcher mask from clipping the C's sweep.
Changing `SAFE` without redoing that arithmetic will either clip the mark or
shrink it.

## Naming

The app carries two names: the **association**, CUFMAI (the Android launcher
label), and the **product**, SoleVision (`com.solevision.app`, and the docs under
`docs/`). The C in this mark is CUFMAI's. There is still no wordmark; that is the
next piece of design work, and `DESIGN_BRIEF.md` scopes it.

## The three earlier concepts

Kept because they share a motif worth not losing — the welt stitch of a
hand-welted sole — and because they are the geometric reference if the traced
vector ever needs rebuilding as clean curves.

| | File | Idea | Best at |
|---|---|---|---|
| 01 | `sole-mark-01-welt.svg` | Solid clay sole with an inset running stitch. | The only one that stays solid at 32 px. |
| 02 | `sole-mark-02-running-stitch.svg` | The stitch alone, no fill, one teal thread at the toe. | Anywhere it must recolour to a single ink. |
| 03 | `sole-mark-03-two-tone-welt.svg` | Rust welt ring, espresso footbed, stitch between. | Larger placements; the most expressive. |

All three are 512×512 on transparency with the same sole geometry — toe dome,
narrowed waist, rounded heel — so any two can sit side by side without the forms
disagreeing. The stitch is a `stroke-dasharray` round dash rather than a
hand-placed dot ring, so it re-spaces by changing two numbers.
