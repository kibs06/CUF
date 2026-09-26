import { useState } from 'react'

import { storeBannerUrl, storeCardGradient } from '../../lib/storeBannerRules'

/**
 * A maker's banner — the storefront photograph they uploaded — with the app's
 * brand gradient behind it.
 *
 * The gradient is not a placeholder that flashes and is replaced: it is what a
 * store without a banner *is*, and it is what a store with a broken one falls
 * back to. `Store.cardGradient` in the app paints the same thing in the same two
 * cases (its `placeholder` and `errorWidget` are the identical gradient), so a
 * workshop that has not been photographed still gets a card with its own colour
 * at the top rather than a grey box.
 *
 * `alt=""` because the banner is decoration: the store's name is the text right
 * below it, and a screen reader announcing "banner image" twice on the same card
 * adds nothing. The card itself is one link, and its label is its text.
 *
 * The failure is tracked by URL rather than as a boolean, so a component reused
 * for another store (the grid re-orders when the catalog refetches) does not
 * carry the previous store's broken image across with it.
 */
export default function StoreBanner({ store, className = '' }) {
  const url = storeBannerUrl(store)
  const [failedUrl, setFailedUrl] = useState(null)
  const showing = url && failedUrl !== url

  return (
    <div
      className={`relative w-full shrink-0 overflow-hidden bg-subtle ${className}`}
      style={showing ? undefined : { backgroundImage: storeCardGradient(store) }}
    >
      {showing && (
        <img
          src={url}
          alt=""
          loading="lazy"
          decoding="async"
          onError={() => setFailedUrl(url)}
          className="h-full w-full object-cover"
        />
      )}
    </div>
  )
}
