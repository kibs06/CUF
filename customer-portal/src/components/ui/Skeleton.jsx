/**
 * Shimmer placeholders.
 *
 * Each skeleton below mirrors the *geometry* of the thing it stands in for —
 * same corner radius, same aspect ratio, same line heights. That is the point:
 * a placeholder of the wrong height still causes the layout shift it exists to
 * prevent, and the customer sees the page jump the moment the data lands.
 */
export default function Skeleton({ className = '' }) {
  return <div className={`shimmer rounded-lg ${className}`} />
}

/** Stands in for `ProductCard` — identical shell, identical square image. */
export function ProductCardSkeleton() {
  return (
    <div className="overflow-hidden rounded-card border border-hairline bg-raised shadow-card">
      <Skeleton className="aspect-square w-full rounded-none" />
      <div className="space-y-2 p-4">
        <Skeleton className="h-4 w-4/5" />
        <Skeleton className="h-3 w-2/5" />
        <Skeleton className="mt-3 h-5 w-1/3" />
      </div>
    </div>
  )
}

export function ProductGridSkeleton({ count = 8 }) {
  return (
    <div className="grid grid-cols-2 gap-x-4 gap-y-6 sm:gap-x-5 md:grid-cols-3 xl:grid-cols-4">
      {Array.from({ length: count }).map((_, index) => (
        <ProductCardSkeleton key={index} />
      ))}
    </div>
  )
}

/**
 * Stands in for a maker's panel in the makers gallery.
 *
 * It mirrors the panel's own geometry — the same third of the row, the same
 * 350px and 450px heights, the brand rule where the real one sits and the text
 * stack at the bottom — because the makers row is where a wrong-height
 * placeholder hurts most: three panels loading at the wrong height reflow the
 * page the moment the real photographs arrive.
 *
 * It does not try to fake a photograph. A shimmer over `bg-subtle` is honest
 * about being a placeholder; a grey rectangle pretending to be a storefront
 * would make the loading state look like a broken image.
 */
export function StoreCardSkeleton() {
  return (
    <div className="relative flex h-[350px] w-full flex-col justify-end gap-3 overflow-hidden rounded-card bg-subtle p-6 shadow-card md:w-1/3 lg:h-[450px]">
      <Skeleton className="absolute inset-x-0 top-0 h-1 rounded-none" />
      <Skeleton className="h-6 w-2/3" />
      <Skeleton className="h-3 w-1/3" />
      <Skeleton className="h-3 w-4/5" />
      <Skeleton className="h-3 w-3/5" />
      <div className="flex items-center justify-between border-t border-hairline-soft pt-3">
        <Skeleton className="h-3 w-28" />
        <Skeleton className="h-3 w-16" />
      </div>
    </div>
  )
}

/**
 * Stands in for `OrderCard`: same header, thumbnail row, price and rail.
 *
 * The thumbnail is 56px rather than the card's 56px square with a 4px gap, and
 * the rail is present even though it is conditional — a page that reflows when
 * the data lands has undone the point of the placeholder.
 */
export function OrderCardSkeleton() {
  return (
    <div className="rounded-card border border-hairline bg-raised p-5 shadow-card">
      <div className="flex items-start justify-between gap-4">
        <div className="space-y-2">
          <Skeleton className="h-3 w-20" />
          <Skeleton className="h-4 w-32" />
        </div>
        <Skeleton className="h-6 w-24 rounded-full" />
      </div>
      <div className="mt-4 flex items-center gap-3">
        <Skeleton className="h-14 w-14 shrink-0 rounded-product" />
        <div className="flex-1 space-y-2">
          <Skeleton className="h-4 w-3/5" />
          <Skeleton className="h-3 w-2/5" />
        </div>
        <Skeleton className="h-5 w-20" />
      </div>
      <Skeleton className="mt-5 h-2 w-full" />
    </div>
  )
}

/** A hero-shaped block for the top of a page still loading. */
export function HeroSkeleton({ className = 'h-[420px]' }) {
  return <Skeleton className={`w-full rounded-premium ${className}`} />
}
