/**
 * The pill a header's navigation link wears.
 *
 * One function for two bars — the storefront's `SiteHeader` and the seller
 * portal's `SellerHeader` — because the seller bar is deliberately the same bar
 * with different destinations in it, and "the same bar" stops being true the
 * first time somebody adjusts one of them. The active state in particular is the
 * thing a customer reads as "where am I", so it is written once.
 *
 * `max-sm:px-2` is the storefront's own concession to a 390px bar, and the seller
 * row below `lg` wants it for the same reason: six labels and the logo do not fit
 * on a phone at full padding.
 */
export const navLinkClass = ({ isActive }) =>
  [
    'rounded-full px-3 py-1.5 text-sm font-medium transition-colors duration-200 ease-out-cubic max-sm:px-2',
    isActive
      ? 'bg-clay/10 text-clay-ink'
      : 'text-muted-strong hover:bg-subtle hover:text-ink',
  ].join(' ')
