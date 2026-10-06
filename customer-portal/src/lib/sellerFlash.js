/**
 * What the corner card says after a product is saved.
 *
 * A pure rule, in `lib/` like every other one, because the two sentences are a
 * decision about what the seller is told rather than about where the card is
 * drawn — and the wording is the only part of the confirmation that can be
 * wrong.
 *
 * ## Where the seller is when they read it
 *
 * On their products page. A save navigates there, and the card rides along
 * because the shell owns it rather than the form. That is what the wording
 * assumes: there is no "view your products" button or sentence, because the
 * products are behind the card — pointing at the page the seller is looking at
 * is a sentence that spends itself saying nothing.
 *
 * ## Two sentences, and the difference is which half of the job is left
 *
 * A **created** product is saved and has no photos: the form cannot upload one
 * before the row exists, so its card names the one thing still missing and where
 * to do it. An **updated** product is done, and its card says so and stops.
 *
 * ## Why neither card says "live on the storefront"
 *
 * Because that would be false for a product with nothing in stock. The
 * storefront drops any product whose total stock is zero — the same rule that
 * hides a sold-out pair — and the form says so before the save, in its own note.
 * A toast that promised visibility would be the one place in the portal that
 * disagreed with `purchasableProducts`, and it would disagree precisely when the
 * seller had just been warned. So the cards stay honest about what they know: the
 * write landed.
 */
export function productSavedFlash({ created, name }) {
  const label = String(name ?? '').trim() || 'Your product'

  return created
    ? {
        title: 'Product added',
        message: `${label} is saved. Open it to add its photos.`,
      }
    : {
        title: 'Product updated',
        message: `${label} is saved.`,
      }
}
