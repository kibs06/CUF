# Logo design brief — SoleVision / CUFMAI

## Status: the symbol is settled

The mark is chosen and shipped — see `README.md` for the assets and how they are
generated. **`sole-mark-04-c-loafer.svg` and the launcher icons are the answer to
deliverable 1 and 2 below.** The C stands for CUFMAI's initial, and the tile is
deep brown at `#2C1207` with the render's upper-left light falling across it.

What is still missing is everything that turns a symbol into a usable identity:
the **wordmark**, its **lockups**, and a **single-ink variant**. That is what this
brief now asks for.

## The client, in three sentences

SoleVision is the marketplace app of **CUFMAI** — the Carcar United Footwear
Manufacturers Association, Inc. — a 2004 association of artisan shoemakers in
**Carcar City, Cebu, Philippines**, a town long known as the "Footwear Capital of
the South." The app gives those artisans the tools big brands have (storefront,
order pipeline, in-person point of sale) while keeping the craft the point:
hand-welted soles, full-grain leather, generations-old technique. One Flutter app
serves buyers, artisans and admins; a React portal handles web administration.

**The feeling to aim for:** heritage trade made digital — warm, tactile,
hand-made. Not a faceless e-commerce app, and not a startup.

## What we need now

| # | Deliverable | Notes |
|---|---|---|
| 1 | **Wordmark** | The main ask. See "The name" below — one name or two. |
| 2 | **Lockup** | Symbol + wordmark, horizontal and stacked, plus clear-space and minimum-size rules. |
| 3 | **Single-ink variant** | The symbol reduced to one colour, for app bars, favicons and one-colour print. The gold cannot survive a light background, so this is a real gap. |
| 4 | **Type licensing check** | Playfair Display, DM Sans and Sora are all open-licensed — confirm they cover the wordmark's intended use before committing. |

Already done: the symbol, the launcher icon, and the vector source.

## Palette — the mark's, not the app's

The mark carries its own palette, sampled from the render. Do not fold it back
into the app's tokens; they are different jobs.

| Role | Hex |
|---|---|
| Tile (upper-left, lit) | `#734225` |
| Tile (mid) | `#250D02` |
| Tile (lower-right) | `#160700` |
| Mark, shadow | `#401F0C` |
| Mark, body | `#F3D2A2` |
| Mark, highlight | `#FCF9EE` |
| Mark, flat fill (in the SVG) | `#E4BE8F` |

The app's own tokens, for context: Burnished Clay `#8B5A2B`, Espresso `#3A2415`,
Rust `#B5622E`, Celadon Teal `#4ECDC4`, cream `#F5EDE4`. The app runs a real dark
mode on `#111111`, so any new lockup must be checked on both white and `#111111`.

## Typography

The app pairs **Playfair Display** (headlines) with **DM Sans** (body) and
**Sora** (numbers). A wordmark should sit comfortably beside that system: a serif
with heritage weight, or a clean geometric sans. Not a display script.

## Hard constraints

- **The symbol must read at 24 px.** It does — the launcher icon is checked at 24
  / 32 / 48 / 64 / 120 / 180 px in `preview.html`. Anything you add has to hold up
  there too.
- **Keep the symbol's proportions.** It is a traced vector, so reshaping it by eye
  will fight the paths; if it needs a different silhouette, rebuild from
  `source/cufmai-c-mark-1254.png` rather than nudging the existing path.
- **The wordmark must clear the C.** The mark's outer sweep runs close to its own
  bounding box, so leave the clear space around it.
- Avoid the palette of generic e-commerce (pure blue, gradient purple).

## The name

The app carries two names: the association's (**CUFMAI**, the launcher label) and
the product's (**SoleVision**, the bundle id and all the docs under `docs/`). The
symbol commits to neither in letterform, but the C is CUFMAI's initial.

**Recommend which name the wordmark carries**, or show both. This is the one
genuine open question, and it is a product decision as much as a design one.

## Reference

`preview.html` shows the shipped mark at real sizes on light and dark, alongside
three earlier welt-stitch concepts (`sole-mark-01..03-*.svg`). The earlier three
are not the chosen direction, but their motif — the round running stitch where the
sole meets the upper — is the brand's strongest idea and it is still available to
the wordmark: it would make a good join or a good dot.
