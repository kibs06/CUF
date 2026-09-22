# Store sale indicator — plan

**Status:** **built.** All product decisions are settled (see the decision
record). Where the build differs from this plan is recorded under *As built* at
the end; see also `NAV_STORE_CAROUSEL_ARCHITECTURE.md` §1c for the shipped
description.

## What it is

On the **Stores** tab (`lib/screens/store/store_screen.dart`), a store that has
at least one product on sale right now shows a **hang-tag-shaped indicator** in
the hero card's stat-pill row. It is tappable and opens that store's on-sale
products.

The surface is the hero carousel card, `store_hero_card.dart`, in the pill row
that currently reads `⭐ 4.0 · 👟 5 · 📍 location`.

## Decision record

| Decision | Choice |
|---|---|
| Indicator form | **Hang-tag motif** — the product card's sale-tag silhouette (cream paper, cut corner, amber grommet), at pill scale |
| Placement | **Hero card pill row**, right of the existing pills |
| Tap behaviour | **Enters the store pre-filtered** to its on-sale products |
| Motion | **Gentle idle dangle** on the focused card only, reduced-motion gated |
| Copy | **`UP TO` micro-label / `-30%`** — the best live discount, floored |

## The rule — one source of truth, reused

"A store is on sale" is **not** a new concept and must not become one. It is:

> the store has at least one product for which `isOnSale(product)` is true.

`lib/utils/sale_price.dart` already owns that rule (`isOnSale`, plus
`maxDiscountPercent` for a best-discount figure). The indicator imports it; it
never re-implements the price/date comparison. This is the standing constraint in
`docs/AI/HOME_ON_SALE_ARCHITECTURE.md` §7.1 and §7.10.

The store's **best discount**, if the copy uses a number, is
`maxDiscountPercent(storeProducts)` — the same floored ("up to") rule the ON SALE
home poster uses, so a store tag and the feed poster can never disagree.

## Where the data comes from — no schema change, no new query

`store_screen.dart` already loads the whole catalog through `ProductProvider`
and builds a per-store index in `_reindexIfNeeded()`:

```dart
_indexedFrom      // the products list the index was built from
_productCounts    // storeId → product count
_topPicksByStore  // storeId → that store's products (newest first)
```

The extension is one more map built in the same pass:

```dart
_saleByStore  // storeId → (count, bestDiscountPercent, earliestSaleEnd)
```

- `count` / `bestDiscountPercent` come from `isOnSale` / `maxDiscountPercent`
  over that store's products.
- `earliestSaleEnd` is the soonest non-null `sale_ends_at` among its on-sale
  products, for the expiry watcher below.

Because `_reindexIfNeeded` is keyed on the products list identity, this costs one
pass over products per catalog change — the same order as the existing counts.

The indicator must follow the **same product set as the existing product count**
(`_productCounts`), so "5 products" and "on sale" can never describe different
lists. Both read the loaded catalog (`hideOutOfStock: true`), which is what the
customer can actually browse.

## The indicator

A tag-shaped pill, not the product card's `HangingSaleTag` widget.
`HangingSaleTag` is 72×100 and its tap is a **one-way reveal** of the discount
backed by `SaleTagProvider`; that interaction is wrong here (the store tag's tap
navigates). What is reused is the **motif**, not the widget:

- the cream-paper body, cut top-right corner and punched amber grommet from
  `hanging_sale_tag.dart`'s `_TagBodyPainter` (currently private — extract or
  redraw at pill scale);
- the dangle (see Motion below), not the product tag's continuous pendulum and
  not its per-product phase.

Size target: the pill row's height (~24px) — a small tag, one line of copy plus
the micro-label. Whole tag is one tap target.

### Copy — decided: `UP TO` / `-30%`

The micro-label is `UP TO` and the value is the store's best discount from
`maxDiscountPercent` (floored). This is the same qualifier and the same rule the
ON SALE home poster uses, so a store tag and the feed poster can never overstate
a deal, and the customer gets a reason to tap. The product card's tag says
`SALE` / `-23%`, but that names **one product's own** discount; at store scale a
bare `-30%` would read as "everything 30% off", which is why the aggregate
carries `UP TO`.

**Edge — a sale too small to floor.** `maxDiscountPercent` returns `null` for a
discount of under 1% even though `isOnSale` is true. The tag must not print
`-0%`; when `count > 0` but `bestDiscount == null`, it falls back to a bare
`ON` / `SALE` face rather than hiding (hiding would make the store look
non-sale while it is).

### Motion — decided: gentle idle dangle

A subtle periodic lean, **on the focused card only** (the carousel knows
the focused index; the peeking neighbours stay still). Shaped like the app's
existing idle beats — the Workshop poster's `tease` and `SeeMoreCard`'s glide:
Timer-scheduled, `TickerMode`-gated, reduced-motion aware, and each lean
**ends at zero** so a finished beat leaves no tilt. It is deliberately not the
product tag's continuous pendulum — that swing is a product's own identity, and
a row of them in a carousel would be noise. A tap landing mid-lean must not
leave the tag resting off-square.

## Tap behaviour

The hero card is itself a tap target (`onTap: () => _enterStore(store)`), so the
tag's tap must be contained — the same nesting `HangingSaleTag` handles (opaque
to absorb its own tap) — and it must **not** enter the store as the card tap
does.

**Decided: enter the store pre-filtered.** Tapping the tag pushes
`StoreProfileScreen` with an on-sale filter already active, so the customer
keeps the store's context and can clear the filter to see everything.

- New optional param on `StoreProfileScreen` (e.g. `saleOnly` / an initial
  filter value); its grid is `_storeProducts` filtered by `isOnSale`.
- The profile page shows a visible, clearable **On Sale** chip while the filter
  is on — the customer must never be stuck inside a filtered view with no way
  back (the size shelf's "Clear filters" rule).
- `StoreProfileScreen` loads its own `_storeProducts`, and those rows carry the
  sale fields, so the filter needs no new fetch.
- The "nothing on sale" state should not be reachable from the tag (the tag
  only renders when `count > 0`) but the page still needs a sane state if the
  sale expires while it is open — the same live-expiry rule below.

## Live expiry

The indicator claims something about *now*. When the last sale in a store ends
while the Stores tab is open, the tag must disappear on its own — the screen only
rebuilds on `ProductProvider.notifyListeners()` (loads/writes), which a sale
expiring does not trigger.

`SaleEndWatcher` (`lib/widgets/sale_countdown_overlay.dart`) is the app's
existing answer, but it watches **one product's** `sale_ends_at`. Generalize it
to accept an explicit `saleEndsAt` (keeping the product constructor as-is), or
add a thin store-level sibling, and schedule it against `earliestSaleEnd`. Thread
the resulting `now` into `isOnSale` / `maxDiscountPercent`.

An open-ended sale (no `sale_ends_at` anywhere) schedules nothing — no invented
urgency, matching the countdown overlay's rule.

## Absent-safe

No store sale → no tag at all, and no residual gap: the pill is a conditional
child of the pill row, never a reserved spacer. Same rule as every other size /
sale surface in the app.

## Layout constraints

The pill row is `rating pill · product-count pill · Flexible(location pill)`.
A fourth child makes overflow a real risk at 320px with a long location, so:

- keep the tag compact and fixed-width;
- the location pill stays `Flexible` (already is);
- confirm at 320px and at 1.3× text scale (the same cases the size-poster tests
  already pin).

## Accessibility

One semantics node per tag, e.g.:

> "On sale: 3 items, up to 30 percent off. Double tap to see this store's sale
> items."

Only claim the number when one exists; a bare sale says "On sale".

## Files to touch

| File | Change |
|---|---|
| `lib/screens/store/store_screen.dart` | Build `_saleByStore` in `_reindexIfNeeded`; pass to the carousel |
| `lib/screens/store/widgets/store_hero_carousel.dart` | New pass-through param |
| `lib/screens/store/widgets/store_hero_card.dart` | Render the tag in the pill row; contained tap |
| `lib/widgets/store_sale_tag.dart` *(new)* | The tag-shaped pill (motif extracted from `hanging_sale_tag.dart`) |
| `lib/screens/customer/on_sale_listing_screen.dart` | Optional `storeId` scope *(if Option A)* |
| `lib/widgets/sale_countdown_overlay.dart` | Generalize `SaleEndWatcher` for an explicit end |
| `docs/AI/STORE_SCREEN_SOURCE.md`, `CHANGELOG.md` | Document the surface and the rule |

## Test plan

- **Rule:** a store with one on-sale product shows the tag; a store with only
  expired/not-yet-started/cleared sales does not (reuse `sale_price` fixtures).
- **Derivation:** best discount is floored via `maxDiscountPercent`; the sale set
  matches the product count's set.
- **Absent-safe:** no tag and no layout shift when nothing is on sale.
- **Expiry:** with a `sale_ends_at` a second away, the tag clears on its own.
- **Tap:** tapping the tag does not enter the store; it opens the sale items.
- **Layout:** pill row does not overflow at 320px / 1.3× scale.
- `flutter analyze lib test` clean, full suite green.

## As built

Shipped as planned, with these three deliberate deviations — each one made
because the plan's simpler shape would have been wrong or too heavy:

1. **The store's products go to the card, not a screen-level summary map.** The
   plan's `_saleByStore` (count / bestDiscount / earliestEnd) cannot re-derive
   itself when the *first* of several sales ends, so the card instead receives
   the store's product list (the same one the `👟` count comes from) and derives
   the summary through `storeSaleFrom` at render time.
2. **The expiry is a store-level sibling, not a generalization of
   `SaleEndWatcher`.** `SaleEndWatcher` fires once for one fixed end and cannot
   chain; `StoreSaleEndWatcher` re-derives and re-arms at each next end, so a
   store with staggered sales stays correctly on sale until its *last* one ends.
   `SaleEndWatcher` itself is untouched.
3. **The tag is 68×28, not ~24px tall, and its copy is `FittedBox(scaleDown)`.**
   The narrow-phone test caught two overflows at 320px / 1.3× text scale (the
   tag's own Column, and the pill row itself); the fixed, smaller box plus a
   scale-down block — the poster family's own treatment — is what fits. The
   layout case is now pinned by a test rather than assumed.

Notes 3–6 from the original list were built as written (contained tap,
`saleOnly` + clearable chip, focused-only dangle, the 320px/1.3× check).
Documentation landed in `NAV_STORE_CAROUSEL_ARCHITECTURE.md` §1c and the
CHANGELOG; `docs/AI/STORE_SCREEN_SOURCE.md` is a stale raw-source snapshot and
was left alone.
