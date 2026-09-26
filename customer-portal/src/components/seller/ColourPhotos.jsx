import { ImageOff, Plus, X } from 'lucide-react'

import { MAX_COLOUR_IMAGES, colourImagesFor } from '../../lib/productColourImages.js'

/**
 * A preview URL for a file the seller picked and nothing has uploaded yet.
 *
 * Cached per file, because `URL.createObjectURL` returns a **new** URL every call:
 * one made during a render would change on the next one and make the browser
 * re-fetch a photo it already has, and the `<img>` would flicker on every
 * keystroke elsewhere in the sheet. Kept for the life of the page rather than
 * revoked, which leaks one blob URL per picked photo until the tab closes — the
 * cost of not having to track lifetimes through a dialog that can be opened,
 * cancelled and reopened.
 */
const PREVIEWS = new WeakMap()

export function previewUrl(file) {
  if (!file) return null
  if (!PREVIEWS.has(file)) PREVIEWS.set(file, URL.createObjectURL(file))
  return PREVIEWS.get(file)
}

/** The image behind one entry: what is stored, or the file waiting to be. */
function sourceOf(image) {
  return image?.url || previewUrl(image?.file)
}

/**
 * A colour's photos, as the card draws them: a short strip, nothing else.
 *
 * The card is a line in a list of colours, so this says *there are photos* rather
 * than *here they are* — up to three, the first one ringed because it is the cover.
 * The dashed box stands for a colour with none, which is a state the app marks on
 * the card too ("⚠ Add photos required") and the reason the strip is not simply
 * absent.
 */
export function ColourThumbnailStrip({ images, limit = 3 }) {
  const shown = colourImagesFor({ colour: images }, 'colour').slice(0, limit)
  const extra = colourImagesFor({ colour: images }, 'colour').length - shown.length

  if (shown.length === 0) {
    return (
      <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded-field border border-dashed border-card-edge bg-raised">
        <ImageOff className="h-4 w-4 text-muted" aria-hidden="true" />
      </span>
    )
  }

  return (
    <span className="flex shrink-0 items-center gap-1">
      {shown.map((image, index) => (
        <img
          key={image.id ?? image.url ?? image.displayOrder}
          src={sourceOf(image)}
          alt=""
          className={`h-12 w-12 rounded-field border object-cover ${
            index === 0 ? 'border-clay' : 'border-hairline'
          }`}
        />
      ))}
      {extra > 0 && <span className="num text-xs text-muted">+{extra}</span>}
    </span>
  )
}

/**
 * A colour's photos, as its sheet draws them: the whole gallery, editable.
 *
 * Index 0 is labelled **Main** because that is what it is — the app's sheet badges
 * it the same way, the card's cover is the first photo with a URL, and a customer's
 * colour swatch reads it. There is no reorder control for the same reason the app
 * has none: removing the cover promotes the next photo, which is the only reorder a
 * seller actually needs.
 *
 * The X on a stored photo is **not** a draft change — `onRemoveStored` deletes the
 * row and the object immediately, which is the app's behaviour too
 * (`removeColorImage`). A pending file is just dropped from the draft, because
 * nothing has been written yet.
 */
export function ColourPhotoGrid({ images, onAdd, onRemoveStored, onRemovePending, disabled = false }) {
  const shown = colourImagesFor({ colour: images }, 'colour')
  const remaining = Math.max(0, MAX_COLOUR_IMAGES - shown.length)

  return (
    <div className="space-y-2.5">
      {shown.length === 0 ? (
        <p className="rounded-field border border-crimson/30 bg-crimson/[0.07] px-3 py-2 text-xs leading-relaxed text-ink">
          This colour needs at least one photo — a customer picks a colour by its
          picture.
        </p>
      ) : (
        <ul className="flex flex-wrap gap-2">
          {shown.map((image, index) => (
            <li
              key={image.id ?? image.url ?? image.displayOrder}
              className={`group relative h-20 w-20 overflow-hidden rounded-field border ${
                index === 0 ? 'border-clay' : 'border-hairline'
              }`}
            >
              <img src={sourceOf(image)} alt="" className="h-full w-full object-cover" />
              <button
                type="button"
                disabled={disabled}
                onClick={() =>
                  image.url && !image.file
                    ? onRemoveStored?.(index, image)
                    : onRemovePending?.(index)
                }
                aria-label={`Remove photo ${index + 1}`}
                className="absolute right-1 top-1 inline-flex h-5 w-5 items-center justify-center rounded-full bg-chrome/85 text-white transition-opacity duration-200 ease-out-cubic focus-visible:opacity-100 md:opacity-0 md:group-hover:opacity-100"
              >
                <X className="h-3 w-3" aria-hidden="true" />
              </button>
              {index === 0 && (
                <span className="absolute inset-x-0 bottom-0 bg-clay/90 py-0.5 text-center text-[10px] font-semibold uppercase tracking-wide text-ink-inverse">
                  Main
                </span>
              )}
            </li>
          ))}
        </ul>
      )}

      <label
        className={`btn btn-outline w-full cursor-pointer ${
          remaining === 0 ? 'pointer-events-none opacity-50' : ''
        }`}
      >
        <Plus className="h-4 w-4" aria-hidden="true" />
        {remaining === 0 ? `${MAX_COLOUR_IMAGES} photos is the most` : 'Add a photo'}
        <input
          type="file"
          accept="image/*"
          multiple
          className="sr-only"
          disabled={disabled || remaining === 0}
          onChange={(event) => {
            const picked = [...(event.target.files ?? [])]
            event.target.value = ''
            // The app's own cap behaviour: it takes as many as are left
            // (`picked.take(remaining)`) rather than refusing the whole pick.
            onAdd?.(picked.slice(0, remaining))
          }}
        />
      </label>
    </div>
  )
}
