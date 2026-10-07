import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate, useOutletContext, useParams } from 'react-router-dom'
import { AlertTriangle, ArrowLeft, ImageOff, Loader2, Trash2, Upload } from 'lucide-react'

import Chip from '../../components/ui/Chip.jsx'
import ConfirmDialog from '../../components/ui/ConfirmDialog.jsx'
import Field from '../../components/ui/Field.jsx'
import CustomisationEditor from '../../components/seller/CustomisationEditor.jsx'
import { PhotoOrderGrid } from '../../components/seller/PhotoOrderGrid.jsx'
import TagPicker from '../../components/seller/TagPicker.jsx'
import VariantEditor from '../../components/seller/VariantEditor.jsx'
import {
  SellerPageBody,
  SellerPageHeader,
  SellerSection,
} from '../../components/seller/SellerPage.jsx'
import { PRODUCT_CATEGORIES, formatCurrency, formatDate } from '../../lib/constants.js'
import {
  previewUrl,
  screenPickedPhotos,
  stagedPhotoKey,
} from '../../lib/photoFiles.js'
import { salePreview } from '../../lib/pricing.js'
import {
  PRODUCT_AUDIENCE_OPTIONS,
  audienceSizeMismatch,
} from '../../lib/productAudience.js'
import { customizationsFromProduct } from '../../lib/productCustomizations.js'
import {
  emptyProductDraft,
  productColumnsFromDraft,
  productDraftFrom,
  productProblems,
} from '../../lib/productDraft.js'
import { productSavePlan } from '../../lib/productSavePlan.js'
import {
  coloursFromVariants,
  variantsFromProduct,
} from '../../lib/productVariants.js'
import { productSavedFlash } from '../../lib/sellerFlash.js'
import {
  useCreateSellerProduct,
  useDeleteSellerProduct,
  useRemoveAllProductImages,
  useRemoveColourImage,
  useRemoveProductImage,
  useSaveProductColourImages,
  useSaveProductImageOrder,
  useSaveProductCustomizations,
  useSaveProductVariants,
  useSellerProduct,
  useUpdateSellerProduct,
  useUploadProductImages,
} from '../../hooks/useSeller.js'
import { useSellerFlash } from '../../hooks/useSellerFlash.jsx'

/**
 * Create or edit one product.
 *
 * One page for both, keyed on the route: `/seller/products/new` creates and
 * `/seller/products/:productId` edits. Two pages would be the same form twice,
 * and the two would drift on exactly the things that must not differ — the
 * validation, the category list and the stock editor.
 *
 * ## Every field the app can set, and which rules are whose
 *
 * The form itself decides nothing. `productProblems` is asked what is wrong and
 * every rule in it comes from the module that owns that field: the sale rules
 * from `pricing.js` (the same file the storefront prices from), the tags from
 * `productTags.js` (the same vocabulary the app's selector writes), the audience
 * from `productAudience.js`, the sizes and colours from `productVariants.js`.
 * That is the point of the arrangement — a form that decided for itself what a
 * sale price is would be a second opinion about money.
 *
 * ## Five writes, one button
 *
 * Save writes the product row, then its own photos, then `product_variants` +
 * `inventory`, then `product_customizations`, then the colours' photo galleries —
 * `createProduct`'s order, and the order matters: the row is what the other tables
 * resolve ownership through, so a new product has to exist before its photos and its
 * sizes can. A failure part-way leaves a product with no sizes rather than a product
 * nobody can buy, and the caption under the button says so.
 *
 * The product's own photos are the exception to "uploads live in their own section",
 * and they are *staged* for exactly that reason: a seller picks them while filling
 * the form in (`NewProductPhotos` holds the Files, previews and all) and the same
 * save that creates the row sends them. So a photo is a field on this form like any
 * other rather than a second visit to the product — the app's own arrangement, which
 * has always put picked files in `_imageItems` and uploaded them from `createProduct`.
 * The colour photos are the other exception: they are *part of* a colour
 * (`ColourDialog` will not save one without a photo), so they travel with the sizes
 * that colour owns.
 *
 * ## What a successful save says, and where it leaves the seller
 *
 * A confirmation card in the corner of the shell (`useSellerFlash`), and then
 * straight to the products list — the same destination for a create and an edit.
 * The card rides along because the shell owns it rather than this form: a card
 * raised here would be unmounted by the very save that raised it.
 *
 * Creating used to land on the new product's own page, because the photo section is
 * the one thing this form could not do before the row existed. It can now: the picked
 * files are held here and uploaded by the create itself, so a save always ends on the
 * list, and the card names the photos only when the seller picked none.
 *
 * ## A save that creates the row and then fails
 *
 * The new id is kept (`createdId`) and the next Save **updates** that product instead
 * of creating a second one — which is what the button says, and what stops an upload
 * failure (the likeliest failure here) from leaving two half-built products behind.
 * Photos are dropped from the draft as they land, so a retry cannot send the same file
 * twice, and the next batch's `display_order` carries on behind them. Both rules are
 * `productSavePlan`'s rather than this form's, and that is where the reasoning lives.
 */

export default function SellerProductForm() {
  const { productId } = useParams()
  const navigate = useNavigate()
  const { store } = useOutletContext()
  const storeId = store?.id ?? null

  const isNew = !productId
  const productQuery = useSellerProduct(isNew ? null : productId)
  const product = productQuery.data ?? null

  const { flash } = useSellerFlash()
  const createMutation = useCreateSellerProduct(storeId)
  const updateMutation = useUpdateSellerProduct(storeId)
  const variantMutation = useSaveProductVariants(storeId)
  const uploadMutation = useUploadProductImages(storeId)
  const customizationMutation = useSaveProductCustomizations(storeId)
  const colourImageMutation = useSaveProductColourImages(storeId)
  const removeColourImageMutation = useRemoveColourImage(storeId)
  const deleteMutation = useDeleteSellerProduct(storeId)

  /*
    A new product's photos, held as Files rather than rows: nothing can be uploaded
    until the product exists to own the object, so the seller's pick is staged here
    and sent by the same save that creates the row (see `NewProductPhotos`).
  */
  const [galleryPhotos, setGalleryPhotos] = useState([])
  /*
    How many of them a save has already stored. The Files are dropped as they land,
    so a retry cannot upload one twice; this is only what the next batch's
    `display_order` — and therefore the cover — is counted from.
  */
  const [photosStored, setPhotosStored] = useState(0)
  /*
    The id of a row an earlier save created before it failed, so the next Save
    finishes THAT product instead of creating a second one.
  */
  const [createdId, setCreatedId] = useState(null)
  const [draft, setDraft] = useState(emptyProductDraft)
  const [variants, setVariants] = useState([])
  const [colours, setColours] = useState([])
  /* Each colour's photos, keyed by the colour's name — the table's own key. */
  const [colourImages, setColourImages] = useState({})
  const [customizations, setCustomizations] = useState([])
  /*
    Two kinds of failure, kept apart. `serverError` is a write that came back
    with something to say; `attempted` turns the draft's own blocking errors on.
    They are separate because the draft's errors are LIVE — computed from what is
    typed — and a blank form would open wearing "give the product a name" before
    its seller has had a chance to type.
  */
  const [serverError, setServerError] = useState(null)
  const [attempted, setAttempted] = useState(false)
  const hydrated = useRef(null)

  /*
    Hydrate once per product id. Keyed on the id rather than on the query's
    `data` object, because a refetch hands back a new object identity for the
    same row — and re-hydrating on that would throw away whatever the seller had
    typed since the last save.
  */
  useEffect(() => {
    if (isNew || !product || hydrated.current === product.id) return
    hydrated.current = product.id
    setDraft(productDraftFrom(product))
    const rows = variantsFromProduct(product.variants)
    setVariants(rows)
    setColours(coloursFromVariants(rows))
    setColourImages(product.colourImages ?? {})
    setCustomizations(customizationsFromProduct(product.customizations))
  }, [isNew, product])

  const set = (field) => (value) => setDraft((current) => ({ ...current, [field]: value }))

  /*
    The columns the row would be written with. Built once per render and used for
    two things: the sale preview above and the save below — so what the seller is
    told they will get is computed from the payload that will actually be sent,
    not from the fields beside it.
  */
  const columns = productColumnsFromDraft(draft)
  const problems = productProblems({
    draft,
    variants,
    colours,
    colourImages,
    customizations,
  })
  const audienceMismatch = audienceSizeMismatch({
    audience: draft.audience,
    sizes: variants.map((row) => row.size),
  })

  const saving =
    createMutation.isPending ||
    updateMutation.isPending ||
    uploadMutation.isPending ||
    variantMutation.isPending ||
    customizationMutation.isPending ||
    colourImageMutation.isPending

  const onSave = async (event) => {
    event.preventDefault()
    setServerError(null)
    setAttempted(true)

    if (problems.errors.length > 0) return

    /*
      Which row this save writes and which photos it sends. Both rules live in
      `productSavePlan`, the second one included: a create that failed after its row
      landed is finished by the next save rather than duplicated, and the batch of
      photos sent is only what is still pending, counted behind what already landed.
    */
    const plan = productSavePlan({
      productId,
      createdId,
      photos: galleryPhotos,
      photosStored,
    })
    let id = plan.id

    try {
      if (plan.row === 'create') {
        const created = await createMutation.mutateAsync(draft)
        id = created.id
        setCreatedId(id)
      } else {
        await updateMutation.mutateAsync({ productId: id, patch: columns })
      }

      /*
        The product's own photos, right after the row — `createProduct`'s image step,
        and the reason it can be done here at all: an object's path and its
        `product_id` resolve through the row, so the row goes first and the files
        follow in the same save. First of the rest because an upload is the slowest
        write here and the one thing the seller would have to re-pick by hand.
      */
      if (plan.photos.length > 0) {
        await uploadMutation.mutateAsync({
          productId: id,
          files: plan.photos,
          startOrder: plan.photoStartOrder,
        })
        setPhotosStored(plan.photoCount)
        setGalleryPhotos([])
      }

      await variantMutation.mutateAsync({ productId: id, variants })
      await customizationMutation.mutateAsync({
        productId: id,
        customizations,
      })
      // Only when there is something to write: a product with no colours, or with
      // colours whose photos are already stored, has no work to do here — and the
      // write deletes and re-inserts the whole set, so calling it needlessly is a
      // delete and re-insert of rows that were already right.
      if (Object.keys(colourImages).length > 0) {
        await colourImageMutation.mutateAsync({ productId: id, colourImages })
      }

      /*
        The card, then straight to the products list — one destination for both
        writes, so a save always ends in the same place. The card survives the
        move because the shell owns it rather than this form (see
        `SellerFlashProvider`), which is why it is raised here and not by the
        page it lands on.

        The name is the one that was written, not the one in the box: a card
        that quoted whitespace the save had just trimmed would be the only
        surface still showing it.

        `replace` rather than a push. On a create that history entry is `/new`,
        and leaving it behind is a Back press into a blank form that would
        happily create the pair a second time.
      */
      flash(
        productSavedFlash({
          created: isNew,
          name: columns.name,
          photos: plan.photoCount,
        }),
      )
      navigate('/seller/products', { replace: true })
    } catch (failure) {
      setServerError(
        /*
          With a row in place, the failure's own message is not the honest sentence:
          what the seller needs to know is that the product exists, that the save is
          unfinished, and that saving again finishes it rather than making another.
        */
        id && !productId
          ? `${columns.name} is saved, but the rest of the save did not finish. ` +
            'Save again to finish it — this updates that product rather than creating a second one.'
          : failure?.message ?? 'We could not save this product.',
      )
    }
  }

  const onDelete = async () => {
    setServerError(null)
    try {
      await deleteMutation.mutateAsync(productId)
      navigate('/seller/products', { replace: true })
    } catch (failure) {
      setServerError(failure?.message ?? 'We could not delete this product.')
    }
  }

  if (!isNew && productQuery.isLoading) {
    return (
      <SellerPageBody>
        <div className="shimmer h-96 rounded-premium" />
      </SellerPageBody>
    )
  }

  if (!isNew && !productQuery.isLoading && !product) {
    return (
      <SellerPageBody>
        <SellerSection title="We could not find that product">
          <p className="text-sm text-muted">
            It may have been deleted, or it may belong to another store.
          </p>
          <Link to="/seller/products" className="btn btn-outline mt-4">
            Back to products
          </Link>
        </SellerSection>
      </SellerPageBody>
    )
  }

  return (
    <SellerPageBody>
      <div>
        <Link
          to="/seller/products"
          className="inline-flex items-center gap-1.5 text-sm font-medium text-muted transition-colors duration-200 ease-out-cubic hover:text-ink"
        >
          <ArrowLeft className="h-4 w-4" aria-hidden="true" />
          All products
        </Link>

        <div className="mt-4">
          <SellerPageHeader
            title={isNew ? 'New product' : product?.name || 'Edit product'}
            description={
              isNew
                ? 'Everything the app can set: the details, a sale, how customers find it, and what you have in stock.'
                : 'Changes go live on the storefront as soon as you save.'
            }
          />
        </div>
      </div>

      {attempted && problems.errors.length > 0 && (
        <div
          role="alert"
          className="rounded-field border border-crimson/30 bg-crimson/[0.07] px-4 py-3 text-sm text-ink"
        >
          <p className="font-medium">
            {problems.errors.length === 1
              ? 'One thing needs fixing before this can be saved:'
              : `${problems.errors.length} things need fixing before this can be saved:`}
          </p>
          <ul className="mt-2 list-disc space-y-1 pl-5">
            {problems.errors.map((message) => (
              <li key={message}>{message}</li>
            ))}
          </ul>
        </div>
      )}

      {serverError && (
        <div
          role="alert"
          className="rounded-field border border-crimson/30 bg-crimson/[0.07] px-4 py-3 text-sm text-ink"
        >
          {serverError}
        </div>
      )}

      <form onSubmit={onSave} className="grid gap-6 lg:grid-cols-[1.4fr_1fr]">
        <div className="flex flex-col gap-6">
          <SellerSection title="Details">
            <div className="space-y-5">
              <Field
                id="product-name"
                label="Name"
                value={draft.name}
                onChange={set('name')}
                required
                placeholder="Barong leather slip-on"
              />

              <div className="grid gap-5 sm:grid-cols-2">
                <Field
                  id="product-price"
                  label="Price (₱)"
                  type="number"
                  value={draft.price}
                  onChange={set('price')}
                  required
                  placeholder="1450"
                  min="0"
                  step="0.01"
                  hint="The regular price. A sale never changes it."
                />

                <Field id="product-category" label="Category" required>
                  <select
                    id="product-category"
                    value={draft.category}
                    onChange={(event) => set('category')(event.target.value)}
                    className="mt-2 h-11 w-full rounded-field border border-hairline bg-raised px-4 text-sm text-ink transition-colors duration-200 ease-out-cubic hover:border-card-edge focus:border-clay"
                  >
                    {PRODUCT_CATEGORIES.map((value) => (
                      <option key={value} value={value}>
                        {value}
                      </option>
                    ))}
                  </select>
                </Field>
              </div>

              <Field id="product-description" label="Description">
                <textarea
                  id="product-description"
                  value={draft.description}
                  onChange={(event) => set('description')(event.target.value)}
                  rows={5}
                  placeholder="What it is made of, how it fits, who made it."
                  className="mt-2 w-full rounded-field border border-hairline bg-raised px-4 py-3 text-sm leading-relaxed text-ink transition-colors duration-200 ease-out-cubic placeholder:text-muted/60 hover:border-card-edge focus:border-clay"
                />
              </Field>

              <div className="grid gap-5 sm:grid-cols-2">
                <Field
                  id="product-sku"
                  label="SKU"
                  value={draft.sku}
                  onChange={set('sku')}
                  placeholder="Optional — your own code"
                  hint="Only you see this. It is searchable on the products page."
                />

                <Field
                  id="product-collection"
                  label="Collection"
                  value={draft.collection}
                  onChange={set('collection')}
                  placeholder="e.g. Heritage"
                  hint="Optional — a line or season. Customers can search it."
                />
              </div>

              <Field
                id="product-barcode"
                label="Barcode"
                value={draft.barcode}
                onChange={set('barcode')}
                placeholder="e.g. EAN-13, UPC-A, or a QR code value"
                hint="Optional — scanned at the counter in the CUFMAI app."
              />
            </div>
          </SellerSection>

          <SellerSection
            title="Sale"
            description="A sale price is a second price, not a replacement: the regular price stays as it is and customers see it struck through."
          >
            <div className="space-y-5">
              <Field
                id="product-sale-price"
                label="Sale price (₱)"
                type="number"
                value={draft.sale_price}
                onChange={set('sale_price')}
                min="0"
                step="0.01"
                placeholder="Leave empty for no sale"
                hint="Must be below the regular price. Customer-visible the moment it is saved."
              />

              <div className="grid gap-5 sm:grid-cols-2">
                <Field
                  id="product-sale-starts"
                  label="Starts"
                  type="date"
                  value={draft.sale_starts_at}
                  onChange={set('sale_starts_at')}
                  hint="Empty starts it now"
                />
                <Field
                  id="product-sale-ends"
                  label="Ends"
                  type="date"
                  value={draft.sale_ends_at}
                  onChange={set('sale_ends_at')}
                  hint="Empty runs until you stop it"
                />
              </div>

              {(draft.sale_starts_at || draft.sale_ends_at) && (
                <button
                  type="button"
                  onClick={() =>
                    setDraft((current) => ({
                      ...current,
                      sale_starts_at: '',
                      sale_ends_at: '',
                    }))
                  }
                  className="text-xs font-semibold text-muted underline-offset-4 hover:text-crimson hover:underline"
                >
                  Clear the sale dates
                </button>
              )}

              {/*
                The line is built from the columns that would be written, so it
                cannot drift from what the storefront will do — see `salePreview`.
              */}
              <p className="rounded-field border border-hairline bg-subtle/50 px-4 py-3 text-sm text-ink">
                {/*
                  Built from `columns` — the payload that would actually be
                  written — through the storefront's own reader, so the sentence
                  cannot disagree with the price a customer is charged.
                */}
                {salePreview(columns, {
                  money: formatCurrency,
                  date: formatDate,
                })}
              </p>
            </div>
          </SellerSection>

          <SellerSection
            title="Tags"
            description="How customers find this pair in search. Pick from each group, or type your own."
          >
            <TagPicker
              entries={draft.tags}
              onChange={(tags) => set('tags')(tags)}
              disabled={saving}
            />
          </SellerSection>

          <SellerSection
            title="Audience and visibility"
            description="Who the pair is for, and whether it is in the shop."
          >
            <div className="space-y-5">
              <div>
                <p className="text-xs font-semibold uppercase tracking-[0.08em] text-muted">
                  Audience
                </p>
                <div className="mt-2.5 flex flex-wrap gap-2">
                  {PRODUCT_AUDIENCE_OPTIONS.map((option) => (
                    <Chip
                      key={option.value}
                      label={option.label}
                      selected={draft.audience === option.value}
                      disabled={saving}
                      onClick={() =>
                        set('audience')(
                          draft.audience === option.value ? null : option.value,
                        )
                      }
                    />
                  ))}
                  {/* Last, so clearing reads as "none of the above". */}
                  <Chip
                    label="Not set"
                    selected={draft.audience === null}
                    disabled={saving}
                    onClick={() => set('audience')(null)}
                  />
                </div>
                <p className="mt-2 text-xs leading-relaxed text-muted">
                  Men&rsquo;s / Women&rsquo;s / Kids&rsquo; decide which size chart a
                  customer reads this pair on. Unisex is a real answer — it just
                  does not appear on any of the audience rows in the app.
                </p>
                {audienceMismatch && (
                  <p className="mt-2 rounded-field border border-amber/30 bg-amber/[0.10] px-3 py-2 text-xs leading-relaxed text-ink">
                    These sizes look like adult sizing — check the audience is
                    right. Nothing is blocked; this is only a note.
                  </p>
                )}
              </div>

              {/*
                A checkbox rather than the portal's `Switch`, which is right here
                for the reason it was wrong on the product list: this is a field in
                a draft with a Save button under it, and a switch promises the
                change is already in effect.
              */}
              <label className="flex items-start gap-3 rounded-field border border-hairline bg-subtle/50 px-4 py-3">
                <input
                  type="checkbox"
                  checked={draft.is_published}
                  onChange={(event) => set('is_published')(event.target.checked)}
                  className="mt-0.5 h-4 w-4 rounded border-hairline accent-clay"
                />
                <span className="text-sm">
                  <span className="font-medium text-ink">
                    Show on the storefront
                  </span>
                  <span className="mt-0.5 block text-xs leading-relaxed text-muted">
                    Unchecked keeps the product and its photos, and takes it out
                    of the shop.
                  </span>
                </span>
              </label>

              <label className="flex items-start gap-3 rounded-field border border-hairline bg-subtle/50 px-4 py-3">
                <input
                  type="checkbox"
                  checked={draft.is_featured}
                  onChange={(event) => set('is_featured')(event.target.checked)}
                  className="mt-0.5 h-4 w-4 rounded border-hairline accent-clay"
                />
                <span className="text-sm">
                  <span className="font-medium text-ink">Featured</span>
                  <span className="mt-0.5 block text-xs leading-relaxed text-muted">
                    Worth a place on the app&rsquo;s home page. Standing out
                    elsewhere is not what this does — it is a flag the customer
                    app reads, and the website does not draw it yet.
                  </span>
                </span>
              </label>
            </div>
          </SellerSection>

          <SellerSection
            title="Sizes and variants"
            description="A colour holds a product's sizes and their stock, so this is a card per colour: open one to give it a name, its photos, and the sizes it comes in. What is written here is what the customer's size grid and the checkout read."
          >
            <VariantEditor
              variants={variants}
              colours={colours}
              colourImages={colourImages}
              onChange={({
                variants: nextVariants,
                colours: nextColours,
                colourImages: nextImages,
              }) => {
                setVariants(nextVariants)
                setColours(nextColours)
                setColourImages(nextImages)
              }}
              /*
                The X on a stored photo is the one edit in the form that writes
                immediately: the phone does the same (`removeColorImage`), and the
                row it removes is a row the save would otherwise have to guess
                about — a photo missing from the draft is not the same statement as
                a photo the seller deleted.
              */
              onRemoveStoredPhoto={(image) =>
                removeColourImageMutation.mutate({ imageId: image.id, url: image.url })
              }
              disabled={saving}
            />
          </SellerSection>
        </div>

        <div className="flex flex-col gap-6">
          {product ? (
            <ProductPhotos product={product} storeId={storeId} />
          ) : (
            <NewProductPhotos files={galleryPhotos} onChange={setGalleryPhotos} />
          )}

          <SellerSection
            title="Customisation options"
            description="What a customer can ask for on top of the pair — an engraving, a different sole."
          >
            <CustomisationEditor
              customizations={customizations}
              onChange={setCustomizations}
              disabled={saving}
            />
            {/*
              Honest about the half of this feature that does not exist yet: the
              app defines options and the website can now define them too, but no
              customer surface lets anyone CHOOSE one. Remove this note when one
              does.
            */}
            <p className="mt-4 border-t border-hairline-soft pt-3 text-xs leading-relaxed text-muted">
              Saved with the product, and read by the CUFMAI app. Customers cannot
              choose an option on the website yet.
            </p>
          </SellerSection>

          <SellerSection title="Save">
            {problems.notes.length > 0 && (
              <ul className="mb-4 space-y-2">
                {problems.notes.map((note) => (
                  <li
                    key={note}
                    className="rounded-field border border-amber/30 bg-amber/[0.10] px-3 py-2 text-xs leading-relaxed text-ink"
                  >
                    {note}
                  </li>
                ))}
              </ul>
            )}

            <button
              type="submit"
              disabled={saving}
              className="btn btn-primary w-full"
            >
              {saving && <Loader2 size={15} className="animate-spin" />}
              {createdId
                ? 'Finish saving'
                : isNew
                  ? 'Create product'
                  : 'Save changes'}
            </button>

            <p className="mt-3 text-xs leading-relaxed text-muted">
              Details, a sale, tags, the audience, the photos, colours and stock,
              and the options are written together, in that order — so a failure
              part-way leaves a product with no sizes rather than a product nobody
              can buy.
            </p>

            {!isNew && (
              <button
                type="button"
                onClick={onDelete}
                disabled={deleteMutation.isPending}
                className="mt-5 inline-flex w-full items-center justify-center gap-2 text-xs font-semibold text-muted underline-offset-4 transition-colors duration-200 ease-out-cubic hover:text-crimson hover:underline"
              >
                <Trash2 className="h-3.5 w-3.5" aria-hidden="true" />
                Delete this product
              </button>
            )}
          </SellerSection>
        </div>
      </form>
    </SellerPageBody>
  )
}

/**
 * A new product's photos — the pick, before there is a product to hold it.
 *
 * The row has to come first and that is not an arrangement this card can change:
 * the object's path opens `{sellerId}/{productId}/…`, the bucket's INSERT policy
 * reads the seller's id out of it, and `product_images.product_id` is a real
 * foreign key — so there is nothing to upload *to* until a row exists. What this
 * card changes is what that requirement costs the seller: the files are picked and
 * held here, previewed from the browser's own blob URLs, and sent by the same save
 * that creates the row. "Add the photos" is therefore part of creating the product
 * rather than a chore waiting on the other side of a save — which is what the app
 * does with its own `_imageItems`.
 *
 * **The first photo is the cover.** It uploads at `display_order` 0 with
 * `is_primary`, and the storefront draws the lowest order first. There is no
 * reorder control for the same reason the colour galleries have none: the app has
 * none either, and taking the cover away promotes the next photo.
 *
 * A removal here is just a file dropped from a list — nothing has been written yet,
 * which is why there is no confirmation and no server call (compare the X on a
 * stored photo in `ProductPhotos`, which deletes a row and an object).
 *
 * HEIC files are screened out before they ever reach the list, with the reason shown
 * beside the button that took them — see `photoFiles.js` for why this portal, unlike
 * the app, has to refuse them itself.
 */
function NewProductPhotos({ files, onChange }) {
  const [refused, setRefused] = useState(null)

  /*
    A pending file's identity is the File object itself, and its preview is a blob
    URL — both cached per file in `photoFiles.js`, so a drag can move a tile
    without the `<img>` being handed a new URL or a new React key.
  */
  const items = files.map((file) => ({
    key: stagedPhotoKey(file),
    src: previewUrl(file),
    value: file,
  }))

  return (
    <SellerSection
      title="Photos"
      description="Uploaded with the product when you save it. Drag one to change the order customers see it in — the first is the cover."
    >
      <div className="space-y-4">
        {files.length === 0 ? (
          <div className="flex flex-col items-center justify-center rounded-card border border-dashed border-hairline bg-subtle/40 py-8 text-center">
            <ImageOff className="h-6 w-6 text-muted" aria-hidden="true" />
            <p className="mt-2 text-xs text-muted">No photos yet.</p>
          </div>
        ) : (
          <PhotoOrderGrid
            items={items}
            onReorder={(next) => onChange(next.map((item) => item.value))}
            /* By identity, not by index: a removal that did not follow the tile
               through a reorder would delete whichever photo happens to sit at
               that position now. */
            onRemove={(item) =>
              onChange(files.filter((file) => file !== item.value))
            }
            coverLabel="Cover"
          />
        )}

        <label className="btn btn-outline w-full cursor-pointer">
          <Upload className="h-4 w-4" aria-hidden="true" />
          {files.length === 0 ? 'Add photos' : 'Add more photos'}
          <input
            type="file"
            accept="image/*"
            multiple
            className="sr-only"
            onChange={(event) => {
              const picked = [...(event.target.files ?? [])]
              event.target.value = ''
              const { accepted, notice } = screenPickedPhotos(picked)
              setRefused(notice)
              if (accepted.length > 0) onChange([...files, ...accepted])
            }}
          />
        </label>

        {refused && (
          <p
            role="status"
            className="flex items-start gap-2 rounded-field border border-crimson/30 bg-crimson/[0.07] px-3 py-2 text-xs leading-relaxed text-ink"
          >
            <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-crimson" aria-hidden="true" />
            {refused}
          </p>
        )}
      </div>
    </SellerSection>
  )
}

/**
 * Photos for an existing product.
 *
 * The upload appends rather than replaces, which is the difference that matters:
 * a seller adding their fourth photo must not lose the first three. Removing one
 * takes the object out of storage as well as the row, because a row without its
 * file is a broken image on the storefront and there is nothing to notice it by.
 * **Remove all** is the same write at the scale of the gallery — one statement,
 * behind a confirmation, because a mis-tap would otherwise take every photo with
 * it. That button belongs in the card's own header, which is why this component
 * renders the `SellerSection` rather than sitting inside one.
 *
 * The card says when a removal fails, and it used to say nothing — which is how a
 * working delete came to read as a broken button: the row and the object were
 * being deleted, but the form's own query was never told, so the tile stayed on
 * screen and a tile whose object had just gone drew as a broken image.
 *
 * **The order is a third immediate write, and the reason is the same one.**
 * `display_order` is what the storefront sorts by and draws first, so a drag is not
 * a draft field like the ones on the left of this page: it lands in the table the
 * moment the photo is dropped (`saveProductImageOrder`, one `upsert`), and `is_primary`
 * goes with it so the first tile genuinely is the cover. An order the table refuses
 * is put back on screen — keeping an arrangement nothing recorded would promise a
 * shape the shop will not draw, which is the mistake the removal above already made
 * once.
 *
 * Per-colour galleries (`product_color_images`) are deliberately not here: the
 * app requires at least one photo for every colour, and the storefront does not
 * read that table at all — it falls back to the product's own gallery when it has
 * no rows for a colour. Requiring something on the web that the web never shows
 * would block a save over a photo no customer can see.
 */
function ProductPhotos({ product, storeId }) {
  const uploadMutation = useUploadProductImages(storeId)
  const removeMutation = useRemoveProductImage(storeId)
  const removeAllMutation = useRemoveAllProductImages(storeId)
  const orderMutation = useSaveProductImageOrder(storeId)
  const [confirmingRemoveAll, setConfirmingRemoveAll] = useState(false)
  const [refused, setRefused] = useState(null)

  /*
    The rows the card draws, filtered to the ones with a URL rather than taken
    whole: a row whose object is missing would render as a broken tile, and the
    reorder write drops it anyway (`imageOrderRows` needs an id).
  */
  const serverRows = (product.imageRows ?? []).filter((row) => row.url)
  const photoCount = serverRows.length

  /*
    The order on screen. A reorder writes immediately — like the X, it is a fact
    about the rows rather than a field in a draft — so this is the table's own
    order plus whatever the seller has just done to it, and it is re-synced when
    the fetched order genuinely changes, which is also what puts it back after a
    write the database refused.
  */
  const serverOrder = serverRows.map((row) => row.id ?? row.url).join('|')
  const [rows, setRows] = useState(serverRows)
  const fetched = useRef(serverOrder)
  useEffect(() => {
    if (fetched.current === serverOrder) return
    fetched.current = serverOrder
    setRows(serverRows)
  }, [serverOrder, serverRows])

  const onReorder = (next) => {
    const previous = rows
    const reordered = next.map((item) => item.value)
    setRows(reordered)
    orderMutation.mutate(
      { productId: product.id, images: reordered },
      /* An order the table refused is not an order: leaving it on screen would
         promise a shape the storefront will not draw. */
      { onError: () => setRows(previous) },
    )
  }

  return (
    <>
      <SellerSection
        title="Photos"
        description="Drag a photo to change the order customers see it in — the first one is the cover."
        actions={
          photoCount > 0 ? (
            <button
              type="button"
              onClick={() => setConfirmingRemoveAll(true)}
              className="inline-flex items-center gap-1.5 text-xs font-semibold text-muted underline-offset-4 transition-colors duration-200 ease-out-cubic hover:text-crimson hover:underline"
            >
              <Trash2 className="h-3.5 w-3.5" aria-hidden="true" />
              Remove all
            </button>
          ) : undefined
        }
      >
        <div className="space-y-4">
          {photoCount === 0 ? (
            <div className="flex flex-col items-center justify-center rounded-card border border-dashed border-hairline bg-subtle/40 py-8 text-center">
              <ImageOff className="h-6 w-6 text-muted" aria-hidden="true" />
              <p className="mt-2 text-xs text-muted">No photos yet.</p>
            </div>
          ) : (
            <PhotoOrderGrid
              items={rows.map((row) => ({
                key: row.id ?? row.url,
                src: row.url,
                value: row,
              }))}
              onReorder={onReorder}
              onRemove={(item) =>
                removeMutation.mutate({
                  productId: product.id,
                  imageId: item.value.id,
                  url: item.value.url,
                })
              }
              disabled={orderMutation.isPending}
              coverLabel="Cover"
            />
          )}

          {orderMutation.isError && (
            <p role="alert" className="text-xs text-crimson">
              {orderMutation.error?.message
                ? `That order did not save (${orderMutation.error.message}) — the photos are back where they were.`
                : 'That order did not save — the photos are back where they were.'}
            </p>
          )}

          {removeMutation.isError && (
            <p role="alert" className="text-xs text-crimson">
              {removeMutation.error?.message ?? 'That photo could not be removed.'}
            </p>
          )}

          <label className="btn btn-outline w-full cursor-pointer">
            {uploadMutation.isPending ? (
              <Loader2 size={15} className="animate-spin" />
            ) : (
              <Upload className="h-4 w-4" aria-hidden="true" />
            )}
            {uploadMutation.isPending ? 'Uploading…' : 'Add photos'}
            <input
              type="file"
              accept="image/*"
              multiple
              className="sr-only"
              disabled={uploadMutation.isPending}
              onChange={(event) => {
                const files = [...(event.target.files ?? [])]
                event.target.value = ''
                if (files.length === 0) return
                const { accepted, notice } = screenPickedPhotos(files)
                setRefused(notice)
                if (accepted.length === 0) return
                uploadMutation.mutate({
                  productId: product.id,
                  files: accepted,
                  startOrder: product.images.length,
                })
              }}
            />
          </label>

          {refused && (
            <p
              role="status"
              className="flex items-start gap-2 rounded-field border border-crimson/30 bg-crimson/[0.07] px-3 py-2 text-xs leading-relaxed text-ink"
            >
              <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-crimson" aria-hidden="true" />
              {refused}
            </p>
          )}

          {uploadMutation.isError && (
            <p role="alert" className="text-xs text-crimson">
              {uploadMutation.error?.message ?? 'That upload did not work.'}
            </p>
          )}
        </div>
      </SellerSection>

      <ConfirmDialog
        open={confirmingRemoveAll}
        title="Remove all photos?"
        description={
          photoCount === 1
            ? 'The photo comes off this product and out of the bucket. The storefront falls back to its placeholder until you add another — this cannot be undone.'
            : `All ${photoCount} photos come off this product and out of the bucket. The storefront falls back to its placeholder until you add more — this cannot be undone.`
        }
        confirmLabel="Remove all"
        pending={removeAllMutation.isPending}
        error={removeAllMutation.error?.message ?? null}
        onConfirm={() =>
          removeAllMutation.mutate(
            { productId: product.id, urls: product.images },
            { onSuccess: () => setConfirmingRemoveAll(false) },
          )
        }
        onClose={() => setConfirmingRemoveAll(false)}
      />
    </>
  )
}
