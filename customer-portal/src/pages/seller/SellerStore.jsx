import { useEffect, useRef, useState } from 'react'
/*
  `useOutletContext` was missing here, and the page was therefore dead on
  arrival: the shell hands the store down through the outlet, the call threw
  `ReferenceError` on the first render, and `ErrorBoundary` caught it — so
  /seller/store showed "This page did not load" with nothing in the build or the
  unit suite to say why. Every other seller page imports it.
*/
import { useOutletContext } from 'react-router-dom'
import { ExternalLink, Loader2, Upload } from 'lucide-react'

import Field from '../../components/ui/Field'
import {
  SellerPageBody,
  SellerPageHeader,
  SellerSection,
} from '../../components/seller/SellerPage.jsx'
import { storeCompleteness } from '../../lib/seller.js'
import {
  useUpdateSellerStore,
  useUploadStoreAsset,
} from '../../hooks/useSeller.js'

/**
 * The seller's storefront.
 *
 * ## Why so few fields
 *
 * Five text fields and two images is everything the app's `EditStoreScreen`
 * and `StoreProfileScreen` write that a browser can write *well*. What is
 * deliberately missing:
 *
 *  - **Location.** The app picks a point on a map and stores `latitude` /
 *    `longitude` alongside the label. A text box here would let a seller move
 *    their workshop to a string, and the store page's map would keep rendering
 *    the old point — two answers to one question.
 *  - **Storefront schedule and GCash settings**, which are their own screens in
 *    the app and are not a form's worth of text.
 *
 * ## Live vs saved
 *
 * The fields save on submit. The two images do not: an upload is its own write
 * to its own bucket, and the row is pointed at the new URL as part of it. Making
 * a logo wait for a Save button would let a seller upload one, navigate away, and
 * believe it had been applied.
 */
export default function SellerStore() {
  const { store } = useOutletContext()
  const updateMutation = useUpdateSellerStore(store?.id ?? null)

  const [draft, setDraft] = useState({
    name: '',
    tagline: '',
    description: '',
    location: '',
    brand_color: '#8B5A2B',
    is_open: true,
  })
  const [error, setError] = useState(null)
  const [saved, setSaved] = useState(false)
  const hydrated = useRef(null)

  useEffect(() => {
    if (!store || hydrated.current === store.id) return
    hydrated.current = store.id
    setDraft({
      name: store.name ?? '',
      tagline: store.tagline ?? '',
      description: store.description ?? '',
      location: store.location ?? '',
      brand_color: store.brand_color || '#8B5A2B',
      is_open: store.is_open !== false,
    })
  }, [store])

  const onSubmit = async (event) => {
    event.preventDefault()
    setError(null)
    setSaved(false)

    if (!draft.name.trim()) {
      setError('Your store needs a name.')
      return
    }
    if (!draft.location.trim()) {
      setError('Your store needs a location — it is what customers read on your card.')
      return
    }

    try {
      await updateMutation.mutateAsync({
        name: draft.name.trim(),
        tagline: draft.tagline.trim() || null,
        description: draft.description.trim() || null,
        location: draft.location.trim(),
        brand_color: draft.brand_color,
        is_open: draft.is_open,
      })
      setSaved(true)
    } catch (failure) {
      setError(failure?.message ?? 'We could not save your storefront.')
    }
  }

  const completeness = storeCompleteness(store)

  return (
    <SellerPageBody>
      <SellerPageHeader
        eyebrow="Storefront"
        title={store?.name || 'Your storefront'}
        description="What customers read on your card and your store page."
      />

      {/*
        There is no "View as a customer" button, and there was one for about a
        minute.

        It pointed at `/makers/<id>` — the store's public page — and the shop is
        closed to sellers (`AppLayout` sends them back here), so the link opened a
        tab that immediately redirected to this portal. A preview link has to be
        able to reach the thing it previews, and by construction this account
        cannot.

        Rather than an exception in the redirect, which would be a hole in the
        one rule that keeps a seller out of the catalog, the page says where to
        look: the storefront is public in any signed-out browser, which is
        exactly the view a customer gets and needs no session at all.
      */}
      <p className="flex items-start gap-2.5 rounded-field border border-hairline bg-subtle/50 px-4 py-3 text-xs leading-relaxed text-muted">
        <ExternalLink className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
        <span>
          To see your storefront the way a customer does, open{' '}
          <span className="num text-ink">/makers/{store?.id ?? ''}</span> in a
          signed-out browser or a private window. Your seller account is kept out
          of the shop, so it cannot preview it for you.
        </span>
      </p>

      {/* The checklist disappears the moment it is empty — see the dashboard. */}
      {!completeness.complete && (
        <div className="rounded-card border border-hairline bg-subtle/50 px-5 py-4">
          <p className="text-sm font-medium text-ink">
            Still to do on your storefront
          </p>
          <ul className="mt-2 flex flex-wrap gap-x-5 gap-y-1.5 text-sm text-muted">
            {completeness.missing.map((item) => (
              <li key={item} className="flex items-center gap-2">
                <span
                  aria-hidden="true"
                  className="h-1.5 w-1.5 rounded-full bg-clay"
                />
                {item}
              </li>
            ))}
          </ul>
        </div>
      )}

      {error && (
        <div
          role="alert"
          className="rounded-field border border-crimson/30 bg-crimson/[0.07] px-4 py-3 text-sm text-ink"
        >
          {error}
        </div>
      )}

      {saved && (
        <p className="rounded-field border border-olive/30 bg-olive/[0.07] px-4 py-3 text-sm text-ink">
          Storefront saved.
        </p>
      )}

      <div className="grid gap-6 lg:grid-cols-[1.4fr_1fr]">
        <form onSubmit={onSubmit} className="flex flex-col gap-6">
          <SellerSection title="What customers read">
            <div className="space-y-5">
              <Field
                id="store-name"
                label="Store name"
                value={draft.name}
                onChange={(value) => setDraft((d) => ({ ...d, name: value }))}
                required
                placeholder="Valladolid Leather Co."
              />

              <Field
                id="store-tagline"
                label="Tagline"
                value={draft.tagline}
                onChange={(value) => setDraft((d) => ({ ...d, tagline: value }))}
                placeholder="Hand-stitched sandals since 1998"
                hint="One line, shown under your name on the makers page."
              />

              <Field id="store-description" label="About the workshop">
                <textarea
                  id="store-description"
                  value={draft.description}
                  onChange={(event) =>
                    setDraft((d) => ({ ...d, description: event.target.value }))
                  }
                  rows={6}
                  placeholder="Who makes the shoes, how long the workshop has been running, what it is known for."
                  className="mt-2 w-full rounded-field border border-hairline bg-raised px-4 py-3 text-sm leading-relaxed text-ink transition-colors duration-200 ease-out-cubic placeholder:text-muted/60 hover:border-card-edge focus:border-clay"
                />
              </Field>

              <Field
                id="store-location"
                label="Location"
                value={draft.location}
                onChange={(value) => setDraft((d) => ({ ...d, location: value }))}
                required
                placeholder="Valladolid, Carcar City, Cebu"
                hint="The first part before a comma is what shows on your card."
              />

              <label className="flex items-start gap-3 rounded-field border border-hairline bg-subtle/50 px-4 py-3">
                {/* `accent-clay` — the same fix as the product form's checkbox:
                    a text colour on a checkbox paints nothing, so this one was
                    the browser's own blue-grey on a brown site. */}
                <input
                  type="checkbox"
                  checked={draft.is_open}
                  onChange={(event) =>
                    setDraft((d) => ({ ...d, is_open: event.target.checked }))
                  }
                  className="mt-0.5 h-4 w-4 rounded border-hairline accent-clay"
                />
                <span className="text-sm">
                  <span className="font-medium text-ink">
                    Open for orders
                  </span>
                  <span className="mt-0.5 block text-xs leading-relaxed text-muted">
                    Closed keeps your store and its products visible, and stops
                    new orders coming in.
                  </span>
                </span>
              </label>

              <label className="block">
                <span className="block text-xs font-semibold uppercase tracking-[0.08em] text-muted">
                  Brand colour
                </span>
                <span className="mt-2 flex items-center gap-3">
                  <input
                    type="color"
                    value={draft.brand_color}
                    onChange={(event) =>
                      setDraft((d) => ({
                        ...d,
                        brand_color: event.target.value,
                      }))
                    }
                    aria-label="Brand colour"
                    className="h-10 w-14 cursor-pointer rounded-field border border-hairline bg-raised"
                  />
                  <span className="num text-sm text-muted">
                    {draft.brand_color}
                  </span>
                </span>
                <span className="mt-1.5 block text-xs text-muted">
                  The rule along the top of your card, and the wash behind a
                  storefront with no photo.
                </span>
              </label>
            </div>

            <button
              type="submit"
              disabled={updateMutation.isPending}
              className="btn btn-primary mt-6 w-full sm:w-auto"
            >
              {updateMutation.isPending && (
                <Loader2 size={15} className="animate-spin" />
              )}
              Save storefront
            </button>
          </SellerSection>
        </form>

        <SellerSection
          title="Photos"
          description="The banner is the panel on the makers page; the logo is the small mark."
        >
          <div className="space-y-5">
            <AssetSlot
              kind="banner"
              label="Storefront photo"
              url={store?.banner_url ?? null}
              storeId={store?.id}
              aspect="aspect-[16/9]"
            />
            <AssetSlot
              kind="logo"
              label="Logo"
              url={store?.logo_url ?? null}
              storeId={store?.id}
              aspect="aspect-square"
            />
            <p className="text-xs leading-relaxed text-muted">
              A photo replaces the brand-colour gradient customers currently see,
              so it is worth adding.
            </p>
          </div>
        </SellerSection>
      </div>
    </SellerPageBody>
  )
}

/**
 * One image slot.
 *
 * `type='logo'` / `type='banner'` is the app's own vocabulary for the storage
 * path (`{sellerId}/{storeId}-{type}-{timestamp}.{ext}`), so a file uploaded here
 * and a file uploaded from the phone are indistinguishable in the bucket — which
 * matters because both write the same `stores` column afterwards.
 */
function AssetSlot({ kind, label, url, storeId, aspect }) {
  const mutation = useUploadStoreAsset(storeId)

  return (
    <div>
      <p className="text-xs font-semibold uppercase tracking-[0.08em] text-muted">
        {label}
      </p>

      <div
        className={`mt-2 overflow-hidden rounded-card border border-hairline bg-subtle ${aspect}`}
      >
        {url ? (
          <img src={url} alt="" className="h-full w-full object-cover" />
        ) : (
          <div className="flex h-full items-center justify-center px-4 text-center text-xs text-muted">
            No {kind === 'logo' ? 'logo' : 'photo'} yet
          </div>
        )}
      </div>

      <label className="btn btn-outline mt-3 w-full cursor-pointer">
        {mutation.isPending ? (
          <Loader2 size={15} className="animate-spin" />
        ) : (
          <Upload className="h-4 w-4" aria-hidden="true" />
        )}
        {mutation.isPending ? 'Uploading…' : url ? 'Replace' : 'Upload'}
        <input
          type="file"
          accept="image/*"
          className="sr-only"
          disabled={mutation.isPending}
          onChange={(event) => {
            const file = event.target.files?.[0]
            event.target.value = ''
            if (!file) return
            mutation.mutate({ file, type: kind })
          }}
        />
      </label>

      {mutation.isError && (
        <p className="mt-2 text-xs text-crimson">
          {mutation.error?.message ?? 'That upload did not work.'}
        </p>
      )}
    </div>
  )
}
