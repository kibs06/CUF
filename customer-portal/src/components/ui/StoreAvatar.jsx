import { getInitials, storeColor } from '../../lib/constants'

/**
 * A maker's avatar: their logo if they uploaded one, otherwise their initials
 * on their own brand colour.
 *
 * The fallback is not a grey circle with a letter in it — a marketplace of
 * artisan stores should look like a row of *shops*, and the initials tinted
 * with each store's own colour (the same `brand_color` the app paints its store
 * pages with) does that with no asset at all.
 */
export default function StoreAvatar({ store, size = 52, className = '' }) {
  const color = storeColor(store)
  const dimension = { width: size, height: size }

  if (store?.logo_url) {
    return (
      <img
        src={store.logo_url}
        alt=""
        style={dimension}
        className={`shrink-0 rounded-full border border-hairline object-cover ${className}`}
      />
    )
  }

  return (
    <span
      aria-hidden="true"
      style={{
        ...dimension,
        backgroundColor: `${color}1A`,
        color,
      }}
      className={`num flex shrink-0 items-center justify-center rounded-full text-sm font-semibold ${className}`}
    >
      {getInitials(store?.name)}
    </span>
  )
}
