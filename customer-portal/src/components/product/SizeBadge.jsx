import { Check } from 'lucide-react'

/**
 * The "your size" tag on a product tile.
 *
 * It answers the one question a grid of shoes cannot: *is it in mine?* — and it
 * answers it from the same rule the home shelf and the product page use, so a
 * tag here and that shelf can never disagree.
 *
 * Three details are deliberate:
 *
 *  1. **It is neutral, not another coloured pill.** The discount tag (top-left,
 *     clay) and the "View details" affordance (bottom-centre, dark) already own
 *     their corners. A third saturated pill would turn the tile into badges, so
 *     this one is a raised surface with a hairline and a small olive check — the
 *     palette's own success colour — and reads as a label on the photograph.
 *
 *  2. **`pointer-events-none` is load-bearing**, exactly as it is on the other
 *     two overlays: the tag sits above the stretched link, so without it the
 *     badge would swallow clicks that are meant for the product.
 *
 *  3. **It is `aria-hidden`.** The tile is ONE link with a screen-reader label
 *     that already carries the size state (`ProductCard` appends it), so letting
 *     a screen reader read the tag separately would announce the same fact
 *     twice — once as link text, once as loose content after it.
 *
 * The states and their wording live in `sizeBadgeFor` (lib/sizeMatchRules.js),
 * where they are tested without a DOM: in stock, sold out, or nothing at all.
 */
export default function SizeBadge({ badge, className = '' }) {
  if (!badge) return null

  const inStock = badge.tone === 'in-stock'

  return (
    <span
      aria-hidden="true"
      className={`num pointer-events-none inline-flex items-center gap-1 rounded-full px-2 py-1 text-[11px] font-semibold leading-none backdrop-blur-sm ${
        inStock
          ? 'bg-raised/95 text-ink ring-1 ring-hairline'
          : 'bg-raised/90 text-muted ring-1 ring-hairline-soft'
      } ${className}`}
    >
      {inStock && <Check size={11} strokeWidth={3} className="text-olive" />}
      {badge.label}
    </span>
  )
}
