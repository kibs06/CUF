/**
 * The product row's right-click menu, with the one prompt it can open wired in.
 *
 * ## Why the surface does not call `useContextMenu` itself any more
 *
 * The *items* live in `sellerRowMenus.js` so both views of the catalogue say the
 * same thing about the same product. One of those items — **Request a 3D model** —
 * is an action rather than a link, because the thing it opens is a sentence
 * before it is a download (`modelRequestAppPrompt`), and opening a dialog is
 * state: it belongs to the surface, not to a module of data. Two surfaces draw a
 * product row (`ProductGridCard`, `ProductListRow`), so wiring that state at each
 * of them is how a menu ends up full in one view and missing an item in the
 * other — the exact drift the items module exists to prevent. The hook is the
 * whole of "what a product row offers", at both call sites, in one line.
 *
 * ## What the prompt is, and why it is not a link
 *
 * A model request is filed in the app — the seller measures the pair with a tape
 * there and the app is where the request's status lives — so the item is honest
 * about being a door rather than pretending to be the room. Dropping the seller
 * straight onto a GitHub releases page from an item labelled *Request a 3D
 * model* would be a non-sequitur at the moment of the click; the prompt is the
 * sentence that connects the two. Same shape as the **Try On in AR** prompt, down
 * to `ConfirmDialog`'s `confirmHref`, so the download is a real anchor and
 * middle-click still works.
 *
 * @param {object} product The row's product, as the list has it.
 * @returns {{ onContextMenu: Function, menu: object }} Spread the handler on the
 *          row and render `menu` beside it — menu and prompt in one element.
 */
import { useState } from 'react'

import ConfirmDialog from '../ui/ConfirmDialog.jsx'
import { useContextMenu } from '../ui/ContextMenu.jsx'
import { APP_DOWNLOAD_URL, modelRequestAppPrompt } from '../../lib/appDownload.js'
import { productRowMenuItems, productRowPath } from './sellerRowMenus.js'

export function useProductRowMenu(product) {
  const [requestOpen, setRequestOpen] = useState(false)

  const { onContextMenu, menu } = useContextMenu({
    items: productRowMenuItems(product, {
      onRequestModel: () => setRequestOpen(true),
    }),
    link: productRowPath(product),
    label: product.name,
  })

  return {
    onContextMenu,
    menu: (
      <>
        {/*
          The menu closes itself as the item is chosen and this opens in the same
          click, so the menu is never behind the dialog: `ContextMenu` dismisses
          on select, and both updates land in one render.
        */}
        {menu}
        <ConfirmDialog
          open={requestOpen}
          {...modelRequestAppPrompt()}
          tone="primary"
          confirmHref={APP_DOWNLOAD_URL}
          onConfirm={() => setRequestOpen(false)}
          onClose={() => setRequestOpen(false)}
        />
      </>
    ),
  }
}

export default useProductRowMenu
