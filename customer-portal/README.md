# CUFMAI Customer Portal

The customer-facing web storefront for the CUFMAI marketplace. React + Vite, talking to the **same Supabase project** as the Flutter app and the admin portal, with the same anon key and therefore the same Row-Level Security.

## Why this exists alongside the Flutter app

The Flutter app is the phone experience. This is the shop window: real URLs that can be pasted into a message and indexed by search engines (`/product/<id>`, `/makers/<id>`) — which a canvas-rendered app cannot offer. The two read the **same tables**, so a product published from a seller's phone appears here with no publishing step in between.

## This app serves two roles, and one `npm run dev`

It is not only a storefront any more. It also carries the **seller portal** at `/seller/*`, because the alternative — a third Vite app — would have meant a third Supabase client, a third auth context and a third copy of every role rule, to serve the same project on a second port.

One dev server, one login, and the **role decides where you land**: a seller lands on `/seller`, a customer on `/`. `SignIn` reads the role off the profile `signIn` resolves to, because asking before the sign-in would mean asking whoever is at the keyboard.

The two sides are kept apart by two gates, and they answer different questions:

| Gate | Question | Where |
|---|---|---|
| `RequireSeller` | May this account sell? | wraps `/seller/*` |
| `AppLayout` | Is this the shop? | redirects an approved seller out |

**The shop is closed to sellers.** `AppLayout` redirects an approved seller to `/seller`, and that one check closes every customer route at once — home, catalog, makers, product, cart, checkout, sign-in, account — because they all render inside that layout and the seller portal deliberately does not. The rule is enforced there rather than per page precisely so the next customer route someone adds cannot forget it.

Two details of that redirect are load-bearing. It waits for `!loading`, because the profile is unknown for the first moment of every page load and redirecting on "not yet known" would throw a signed-in customer to the sign-in page on every reload. And it applies to `isApprovedSeller` only — a `pending` or `rejected` applicant is **not** redirected, because they have no portal to be sent to (the gate shows them a waiting page) and taking the storefront away from someone whose application is still being read would leave them with nothing at all.

The consequence worth knowing: **`/settings` is closed to sellers too**, and it used to hold the portal's only sign-out button. So the seller shell has its own `/seller/account` — password, appearance, sign-out — built from the same `PasswordForm` and `ThemeChoice` components rather than a second copy of them, plus a sign-out in the seller bar's own account menu so leaving is possible from wherever a seller is.

**The seller portal wears the storefront's chrome.** `SellerHeader` is the same bar — sticky blur, hairline, 64px row, the same 7xl container, and the same current-page pill, which lives in `components/layout/navLinkClass.js` so the two bars cannot drift — with the seller's five destinations in place of Shop and Makers, the **store's name where the wordmark goes** (a seller with one shop does not need telling which portal they are in, they need reminding which storefront they are editing), and, where the shop keeps its cart and account menu, the **seller's own face**, whose panel carries **Notifications and Messages with their unread counts**. It replaced a dark 240px sidebar: the seller signed in through the same door as the customer, and a different-looking product on the other side of that door said the wrong thing. Below `lg` the nav becomes a second row inside the same sticky header and scrolls sideways rather than hiding behind a menu, because five destinations do not fit beside a phone's logo.

There is no "Account" pill in that nav, and that is the point rather than an omission: Orders and Products are places, Account is *who is signed in*, so it is the avatar — the seller's photo, or their initials on the brand brown — which opens a panel holding the account page and Sign out. `SellerAccountMenu` is the shop's `AccountMenu` with the dead rows removed; the customer one links to `/account`, `/messages` and `/settings`, every one of which `AppLayout` bounces a seller out of. What the seller bar also does **not** carry is search or a cart — both are the shop's.

### What the seller portal does and does not do

Built: a dashboard (today's figures, what is waiting on the maker, sizes running out, storefront checklist), the order queue with status transitions, products — the app's own form, colours and their photos included — with a colour/size/stock editor, customisation options and photo upload, the storefront editor, and revenue reporting.

**The products page draws the catalogue two ways, and remembers which.** *Is this the pair I meant?* is a question about the photograph; *which of these is missing a size 42?* is a question about columns — so the toolbar switches between `ProductGridCard` and `ProductListRow`, and `useProductView` keeps the choice per device (per device on purpose: a phone is not where anyone reads a chip column). Above the list, `catalogSummary` counts published, hidden and both kinds of stock trouble from the rows already fetched — no second query, so the summary cannot disagree with the list under it — and the stock figures are counted **per size**, because a product running low in one size of eight is one restock, not three. Each tile and row carries its sizes as chips (`SizeStockChips`, from `sizeStockChips`), which is the per-size answer the page used to give as a total ("3 sizes · 8 pairs" reads as healthy until you notice they are all size 39).

**Restocking does not go through the form.** `QuickStockPanel` opens under the row or tile it belongs to — a stepper per size and one Save — because restocking is the most frequent thing a seller does to a product and the least like editing one: nothing about the pair changed, the workshop just made six more size 41s, and the form would cost a navigation, a page of fields and a save that writes the name and price back over themselves. It sends the **whole** variant set (that is what `saveProductVariants` replaces) and it deliberately cannot add or remove a size — a size added there would be buyable the instant it landed, so that stays in `VariantEditor` where the seller is looking at the whole product. Nothing is written until Save, unlike the publish switch beside it: a count is typed through (3, 4, 5) and three writes for one restock is three chances to put 5 on top of 35.

**And it steps aside for a product with colours**, which is the other thing it cannot answer: it has one count per size, a two-colour product has one per size *and* colour, and the write is a set replacement — so restocking from this panel used to flatten a coloured product to a single colourless row and zero its per-variant prices and SKUs. It now says so and links to the form, the same shape as its no-sizes state.

### The product form is the app's form now

It used to write seven of the columns a product has, and the three it left out were the three the storefront already reads: a **sale** (`pricing.js` prices it, the cart charges it, the order records it), **tags** (`searchRules.js` matches them and `SearchField` suggests them) and a **collection** (`Home`'s rails). A seller who wanted a discount, or a product a customer could actually find, had to reach for the phone. The form now sets everything the app's does — sale price and window, tags, audience, featured, barcode, collection, colours with their own photos and per-variant stock, extra prices and SKUs, and customisation options — and there is nothing the phone can write that it cannot.

**It is the app's own colour flow, cards and all.** `_buildVariantsSection` draws a card per colour — cover photo, name beside its swatch, `photos · sizes · in stock`, and a warning when it has no photos — with *Add Color* underneath, and that is what the section is now. Everything that writes stock is reached from a card: the card opens `ColourDialog`, which is `_showColorSheet` (**name** from the app's own eleven presets or typed, with the duplicate refused while typing → **photos**, at least one because a customer picks a colour by its picture, the first badged *Main* → **sizes and stock**, which is not asked here but *reached* from here: *Add sizes* opens the size sheet scoped to this colour and its rows come back into the card's own list). `applyColourSheet` puts the three back together — a **rename moves the rows, the photos and the list in one go**, which is what makes the name-as-key schema safe to edit.

**And the size sheet inside it is the app's `_showVariantSheet`.** *Sizing system* (US/EU/UK, or one typed in — changing it clears the sizes, because `'42'` means EU 42) → *every size in that system*, multi-select → *a row per size* with a +/− count, an optional extra price and SKU, and *Another count for this size* for the case that needs two. The save reads what it will write — *Add 6 variants*, *Update variant* — and applying **replaces this colour's rows for the picked sizes and leaves every other colour alone**, which is the difference between "EU 42 in Tan is now 9" and "EU 42 is now Tan", and the difference between an edit and a deletion. A size this colour already stocks opens with its own counts, so it is the phone's *Edit Variant* as well.

Two smaller decisions came with it. **The uncoloured rows get a card too**, because the app cannot express them: the phone requires a colour (`'Please add at least 1 color.'`) and turns a legacy `color IS NULL` row into a nameless colour card it then refuses to save, while most of this catalog *is* one row per size with no colour — everything the portal wrote before it could express colours, and the shape the storefront's size grid reads. So they appear as a **No colour** card that opens the size sheet directly, with no name and no photos to ask for because there is nothing there to name. And the swatch dot is a port of the storefront's own mapping (`lib/utils/variant_swatch_color.dart` → `swatchRules.js`), so `Tan` is the same brown in the sheet as on a product page, with the app's branch order kept exactly: `Dark Brown` is dark, `Tan suede` is a brown, and `Carob` is its own dark brown while `Carob Brown` is not. Its one divergence is the unknown-name fallback — Dart's `String.hashCode` cannot be reproduced in JS, so an invented name hashes to a warm tone of its own instead of the phone's; what is kept is the property the app wrote it for, that a name never changes colour between renders.

**No field's rule lives in the form.** `productProblems` is asked what is wrong and every answer comes from the module that owns that field — `salePriceProblem` and `saleWindowNote` from `pricing.js` (the file the storefront prices from), `parseTags`/`serializeTags` from `productTags.js` (the app's own vocabulary, `custom:<group>:<text>` encoding included), `audienceSizeMismatch` from `productAudience.js` (whose three scales are the shopper's own `FOOT_SIZE_CATEGORIES`, spread in rather than re-spelled), the colour and size arithmetic from `productVariants.js`, the option rules from `productCustomizations.js`. It answers in two lists, and the split is the interesting part: an **error** blocks the save and is either the app's own refusal (a name, a price, a sale price that is not a discount, an option with no kind) or a shape the schema cannot hold (a barcode past the app's fifty characters, a colour column with no name) — while a **note** never blocks anything. A sale window that can never open, a Kids' audience with adult sizes, a colour with no sizes yet, every size at zero: all of those save exactly as drawn, because a form that refuses what the phone accepts is how a seller ends up unable to fix a typo in a product's name.

**Four writes, one button, in the app's order** — the row, then `product_variants` and the derived `inventory`, then `product_customizations`, then the colours' photo galleries — because the row is what the other tables resolve ownership through, so a product has to exist before its sizes can. `is_active` is **not** a field on either surface and should not be: the app re-derives it as "any stock at all" after every variant write, so a switch a seller could flip would be overwritten by the next save; the portal derives it the same way and swallows its failure the same way. A zero sale price is written as `NULL` rather than as `0` (the app writes the `0`; `isOnSale` ignores both, and only one of them is a number a later reader could mistake for a price). The sale preview under the fields is built from the payload that would actually be sent, through the storefront's own `isOnSale`/`effectivePrice` — so the sentence cannot disagree with the price a customer is charged.

**Two real bugs came out of doing this**, both older than this work. First, **`is_published` was read by nothing on any customer surface**: the form's "Show on the storefront" checkbox hid a product from the seller's own list and left it on sale to everyone, because `catalog.js` never filtered the column. It does now, in both reads. Second, the quick-restock panel described above, which flattened colours. Both were found by asking what each field is *for* — the same question that turned up the account-menu icons losing twice.

One honest limit remains on the customer side: `product_customizations` can now be written from either surface and no customer surface lets anyone **choose** an option (the app passes `customizations: null` into its own cart), so the form says as much under the section. That is a gap in the buying path, not in this form.

The per-product publish control is `components/ui/Switch.jsx`: one `<button role="switch">` with a CSS knob. The three raw `<input type="checkbox">` controls it replaced were wearing the browser's blue-grey box — this project has no `@tailwindcss/forms`, so `text-clay` on a checkbox styles nothing — and the two that remain (the product form and the storefront editor) now use `accent-clay`. They stay checkboxes because they are fields in a draft with a Save button under them; a switch promises a change that has already happened.

**Notifications and Messages open a side panel, not a page.** Clicking either alert slides a drawer in on the right of whatever the seller was already looking at — reading an order, editing a size — because *has anything come in?* is asked from inside the work, and a page navigation throws that context away and costs a back press to get it back. Both panels hold an **“open as a full page”** link in their own header, and `/seller/notifications` and `/seller/messages` still exist for exactly that reason: a notification or a thread is a thing people link to (“look at this order”), and a drawer that only exists inside a session cannot be pasted into a chat.

**The pin is the whole idea.** A panel opened once is a drawer — Escape, a click on the scrim and navigating away all close it. Pinned, it becomes a real column beside the page: the page keeps its width minus the panel's, both stay readable side by side (orders on the left, the inbox on the right) and it survives navigation, which is the only reason pinning exists. Below `lg` there is nothing to dock beside, so a pinned panel falls back to the overlay it already knows how to be — `isPanelDocked` is *open and pinned and wide enough*, and any one of the three missing gives the state that always works. **Only one form is ever mounted**: the difference is not styling but whether the panel is a flex sibling of `<main>` or a fixed layer over it, and rendering both with one hidden would mount the feed twice — two message subscriptions, two queries under one key, two composers with the same `id`. The pin and the panel are remembered in `localStorage` (`cufmai:seller-panel`), and the **panel is only remembered while pinned**: restoring an unpinned drawer is the site reopening something a seller closed.

**The width is the seller's, and the ceiling is the window's.** The grab is a `role="separator"` splitter on the panel's inner edge — ARIA's window splitter, which is what this is: a boundary, not an action, so it is not a `button` and it announces its own value. A pointer drags it, ArrowLeft/ArrowRight move it a rem at a time, Home/End jump to the two ends, and the chevrons in the header expand it to the widest this window allows and put it back. Every path ends at the same wall, and the words *with limitations* are that wall: **16rem is the floor** (the width at which a notification card is still a card), **40rem is the ceiling nobody gets past**, and the window gets its own say — **55% of it docked**, because there is a page beside the panel that has to stay readable, and **92% over the page**, because the 8% left showing is what stops a drawer from turning into a navigation. `panelMaxRem` owns those; `clampPanelWidth` owns the walls.

Three details make that hold together. **The seller's width and the ceiling are two separate facts** — expanding is not "set it to 40rem", so a seller who expanded and collapsed gets their own width back rather than a guess at it. **The ceiling is applied when the panel is drawn, never when it is saved**, so a width chosen on a big screen is not a number that breaks a small one, and shrinking the window and growing it back gives the width back instead of the floor. And **a drag is drawn from local state in `SellerSidePanel`**, committing once on release: a pointer move fires dozens of times a second, the width lives in the shell's provider, and committing per move would re-render thirty notification cards per frame — while leaving the `children` element untouched lets React skip that subtree entirely until the drop.

**The way in is the account menu, and it is the only way in.** Notifications and Messages are the avatar panel's first two rows, each with its unread count, each a `button` rather than a link because nothing about them changes the URL — clicking one twice closes the panel, and the region id is derived from the panel's own id so the row can name it with `aria-controls` without either component knowing the other. **Icon buttons in the bar were tried twice and taken out twice**: beside five pills and a 40px face on a 64px row, a bell and an inbox are two more 40px circles whose meaning is a tooltip, and both of them say the same thing — someone is waiting on you — in two shapes. The menu is one click away from every page, and the two counts are the first thing in it. Neither row is a pill and neither is in the bar's nav list: **a count is not a destination**, and the bar already lists every place to go. Both counts are server-side `HEAD` counts behind the store query, so a store-less seller asks for nothing.

**And the sum of them is on the face.** A menu whose counts are only drawn inside it has to be opened to find out whether it is worth opening, so the seller's only way to learn that an order had arrived was to go looking for one — and because the panel is what mounts the queries, a badge inside it could only ever move while someone was already looking at it. So the avatar carries a badge of its own whenever anything is unread, and it is **notifications + threads**, not either half: the question a 40px face can answer at a glance is *is anything waiting on me*, and which kind is what the two rows answer the moment the panel opens. That is not a third control and it is not a bell — those lost twice — it is the same face with a number on its corner, so nothing was added to a row that was already full. The number is read **at the button** (see `SellerAccountMenu`), which is what makes it exist on every seller page and what gives `SellerRealtime`'s invalidation something mounted to redraw. `badgeRules.js` owns the arithmetic — including that a half-loaded pair still draws the half that arrived — and `CountBadge` owns the three rules that have to be identical in all four places a badge is drawn: zero draws nothing, `99+` is the cap, and the number is announced exactly once (on the avatar by the button's own `aria-label`, which carries the *true* figure, since the cap is a drawing decision). On the rows it is spelled out instead — "28 unread notifications" — because there the digit is the only place the meaning is written.

**A panel is an `<aside>`, not a modal.** Escape closes it and a click outside closes it, but focus is not trapped inside it, and calling it `aria-modal` would promise a screen reader something it does not do. Focus *is* moved into the panel on open so the next Tab walks its controls rather than the page behind it; nothing is handed back on close, because two controls can open it and guessing which one gets focus is worse than leaving it where the panel was. The panel sits **outside** `<main>`, so a page that throws does not take the seller's inbox with it, and the realtime channels live in the shell (`SellerRealtime`) rather than in the badge hooks — three components now draw those two numbers, and one channel per hook would be three channels invalidating the same two keys.

**Notifications are realtime here, and the customer's are not.** `notifications` was never added to the `supabase_realtime` publication, so the customer's feed refetches on focus instead — subscribing to an unpublished table gives a subscription that silently never fires, which is worse than none. `seller_notifications` *was* published in its own migration, so these badges subscribe for real — in `SellerRealtime`, the one component of the shell that is on every seller page — and one channel invalidates both the badge and the feed, so a count can never disagree with the list it badges. The feed's types are the app's five (`new_order`, `stale_order`, `low_stock`, `custom_order_request`, `new_message`), and a type this build has never heard of is drawn with a label made from its own value rather than dropped: the column's original CHECK lists four of the five, so unknown rows are a real possibility and a missing notification is a seller not being told something. Cards link by type — an order, the product whose size is running out, the thread — and a `custom_order_request` is deliberately inert, because the screen it opens in the app has no equivalent here.

**The seller's inbox is the other half of the same tables.** It reads `conversations` by `store_id` and takes the name from `conversations.customer_name`, denormalised onto the thread by a trigger because profiles RLS made the seller's join return nothing; unread means the customer's messages, so `fetchUnreadCountsByConversation` takes the counted side as an argument rather than hard-coding the maker's. Replying is allowed — the INSERT policy is keyed on `sender_type = 'seller'` — so the thread has a composer, and reading marks the customer's messages read through `mark_conversation_read(convo_id, 'seller')`, never a table UPDATE (there is no UPDATE policy on `messages`, and an update that matches nothing returns `200 OK`). `lib/sellerMessages.js` imports everything that is genuinely symmetric instead of copying it, and building it moved the chat bubble and the day separators out of the customer's `MessageThread` into `components/messages/MessageBubble.jsx` and `messageRules.js` — a bubble is not a customer thing or a seller thing.

Business rules are **ported, never re-invented**, the same rule as the rest of this portal. `lib/sellerRules.js` copies `order_detail_screen.dart`'s status pipeline — including that `ready → delivered` rather than `received`, because receipt is the customer's act, and that `cancellation_requested` is a decision with two answers — and the low-stock boundary from `SellerInventoryRow` (1–5 is "running out"; 0 is a different problem with a different fix). `lib/seller.js` reproduces the app's own `_syncInventoryFromVariants`, because `inventory` is derived from `product_variants` and **no database trigger maintains it** — the schema comment naming `_syncInventoryFromVariants()` names a Dart function.

Deliberately absent, and why:

- **POS.** A point of sale is a counter, a scanner and a receipt printer. Reports says on the page that its total excludes walk-in sales rather than quietly under-reporting them.
- **Custom orders.** The app reviews them in `CustomOrdersScreen`; a `custom_order_request` notification is drawn without a link rather than pointing at a page that does not exist.
- **A "message this customer" button on an order.** The app has one, and the portal could use the same find-or-create path — it is simply not built yet, so a seller answers from the inbox they already have.
- **Store creation.** It needs the app's map picker; a store created without a location is worse than none, so the shell points at the app.
- **A colour picker on the storefront.** The form now writes per-colour galleries and the seller portal is built around them, but no customer surface here reads `product_color_images` yet — a product's colour photos are visible to the seller who uploaded them and to the app, and the shop still falls back to the product's own gallery. That is the first thing on the next-up list, not an omission: the data is there the moment a screen wants it.

## Setup

```bash
cd customer-portal
npm install
cp .env.example .env
```

Fill `.env` with the same Supabase credentials the app uses (they are in `lib/constants/app_constants.dart`):

```
VITE_SUPABASE_URL=https://psczvbfoybqhjeqssimw.supabase.co
VITE_SUPABASE_ANON_KEY=your_anon_key_here
```

## Run

```bash
npm run dev      # http://localhost:5174
```

The port is offset from the admin portal's (5173) so both can run at once.

```bash
npm run build    # → dist/
npm run preview  # serve the built output
npm test         # business-rule tests (Node's built-in runner, no test deps)
```

## Deploying — one thing will bite you

**The host must rewrite every unknown path to `/index.html`.** These are client-side routes, so `https://…/product/abc` only works if the host serves the app shell and lets the router resolve it. Without that rewrite, a customer who refreshes on a product page gets a 404 — and that URL is exactly the one people share.

- Netlify: `/* /index.html 200` in `_redirects`
- Vercel: a catch-all rewrite to `/index.html`
- Firebase Hosting: `"rewrites": [{ "source": "**", "destination": "/index.html" }]`

Before sign-up works, the deployed origin must also be in Supabase → **Authentication → URL Configuration → Redirect URLs** — the same list the app's `solvision://auth/confirm` is on.

## Layout

```
src/
  lib/          Data access and business rules
    pricing.js       Sale rules — a 1:1 port of lib/utils/sale_price.dart
    stock.js         Stock rules — a 1:1 port of lib/utils/product_stock.dart
    cartRules.js     Cart rules — from lib/utils/cart_helpers.dart
    searchRules.js   Search rules — a 1:1 port of lib/utils/product_search.dart
    notificationRules.js  Categories, batching previews, destinations and the
                     feed's filters — from app_notification.dart
    messageRules.js  Threads, bubbles, quick questions, realtime folding —
                     from message_service.dart, conversation.dart and
                     order_quick_message_sheet.dart
    storeIndexRules.js  What a store card says — from store_screen.dart's
                     _reindexIfNeeded and store_hero_card.dart's pill row
    storeBannerRules.js A store's banner, and the brand gradient when there
                     isn't one — from store.dart's bannerUrl + cardGradient
    shuffleRules.js  The shelf's random order — a seeded Fisher–Yates deal
    themeWipeRules.js Which still the theme change clips, and by which circle
    sizeKeyRules.js  What a stored size means — a 1:1 port of lib/utils/size_key.dart
    sizeMatchRules.js Does a product stock my size — a 1:1 port of lib/utils/size_match.dart
    checkoutRules.js Checkout rules — money, address, both payment methods,
                     reference, deadline
    orderRules.js    Order rules — statuses, timeline, cancel eligibility
    profileRules.js  Profile rules — draft, validation, avatar file checks
    signupRules.js   Sign-up field rules — birthday policy, gender options
    catalog.js       Queries + row mapping, mirroring SupabaseService
    cart.js          cart_items reads/writes (re-exports cartRules.js)
    checkout.js      The GCash RPCs, payment status, addresses
    orders.js        Order reads + the cancel RPC (re-exports orderRules.js)
    notifications.js notifications reads/writes (re-exports notificationRules.js)
    messages.js      conversations/messages reads, the two mark-read RPCs and
                     the realtime channels (re-exports messageRules.js)
    profile.js       profiles writes + avatar upload (re-exports profileRules)
    constants.js     Roles, categories, currency/date formatting
  hooks/        TanStack Query hooks over lib/catalog.js, lib/checkout.js
                and lib/orders.js; the auth context owns accounts and profile
  components/
    motion/       Shared motion tokens + the page transition
    product/      ProductCard, ProductGrid
    checkout/     OrderSummaryCard, AddressSection, AddressForm
    orders/       OrderCard, StatusPill/OrderProgress, OrderTimeline,
                  CancelOrderDialog, MessageMakerDialog
    account/      ProfileForm, AvatarUpload
    layout/       Header, footer, the shell
    search/       The header's expanding search and its suggestion panel
    stores/       The makers gallery (SeasonalStoreCards)
    ui/           Buttons-in-classes, price, badges, skeletons, empty states
  pages/        Home, Shop, Stores, StoreDetail, ProductDetail,
                Cart, Checkout, GcashPay, Orders, OrderDetail,
                Notifications, Messages, MessageThread, Account, NotFound
```

## The rule that matters most

**Business rules are ported, never re-implemented.** `lib/pricing.js` and `lib/stock.js` are line-for-line translations of their Dart counterparts, including the details that look like nitpicks and are not:

- a sale price must be **strictly** below the price to count as a sale
- the badge percentage is **rounded**, the "up to N% off" figure is **floored** — one names a product, the other makes a claim about a whole shelf
- products with no `inventory` rows are **out of stock**, not unlimited

Those files have tests (`npm test`). If the Dart rule changes, these change with it — a storefront that disagrees with the app about the price is the one bug a customer will certainly notice.

`lib/searchRules.js` is the same kind of port, and it fixed the same kind of bug. `product_search.dart` exists because searching **"Formal Shoes"** returned nothing: `Formal` is a *category*, the catalog's own word for those products, and no product is named or tagged it. The rule therefore matches a whole-phrase name **or** any query word against the name, the category and the tags — an OR, deliberately, because a customer typing more words is narrowing in their head, not asking for a conjunction. The portal had re-implemented one `includes()` over the whole typed string, so the dead end was back: measured against the deployed catalog, **`"Formal Shoes"` found 0 products** where it now finds 3, `"leather boots"` 0 where it now finds 5, and `"shoes sandals"` 0 where it now finds 7 — single-word queries and nonsense queries return exactly what they did before.

`matchesStorefrontSearch` is the one addition to that port: the portal's rows carry `store_name` and `collection`, which the app never searches because it reaches a maker through their own page. A customer typing "Carcar Leather" is naming a reason to buy rather than a product, so those two fields are matched word-wise, and the header search field already advertises it (“Search shoes, sandals, makers…”).

### The search is a pill in the middle of the bar

It used to be two controls — a field on desktop, a separate expanding row below `md` — and it is one now: Lightswind UI's `ExpandableSearch`, in `components/search/SearchField.jsx`. A 40px pill with the magnifier in it opens into the field (and its suggestion panel) on click or on `⌘K`, and closes on Escape, on a click outside while it is empty, or when a search runs.

Five things about it are this codebase's rules rather than the published component's:

1. **CSS, not a spring.** The published version animates its width with Framer Motion (`stiffness: 400, damping: 30`). Here the width is two Tailwind classes and a `transition-[width]` on the portal's own `ease-out-cubic` curve — the same substitution the rest of the portal makes, for the reason "Animations must fail open" gives: a class *is* the element's layout, so a transition that never runs costs the slide and not the field, and every duration and curve here comes from `motion/transitions.js`. The visible difference is that the published spring overshoots slightly and this does not.
2. **Centred from `lg` up, by a three-track grid** (`1fr auto 1fr`) — which is what makes the pill's centre the *bar's* centre rather than the middle of whatever the nav left over. Measured at 1440px in every state, closed and open: **pill centre 705px, row centre 705px**, and at every width the gap from the nav to the pill and from the pill to the account buttons is the same **12px**, which is the grid's own gap — that equality *is* the centring. The two outer tracks are equal only while their contents fit, which is why the grid starts at `lg`: a 352px pill in the middle of a 768px bar has nowhere to sit, so below `lg` the pill is right-aligned like any other mobile search button, and the field fills the row instead.
3. **Below `lg` an open pill takes the row.** The logo, the nav and the buttons hide while the field is open and come back when it closes — on a 390px bar there is no room for a field *and* a header. Measured at 390px: shut, the pill is 40px, the nav ends at 187px and the pill starts at 224px; open, the pill is **358px** (the whole row, centred, `off by 0px`) with the chrome hidden, and the page has **no horizontal overflow at all**.
4. **`⌘K` is wired, and the badge tells the truth** — `Ctrl-K` off a Mac, which is what the badge says, and the badge is drawn only while the field is empty and only from `md` up. Escape is layered in the app's own order: the suggestion panel closes first and the field second, because throwing away what someone typed is not what they meant by "close this".
5. **Focus is managed in both directions.** Opening focuses the input; Escape closes back to the pill, which needed an effect rather than a line in the handler — during the handler the pill is still the previous render's field, so `triggerRef` is null and the focus landed on `<body>`, throwing away a keyboard customer's place in the page.
6. **It opens wide enough to be a field.** The published component opens to `18rem` (288px), which in a bar whose middle track is `1fr auto 1fr` is long enough only for the placeholder. It is now **22rem from `lg` and 26rem from `xl`** — measured **352px** and **416px**, with the placeholder needing 203px of a 274px/338px text area, so there is room to see what you typed. Below `lg` it is still `w-full`: the pill fills whatever it has been given rather than being a fixed width with nothing beside it.
7. **The input is `type="text"`.** A search input draws the browser's own ✕ the moment there is text in it, so a customer who typed a letter saw **two ✕ in the same pill** — ours, which clears the panel and returns focus, next to the browser's, which does neither and is a different size in every engine. `input[type='search']::-webkit-search-cancel-button { appearance: none }` is in `index.css` as the site-wide guard, and this field does not rely on it: with no `type="search"` there is nothing for the engine to draw. Measured: **0** `input[type="search"]` on the page, **1** clear button in the pill when there is text and **0** when there is not. What `type="search"` was doing is said outright instead — `inputMode="search"` and `enterKeyHint="search"` for the mobile keyboard's own search key, with the `role` and `aria-*` set the input already carried.

This is also what fixed the sideways scroll on a phone. The bar's own row needed **422px** of content in a 390px viewport (`/shop` and `/makers` measured the same 32px of overflow), so every page could be dragged sideways on a phone: the wordmark now collapses to the mark below `sm`, the nav's padding tightens there, and the row fits. At 320px it still overflows by 29px — the bar has no room for a mark, two nav links, a pill and two buttons — but nothing overlaps, which is the honest failure rather than two controls on top of each other.

### The suggestion panel

The header field drops the app's typed-suggestions list out of it (`SearchField` → `searchPanelRows`): the query the customer has typed first, then the catalog's own categories, tags and product names, each labelled with what it is. Four things about it are decisions:

1. **It costs no request per keystroke** — the rows come from the catalog already in memory. And the header renders on *every* page, so the catalog is fetched only while a panel is actually showing a query (`useProducts({ enabled })`); measured: a visit to `/makers` issues **zero** product requests until the first character is typed, and the shared cache serves every later surface. (In `npm run dev` React's `StrictMode` double-mounts, so the first fetch appears twice; the built app fetches once.)
2. **It is a combobox, not a list of links.** The input keeps focus and owns the highlight (`aria-activedescendant` over `role="listbox"`/`role="option"`), so Tab is not a walk through eight rows. ArrowDown/ArrowUp move it, Enter runs the highlighted row — *or the typed query when nothing is highlighted* — and Escape closes the panel **without discarding the text**.
3. **It closes on `pointerdown` outside, not on blur**, the same reason `AccountMenu` does: a blur handler fires before the click lands, so a row would vanish before it could be chosen. Rows use `onMouseDown` + `preventDefault` so the click never even moves focus.
4. **The phone has the panel too, now.** It used to be a desktop-only affordance: the mobile field lived in a row that animated its own `max-height` and was `overflow-hidden`, so a dropdown inside it would have been clipped. With one expanding pill there is no such row, so the same list drops out of the same field at 390px.

A query that matches nothing is not a dead end: the panel still offers `Search for “…”` as its first row, which is what the app does — the customer's own words are always runnable.

## The makers page: a photograph, not a business card

The app's Stores tab is a hero carousel — one workshop at a time, with its rating, its product count and a row of its actual shoes. The portal shows all of them at once, because a page of real URLs has to be scannable, but the **content** the app chose for a store is what makes a card read as a shop, so it is ported (`storeIndexRules.js`) rather than invented.

The shape of a card is a port too — Lightswind UI's `SeasonalHoverCards`, in `components/stores/SeasonalStoreCards.jsx`. It is a row of full-bleed photo panels a third of the width that grow when you hover one, with the store's description held back until then: the photograph is the invitation and the words arrive when the customer shows interest. That is this page's own argument taken further than the card it replaces — the artisan is the differentiator, and a workshop's storefront photograph is what says so in one glance — so the maker's **banner** is now the panel itself rather than a 112px band above a window of product tiles.

Three departures from the published component:

1. **The panel is the link, not a div.** A maker card has always been one link to `/makers/:id`, and a gallery of photo panels that goes nowhere is a slideshow.
2. **Keyboard focus gets the same reveal as the mouse**, and it took two mechanisms because the two elements are different: `md:has-[:focus-visible]:w-2/3` for the panel's own width (the `li` is what grows, and `:has()` is how a non-focusable ancestor asks about a descendant) and `group-has-[:focus-visible]:` for the description and the photo's zoom. `group-focus-visible:` looks like the right tool and is the wrong one — it compiles to `.group:focus-visible …`, which asks whether the *panel* is focused, and a `li` never is. The bug that hid behind that is the reason it is written down: the panel grew on Tab while the description stayed invisible, so the reveal was mouse-only while looking keyboard-friendly.
3. **The description is visible below `md`.** A touch screen has no hover, so the published reveal would hide it on every phone; the words are held back only where there is a pointer that can ask for them.

One published detail is not optional: `flex-wrap` **and** `md:flex-nowrap`. Below `md` the panels are full width, so they are one per line either way; above it, leaving wrapping on makes the browser break the line using each panel's *hypothetical* width, so a hovered panel at two thirds pushes the third panel onto a second row instead of squeezing its neighbours. Measured before the fix: hovering gave **763px** with the other two still at **405px** — the shrink never happened. With `nowrap` the same hover gives **588 / 294 / 294** on one row.

### The banner, and what stands in for one

The most store-like thing a store has is its own storefront photograph, and the card was not showing it. `stores.banner_url` has been in the schema since the app's store profiles shipped; the app's `store_hero_card.dart` paints it full-bleed with `BoxFit.cover`; every portal store query is a `select('*')`, so the column was already arriving on every store row — and `banner_url` had **zero** references anywhere in `src/`. Two of the three live stores have a banner, so two makers looked like names in a list while their own photograph sat unused in the payload.

`lib/storeBannerRules.js` is the port: `storeBannerUrl(store)` (the app's `bannerUrl != null && bannerUrl!.isNotEmpty`, tightened — a blank column in an `src` makes the browser re-request the current page, so a blank banner would have cost a page load per card) and `storeCardGradient(store)`, which is `Store.cardGradient`: `linear-gradient(135deg, <brand colour>, lerp(colour, #1A1208, 0.55))`.

The gradient is not a placeholder that flashes and gets replaced — it is what a store without a banner *is*, which is exactly how the app uses it (`placeholder` and `errorWidget` are the same gradient), and it is the same band a **broken** one falls back to. Live: Valladolid Leather Co. has no banner and no logo, and its card gets a clay-to-espresso band that reads as deliberate rather than as a missing image.

Two of the three live stores have a banner and one has none, so the panel is the banner and the fallback is the same gradient the app paints behind a missing *or broken* one: live, **Valladolid Leather Co.** renders a clay-to-espresso panel where the other two render `storefront.jpg` (Janella, 1600×778 intrinsic) and `banner_…jpg` (demo_storeName, 960×720). The store's `brand_color` also stays as the rule across the top of the panel, which is what ties a photographed panel to an unphotographed one — the gradient alone would not read as the same shop.

What the facts say, and the three decisions in them:

1. **The rating appears only when `stores.rating` is not null.** The column stays NULL until the first review, which is exactly why the app guards it — `0.0 ★` on a store nobody has reviewed is a rating that does not exist. Live data: one store at 4.0, two with no rating at all.
2. **The pairs figure counts what a customer can buy right now**, because it comes from the catalog hook that has already dropped anything out of stock; zero reads `No pairs listed yet` rather than `0 pairs`.
3. **The place is the first comma-separated segment**, as the app's pill is (`location.split(',').first`): `Valladolid` fits a card, `Valladolid, Carcar City, Cebu` does not. The full address stays on the store's own page.

One deliberate divergence from the app: the app re-sorts each store's products by id descending, because the list it holds arrives shuffled; this query already orders by `created_at` descending, so insertion order **is** newest-first and re-sorting here would scramble it. A product with no `store_id` is left out rather than filed under `undefined` — it cannot belong to a card that does not exist.

None of it costs a request: the makers page re-uses the catalog query every other surface already shares, so the counts and the page's own `3 workshops · 15 pairs` line are derived from data already in memory. (That is the only thing it is used for now: with the product window gone, `topPicksFor` in `storeIndexRules.js` has no caller — kept because it is a port of the app's own rule and tested, but worth knowing it is currently unused.) Measured over CDP in an isolated browser against the live project, in **both** themes: three panels at exactly **392×450** on one row; hovering the first grows it to **588** while its neighbours shrink to **294** each, still one row (all three panels share the same `top`), with Janella's description going from `opacity 0` / `translateY 24px` to `opacity 1` / `0`. **Tab** onto the same link does exactly the same without a mouse. Dark and light measure identically, there is no horizontal overflow and no console exception. On a phone (390px) the panels are full width at **358×350** with the description **already visible**, because there is no hover to ask for it. `StoreCardSkeleton` was updated to the panel's geometry — the same third, the same 350/450 heights, the brand rule and the text stack at the bottom — so the loading row does not reflow when the photographs land.

⚠️ Measured on this page and fixed in the header: at 390px the bar used to overflow the viewport by 32px on every page (`/shop` measured the same `422px` of content in a `390px` viewport, and the widest element was the header's own inner row). It fits now — see "The search is a pill in the middle of the bar" above.

### On the home page: one banner, one destination

The home page used to show three maker cards here — a 52px avatar, a name, a tagline, a place, each its own link. They are now **one banner**: a photograph with a caption bar, and the whole thing is a single link to `/makers`.

The trade is the point. Three cards in a `sm:grid-cols-3` row are the smallest possible version of a workshop, and they were competing with the catalog grid directly above them — which is the thing the page is actually selling. On the makers page a maker is the subject; on the home page they are the *reason to trust the thing above them*, and that argument is a photograph rather than a list of names.

The caption is a **bar** (`chrome/70` + `backdrop-blur`, top hairline) instead of white type laid over the image. That is not only a look: white on an asset nobody has seen yet is a contrast lottery — the association's photograph may well be a bright workshop floor — and a bar keeps the ink legible over any image at all. It is the same surface-over-photo treatment the product tiles already use for their "View details" affordance.

The caption reads: the avatars, `MEMBER WORKSHOPS`, the names, and then the association's own sentence — the same one the makers page opens with, because `ASSOCIATION_INTRO` in `lib/constants.js` is the **one copy** of it. A sentence about who the members are should not exist twice by hand, and "here" is deliberately left alone: it means the marketplace on both surfaces.

Three smaller decisions, each of which was measured rather than guessed:

- **Each avatar keeps the page surface behind it** (a `bg-raised` disc with a hairline ring) rather than sitting straight on the bar, because the fallback avatar is a *tint* of the store's colour — designed to be read on a card, and this is the card brought along.
- **The avatars and the label are `sm` and up.** The sentence turned both mobile arrangements into a caption with a strip of photograph: inline, the 110px of avatar stack squeezed the text column and the sentence wrapped to **six** lines; stacked, the avatars cost a 58px row of a banner that is a photograph *behind* a translucent bar. Without them the mobile caption is 203px of a 420px banner — **52% photograph**, against 38% stacked and 22% inline. The names line already says who they are.
- **The section header lost its `All makers →` link.** A banner that goes to `/makers` sitting an inch under a link to `/makers` is two doors to the same room.

**The photograph is a slot.** `MAKERS_BANNER` in `pages/Home.jsx` is `null`, which draws a placeholder ground: each member workshop's own `brand_color` as a soft radial wash over `chrome`. To swap in the real thing, put the file in `public/` and set the constant to its path (`'/makers-banner.jpg'`), or import it from `src/` — nothing else changes, because the height, the caption bar and the destination are independent of it.

Measured over CDP at 1440 and 390: the banner is **1216×400** and **358×420**, flush with the section heading at **105px** / **16px**; the caption bar is **147px** on desktop (leaving **253px** of photograph, 63%) and **203px** on a phone (**218px**, 52%); the sentence is 2 lines at 14px on a desktop and 4 at 13px on a phone; the CTA is 46px tall (178px wide on desktop, full width on a phone); a real mouse click at 92% height over the workshop names — inside the bar, the part that could plausibly swallow a click — lands on `/makers`. One link, no nested focusables, no horizontal overflow, no console errors. The loading placeholder is one banner's height, not three cards', so the section does not reflow when the data lands.

The bar is translucent, so the honest test of "legible over any photograph" is the worst case: over a pure-white image `chrome/70` composites to a mid grey and 85% white on it measures **~5.6:1** — clear of AA for 13–14px text, and better than that over anything darker.

## The sale ribbon: why it is full bleed

The sale banner under the hero used to be a card — a `7xl` panel with a rounded border, a clay glow, a 64px discount medallion and a 2px hover lift. It read as one more panel on a page of panels, and it stated the discount three times (the medallion, the headline, and the button's promise).

It is now a **full-bleed ribbon in the brand clay**, deliberately outside the `max-w-7xl` container the rest of the page sits in. Four things follow from that, each measured over CDP against the live catalog at 1440px and 390px:

- **Edge to edge.** `0 → 1425px` at a 1440px viewport (the 15px is the scrollbar), `0 → 390` on a phone. Its inner row is still `max-w-7xl px-4 sm:px-6 lg:px-8`, so the figure starts on the same line as `THE WORKSHOP COLLECTION` below it — 105px on both, and 16px on both at 390px.
- **It still overlaps the hero**, by 56px at `lg` and 24px on a phone, so it costs no extra page height.
- **No lift on hover.** A viewport-wide strip that translates 2px is a page that jumps under the cursor; the band brightens by 6% white instead, and the arrow still slides.
- **The figure is the display face.** 56px Playfair at `lg`, 44px on a phone, with `off` tracked out beside its baseline. This is the one number on the site that is a *headline* rather than data — prices, sizes, counts and the end date all stay in `num` (Sora, tabular).

Two things it had to get right, both of which the first draft got wrong:

- **The button is `btn-ghost`, not `btn-primary`.** The primary skin is a *clay* fill and the band is clay: a clay pill on a clay band is a button nobody can see. The ghost skin is the one the app already defines for ink on a dark ground, and at 46px it clears the 44px target a thumb needs.
- **The small type is white at 85–90%, not 70–75%.** Burnished Clay is a mid tone, so `white/70` on it measures ~4.0:1 — under AA for 10–13px text — while `/85` is ~4.7:1. Hierarchy here comes from size, weight and tracking instead, which costs no contrast.

The band's link label is spelled out (`On sale — up to 61% off, ends Sep 28. 1 pair from 1 maker. See what's on sale`) rather than left to the visual order, because the visual order is a poster: a decorative figure, a date chip and one sentence. The stack of deal thumbnails is decorative too, and only drawn when there are **two or more** — a single 44px circle of somebody's product photo next to a full-width call to action reads as a mistake, and with a catalog this small that is the common case.

## The shelf: a new deal per visit

The catalog is **shuffled by default** (`lib/shuffleRules.js`), with `Newest first` still in the sort control for anyone who wants the old order.

The reasoning is the size of the shelf: fifteen products in `created_at` order is the same fifteen in the same order on every visit, so the first row — which is all a visitor sees without scrolling — is decided by whoever listed most recently. A deal turns the catalog into a browse rather than a list.

Four decisions, and three of them are about the ways this goes wrong:

1. **Seeded, not `sort(() => Math.random() - 0.5)`.** A random comparator is not a shuffle — the engine may compare an element many times and against different neighbours, so some orders come up far more often than others. It is Fisher–Yates, from a mulberry32 stream.
2. **The order is a value, so it is memoised.** A shuffle that runs per render re-deals the shelf on every hover, refetch and filter chip; the seed is fixed for the life of the page instead, and the cards stay put.
3. **The deal is cut from the whole catalog and the filters subtract from it.** Not the same thing: a shuffle of the three products that survive a filter is a *different* permutation of those three than their order in the fifteen, so dealing after filtering would rearrange the shelf on every category click rather than narrowing it. Measured: choosing a category leaves the visible cards in the deal's own relative order (`/shop` → 15 products, filtered to the 3 `Casual` ones in place).
4. **The seed is deliberately not in the URL.** The filters still round-trip exactly as before — a shared link opens the same `?q=&category=&sort=`, because those are things a customer means to send — but a link that opened onto one *particular* shuffle would be a stranger page to land on than the catalog itself. So the arrangement is per-visit and everything else is shareable, which is the split that matters.

Verified over CDP on the live catalog: two visits to `/shop` deal different orders, `?sort=newest` returns the query's own order deterministically, choosing `Shuffled` again returns that visit's deal unchanged, and filtering keeps it.

## Motion

Every duration and curve comes from `src/components/motion/transitions.js`, mirroring the app's `Curves.easeOutCubic`. Durations are short by design — a storefront is browsed quickly and an animation the customer waits for is a tax.

There is exactly one exception, and it is one of those durations being *shorter* rather than longer: **`CountUp`'s length comes from the number it is counting**, in `lib/countUpRules.js` — slowest on a single digit, where the increments are the whole animation, and fastest at five digits and up, where a count is a blur at any length and only has to say the figure is live. One 400ms for every figure is the wrong shape at both ends: too fast to read as counting for `0 → 3`, and thirty thousand ticks a second for a peso total. It is the only animation in the portal that sets its own timing, and the curve, its two ends and the clamp are unit-tested without a browser because node has no `requestAnimationFrame`.

Reduced motion is honoured in both halves: `useReducedMotion` for the JS-driven transforms (hover lifts, the gallery zoom) and a media query in `index.css` for CSS transitions, the page entrance and the skeleton shimmer. With it on, durations go to **zero**, not to something faster — a customer who asked for less motion wants the destination, not a quicker journey.

### Animations must fail open

**Nothing that matters may depend on an animation running.** Entrances are `animation: … backwards` in `index.css` (`.page-enter`, `.fade-enter`, `.panel-enter`, `.pop-enter`, `.drop-enter`, `.rise-enter`, `.slip-enter`), and every animated overlay mounts and unmounts with its state — there are **no exit animations anywhere in this portal**. This is not a style preference; it fixes a bug that made the site show an empty page.

#### What went wrong

The route shell was `<AnimatePresence mode="wait">` with an exit and a motion entrance. It could stall, and when it did `<main>` kept the header, kept the footer, and rendered no page at all — the content sat in the DOM at `opacity: 0`, because the incoming page's visibility depended on a JS animation getting a frame loop and finishing, and `mode="wait"` additionally made it wait behind the outgoing page's exit. Anything that stopped that loop stranded the page: a background tab, a navigation interrupting the previous exit, a dev-server reload mid-flight. It reproduced on ordinary clicks, not just edge cases.

Three rules follow for anything added later:

1. **Nothing may gate whether an element mounts, or whether it becomes visible.** An entrance is fine; an exit the next thing waits behind is not.
2. **An element's visible state must be its natural state,** with the animation as an addition. A stylesheet animation's end state *is* the element's own value, so a missing animation costs the flourish rather than the content. An inline `opacity: 0` waiting to be animated away does not.
3. **Animations go on elements that carry no state.** An overlay waiting out its exit is still mounted: still focusable, still in the DOM, still taking clicks. `CancelOrderDialog`'s backdrop is `fixed inset-0`, so an invisible one left behind would eat every click on the site.

`ErrorBoundary` around the routed page is the same idea for thrown errors: a class component that renders "This page did not load" with a reload button, keyed to `pathname` so navigating away clears it. Without it, a render error unmounts the tree and the customer gets a white screen with nothing to click.

#### The overlays, audited

Each of these was an `AnimatePresence` pair; each is now a conditional plain element with a CSS entrance:

| Overlay | Was | Failure it carried | Now |
|---|---|---|---|
| `PageTransition` | exit + motion enter, `mode="wait"` | the whole page invisible, permanently | `.page-enter`, no exit |
| `AccountMenu` | exit + enter | a closed menu still mounted: a 224px panel of links over the header, still focusable | `.drop-enter`, unmounts on close |
| `SiteHeader` mobile search | exit + enter | a closed panel still mounted: a field you can still tab into, holding vertical space | `.panel-enter`, unmounts on close |
| `CartIconButton` badge | exit + enter keyed on the count | the count invisible when it mattered | `.pop-enter`, plain element |
| `SellerSidePanel` | — (new) | — | `.slip-enter` + `.fade-enter` scrim in the overlay form, `.pop-enter` badges; nothing mounted when closed |
| `CancelOrderDialog` | exit + enter | a transparent full-screen sheet over the entire site, eating every click | `.fade-enter` + `.rise-enter`, unmounts on close |

The dialog also renders through a **portal into `document.body`**, which is where a modal belongs: `fixed inset-0` only means "the window" when no ancestor is transformed. See the next section for why that is not hypothetical.

#### The theme wipe

Changing the theme is a full-screen change, and a full-screen change in one frame reads as a repaint rather than as something the customer did. So it has a direction: **going light, the new theme grows out of the click until it covers the screen; going dark, the light recedes back to that point and the dark is what is left.** `lib/themeWipeRules.js` owns the geometry and the direction, `useTheme.jsx` runs it, and `index.css` holds the two rules the API needs.

It is the View Transitions API, which paints a still of the old theme and a still of the new one and lets us clip one of them with a circle. Four things are worth knowing:

1. **The class is written by the transition's own callback, not by a re-render.** The browser snapshots the page the moment that callback returns; a React state update is not guaranteed to have painted by then, so `commit` writes the class itself and the effect confirms it. Nothing about the wipe depends on React winning a race.
2. **Going dark is the *outgoing* still being clipped**, not the incoming one: the dark is already underneath, revealed as the circle closes, which is why `html[data-theme-wipe="dark"]` stacks the old snapshot above the new in `index.css`. A dark circle growing backwards would leave a light ring at the edge of the screen for the whole animation and snap at the end.
3. **Both stills have their default cross-fade switched off.** The API blends the pair with `plus-lighter`, which over two opaque light/dark stills blends to white — the wipe would be a flash.
4. **It fails open, like everything else here.** No View Transitions API and there is no wipe at all — the theme still changes. Choosing a mode that resolves to the theme already showing (`System` while the device is dark) also starts no transition, because a full-screen snapshot to arrive exactly where the page already was is nothing.

##### The one place reduced motion means "shorter", not "none"

Everywhere else on this site, `prefers-reduced-motion` sends durations to **zero**, and that is right for decoration. The wipe is not decoration: it is the explanation of a change to *every colour on the screen*, and removing it leaves a hard flip, which is the larger sensory event of the two. So a reduced-motion customer gets a **160ms circle instead of 520ms** — short, small, and still a wipe. It is a named exception (`THEME_WIPE_REDUCED_DURATION`), not a pattern to copy, and the decision lives in `themeWipePlan`, which returns a *duration* rather than a yes/no.

Measured over CDP, clicks driven with real pointer events and the media feature emulated:

| media | light direction | dark direction |
|---|---|---|
| `no-preference` | `::view-transition-new(root)` **700ms**, `circle(0px at 409px 141px)` → `circle(1213px at 409px 141px)` | `::view-transition-old(root)` **700ms**, `circle(1176px at 409px 212px)` → `circle(0px at 409px 212px)` |
| `reduce` | same circle, **220ms** | same circle, **220ms** |

The durations were tuned up from an initial 520/160ms, which read as a flick on a 1440px screen. This is the slowest animation on the site and the only one paced for how it looks rather than for getting out of the way — nothing waits on it, because the theme is already applied underneath the snapshots.

##### Two of the three clicks do nothing, which is correct and looks broken

The picker in Settings is three radio rows, and only one kind of click changes what is on screen:

- clicking the mode that is **already selected** fires no change at all;
- clicking a mode that resolves to the **theme already showing** — `Light` while on `System` with a light device — moves the check and nothing else. There is no wipe because there is nothing to reveal.

Both are right, and from the outside they are indistinguishable from a broken feature. The answer is a dev-only diagnostic rather than more UI: a header toggle was built for this and then removed, because the third control in the header row crowded the phone widths, and Settings → Appearance already says which theme is on.

**So a change that does not wipe says why, in the console, in development:**

```
[theme] no wipe: the device asks for reduced motion. Theme is now “light”; …
[theme] no wipe: the theme did not change (only the mode did) — nothing to reveal. …
[theme] no wipe: this browser has no View Transitions API. …
```

Stripped from the production bundle (`import.meta.env.DEV`), because the honest answer to "it did not animate" should not be a shrug.

The wipe is pixel-verified rather than assumed. The probe clicked “Light” and “Dark” at known coordinates, screenshotted mid-animation, decoded the PNGs and sampled luminance against the circle's predicted radius: light — everything at the click bright from the first frame, a point half a radius away dark and **later bright**, the far corner last; dark — the same three points going **dark in the opposite order**, nearest to the cursor last. That ordering is the whole feature: the first says the circle grows out of the click, the second says it collapses back into it.

Entrances only fill `backwards`, never `both`/`forwards`, and that matters: a forwards-filled `transform` keyframe leaves `matrix(1, 0, 0, 1, 0, 0)` on the element — an identity matrix that is not `none`, which makes the element the containing block for its `position: fixed` descendants. It happened here. The `.page-enter` wrapper kept that matrix after every route, and the cancel dialog's backdrop measured **1024×256 at y=65** instead of covering the window, rendering the dialog at the bottom of the page rather than centred. `backwards` releases the property when the animation ends, so the wrapper settles at `transform: none`; the portal means the dialog no longer depends on that either way.

## What is built, and what is next

Built: browse, search with typed suggestions, category and sale filtering, sorting, product pages, maker pages, accounts (sign in, sign up, e-mail confirmation, **profile editing**, password change/reset), the shared cart, **checkout with both of the app's payment methods** (GCash through PayMongo, and Cash on Pickup), **order history** (`/orders`, `/orders/:orderId`) with the status timeline and customer cancellation, a **notifications** feed, and **messaging** — realtime threads with makers, startable from a maker's page or from an order.

Next, roughly in the order the buying path needs them: choosing a **colour** on a product page (the cart's `resolveVariant` already takes one, but no screen offers it, so a two-colour product resolves to its first variant — and a seller can now create one from the web, which makes this the most visible gap in the buying path), **customisation options a customer can actually choose** (the seller form writes them, no surface offers them, so `cart_items.customizations` is never set), applying a **voucher** at checkout, and a **delivery estimate** (`delivery_date.dart`). Then the size plan's remaining phases (the auto-selected size and the cart/checkout mismatch notices — see the section above), and the retention surfaces: **product reviews** and store ratings, **following** a maker, **photos in a chat** (the app can send them; the portal renders them but cannot upload — see the messaging section), pickup and bulk reservations, recently viewed, and per-route **titles/Open Graph tags** — which matter because shareable URLs are this portal's reason to exist, and every shared product link currently previews as a generic "CUFMAI".

The cart is the app's own `cart_items` table, keyed by `user_id` — so a pair added on a phone is waiting in the cart on a laptop. That is also why the cart sits *behind* sign-in rather than in front of it: a local-storage cart would be a second, invisible cart the app knows nothing about.

## Size-aware shopping: the foot profile finally does something

The Settings page has been able to store a foot size since the Settings port, and until now **nothing read it**. Three surfaces do now, all on the app's own rule (`lib/utils/size_match.dart` → `sizeMatchRules.js`, with `size_key.dart` → `sizeKeyRules.js` behind it):

- **`In your size`** — a shelf on the home page, between the catalog and the makers, laid out as the **collection's own `ProductGrid`**. Eight products that stock the customer's size *right now*, derived from the catalog already in memory (no request), with `See all in your size` as the door to the rest. The heading **names the size** (`In your size — EU 42`) so a wrong profile is visible rather than silently filtering. It is the collection's grid and deliberately not a rail: as a horizontal scroller these were the same `ProductCard` at **224px instead of a full column**, without the size tag, and free to end at different heights (the flex item was the wrapper, not the card) — which made the personal shelf read as a second, lesser catalog sitting under the real one. Eight rather than the ten it carried as a rail, so it is two full rows of that grid at `xl`.
- **One line on a product page** under the size grid, and only ever one of three sentences, from `sizeAdvice`: `In your size · EU 42 · 3 left`, `In your size · EU 42 · sold out` (never offering the next size down, which is a different shoe on a different fit), or `EU 42 isn't available — closest is EU 41.5` (named as the *closest*, never as the customer's). Anything else — no size on file, no size data, nothing within half a size — prints **nothing**. Absent size, absent UI: no skeleton, no guess.
- **`My size · EU 42`** in the catalog's filter row, and `?size=` in the URL, which is what the shelf's `See all` opens. Same rule as the shelf, so the two cannot disagree. The chip follows the app's dead-end rule: it appears only when the customer has a size on file **and** the catalog actually stocks something in it (it stays visible while the filter is on, so the off switch does not vanish with the results).
- **A tag on product cards** (`SizeBadge`), from `sizeBadgeFor`: `EU 42` with an olive check when the tile stocks the size, `EU 42 sold out` when that size is sold out while the product itself is for sale, and **nothing** otherwise. It is deliberately the least colourful thing on the tile — the discount tag and the hover affordance already own their corners — it is `pointer-events-none` so the stretched link keeps its clicks, and it is `aria-hidden` because the size state is appended to the link's own screen-reader label instead. One call-site rule: a **near** size gets no tag (a tag claims buyability, the same standard as the shelf — only the product page names a "closest"). Every tile is tagged, the home shelf's included; it used to ask for `hideSizeBadge`, but the shelf renders the collection's grid now, and a card there without the tag reads as a *different* card rather than as an unlabelled one.

`sizeAdvice` and the shelf are two of the three sizes of "is it in mine?" — plan §8 R1 and R3 are why the wording matters and why a near size is never substituted. **No size ever pre-selects itself on a product page.** The app's P3 selects *my size → nearest → first in stock*; here the size grid stays a deliberate choice (the buy button is disabled until one is made), and the advice line informs that choice rather than making it.

Two parity fixes came with the port, both of which the product page had wrong:

1. **The size grid is sorted and deduped** (`availableSizes`). `inventory` rows arrive in whatever order they were written — the live catalog hands back `40, 41, 39, 38, 42` — so the grid read as a jumble, and a size that legitimately holds one row per colour rendered twice. Half sizes sort numerically, which is the app's §4.3 fix.
2. **`stockForSize` sums a size's rows.** The cart already sums them, so reading only the first row could strike a size through as sold out while the cart would accept it — the contradiction with the buy button the plan's §8 R4 exists to prevent.

The profile's own size label (`Settings` → `Size Your Foot`, and the row's subtitle) now goes through `formatSize`, so the `EU ` prefix has one owner — the same cleanup the app's P0 phase made (`grep -rn "'EU $" lib/` returns nothing there, and a test here enforces the same for `src/`).

**Not built, and deliberately:** the P3 auto-selection, and the P4 cart/checkout mismatch notices (`· not your usual EU 42`, the one checkout card that is dismissible and never blocking). The rule they would read is in place and tested; the surfaces are not.

One hook fronts all four surfaces — `hooks/useMySize.js` resolves `shoppingEuSizeFrom(profile)` once, so "where does my size come from" has one answer rather than four copies, and null flows through every caller as "render nothing".

## Orders: three things the schema decides for you

`/orders` is the list (filterable, with the filter in the query string so the back button works), `/orders/:orderId` is the receipt plus the status board. All of it is read straight off `orders`, `order_items` and `order_status_history`.

1. **`order_items` is written late, so `items_snapshot` is not optional.** The PayMongo flow is `defer-until-paid`: line rows are inserted by the webhook *after* the money moves, so an order that is still pending payment — or was cancelled before payment — has **no line rows at all**. Verified on a live cancelled order: `order_items: []`, `items_snapshot: [...]`. `orderLines` prefers the real rows and falls back to the snapshot, which is what makes a paid order and an abandoned one render with the same code.
2. **Cancelling is not an UPDATE.** `orders` has no customer `UPDATE` policy — only sellers (own store) and admins — and RLS does not raise, it just matches zero rows. Measured: `PATCH /orders?id=eq.<own order>` returns `200` with `[]`. The app's own `cancelOrder` is exactly that call, so it reports success while the order is untouched. The portal therefore writes through **`cancel_my_order`** (`20260925140000_add_cancel_my_order_rpc.sql`, **not yet applied** — see below).
3. **The cancel rule mirrors the app, boundaries included.** `pending`/`placed` cancel outright; `preparing` becomes a *request* the maker approves, and only inside the **2-hour window** (`AppConstants.processingCancelWindowHours`) measured from the order's own `preparing` history row — not from `created_at`, because a maker can sit on an order for days. `ready` is deliberately not cancellable: the pair is already bagged and waiting.

Until `20260925140000` is applied, the cancel button is honest about it rather than failing vaguely: `cancelError` recognises PostgREST's `PGRST202` (function not found) and says *"Cancelling from the website is not switched on yet. You can cancel this order in the CUFMAI app."* That message was verified by clicking through the dialog against the deployed project with the migration unapplied — which is also how the dialog itself (9 reasons, required free text for *Other*, Escape, scroll lock) was checked.

Two things the order pages deliberately do **not** do: they do not release inventory on cancellation (no path in this schema does for a paid order — the seller app's cancel is the same bare UPDATE), and they do not model the `subtotal_amount`/`discount_amount`/`voucher_*` columns, because the portal never sends a voucher code. `orderTotals` derives the delivery fee as `total_amount − lines` and clamps it at zero rather than printing a negative one.

## Notifications: generated since July, read by nobody

The portal had no notification feed, and the interesting part is how much was already there. `public.notifications` has existed since `20260702_notifications.sql` with `select`/`update` policies scoped to `auth.uid() = user_id`; an `AFTER INSERT` trigger and an `AFTER UPDATE OF status` trigger on `orders` have been writing a row for every step of the buying path — `pending → placed → preparing → ready → received` — for months. Every one of those rows was generated for a customer and read by nothing on the web.

`lib/notificationRules.js` and `lib/notifications.js` are the port, and four things about it are not obvious from the table:

1. **There are nine categories, not five.** The original migration created `unpaid, processing, shipped, review, returns`; later ones added `message`, `support`, `approval` and `reservations`. A feed that knew only the first five would render four kinds of notification as “Unpaid”. An unrecognised category resolves to `unpaid` — the app's own `_parseCategory` default — rather than to nothing, because a category drives an icon and a chip and has to render as *something*.
2. **A card can be a batch.** A trigger folds up to three messages from one conversation into a single `message` row, with `metadata.previews` (`{sender, text, timestamp}`, newest first) and `metadata.message_count`, and refreshes the title and timestamp as more arrive. “3 messages in this thread” is a different statement from “You have a message”, and the previews are drawn as a quoted list inside the card.
3. **Hiding is `is_deleted`, never a `DELETE`.** There is deliberately no client DELETE policy on the table, so a hard delete would match zero rows and report success — the same trap `orders.js` documents for cancelling. Every read filters `is_deleted = false`.
4. **The badge is a count, not a list.** The account-menu badge renders in the header of every page, so it asks Postgres for `{ count: 'exact', head: true }` instead of downloading a customer's feed to draw one number. Both hooks are `enabled: Boolean(userId)`.

**Realtime is deliberately not wired up here**, and that is not an oversight. The messaging migration explicitly added `conversations` and `messages` to the `supabase_realtime` publication and `notifications` was not added — its delivery path is push, via the app's `push_notification_service.dart`. Subscribing to a table that is not published produces a subscription that silently never fires, which is worse than none, because the feed would look live. It refetches on window focus instead, which is when a customer actually returns to it.

### The screen

`?tab=` (All / Catalog / Custom — the order's *source*) and `?category=` are two different questions and are kept as two controls: the tab is which kind of order, the chip row is which kind of news, with each chip carrying its own unread count. Collapsing them would make a customer who wants unread messages about custom orders choose which half of their question to ask. Both live in the URL, like every other filter here.

An unread card is marked **three** ways on purpose — a brand-coloured rule down its edge, a filled dot, and a bolder title — because colour alone is not a state a colour-blind customer can read, and the dot alone is easy to miss in a feed that is mostly read cards. The state is also in words for screen readers.

Read/unread and hide are **optimistic** (a reading list is the customer's own; waiting a round trip to draw a card as read makes the feed feel broken), while “Mark all read” is not: it is one request that may touch dozens of rows, and a screen that redrew them all first would have to put them back one at a time if it failed. It is scoped to the current filter, so clearing the message chips does not quietly clear the order ones.

Where a card goes is `notificationDestination`, in the app's own order: a message with a `conversation_id` → the thread; a `support` reply → the app's MyReportsScreen, **which the portal does not have**, so the card renders inert rather than linking somewhere unrelated; anything with an `order_id` → that order. Verified against the live project: every query shape the feed issues (the select list, `is_deleted`, `category`, `order_type`, the ordering, the count) returns `200`, and an anonymous visit to `/notifications` — plain or filtered — redirects to `/signin` and issues **zero** notification requests. `439 tests pass`.

⚠️ The feed has not been click-verified with a session: there are still no signed-in test credentials for the portal, so the read/write paths are rule-verified and query-verified, not driven in a browser.

## Messages: the one feature where the backend did all the hard parts

`conversations` and `messages` have been live since `20260713_messaging.sql`, with attachments, a delete-own-messages policy and a batching notification trigger added later. The portal had none of it. The port is `lib/messageRules.js` (rules) + `lib/messages.js` (queries, RPCs, channels) + `hooks/useMessages.js` + `pages/Messages.jsx` and `pages/MessageThread.jsx`.

Five things the schema decides, each of which a naive port gets wrong:

1. **Marking read is an RPC, not an UPDATE.** There is deliberately no client UPDATE policy on `messages` — RLS does not raise, it matches zero rows and returns `200 OK`, which is exactly the silent no-op `orders.js` documents for cancelling. The only path is `mark_conversation_read(convo_id, reader_role)` (and `mark_message_read(message_id)`), and the parameter names are the SQL function's own, not `p_`-prefixed — a wrong name is a `404 PGRST202`, which is how the first attempt at this was caught.
2. **The client never writes to `conversations`.** The app's `sendMessage` updates `last_message_at` / `last_message_preview` after inserting; that UPDATE matches zero rows too, and is harmless there only because the trigger has already done it. Porting it would be porting a no-op, so the portal inserts the message and nothing else. The same reasoning means the portal does **not** create the other party's notification: `notify_on_new_message` upserts it and folds up to three previews into `metadata.previews`, and a client insert would double-post and race the batching.
3. **A thread with no messages sorts FIRST.** The app orders by `last_message_at desc` with `nullsFirst: true`, so a conversation just opened from a maker's page is at the top of the inbox — where the customer who just opened it is looking. `sortConversations` is that rule, with the day keyed off `created_at` when there is no activity.
4. **`body` is nullable, and an attachment is a signed URL.** A later migration made a message attachment-only (`body IS NOT NULL OR attachment_url IS NOT NULL`) and the app stores a **one-year signed URL**, so the portal renders photos with no signing of its own (and no upload path at all — taking the photo is the phone's job, and the private bucket's INSERT policy is the app's flow). `messagePreviewText` uses the trigger's own words for an attachment-only message — `📷 Photo` / `🎥 Video` — so the inbox row and the bubble cannot disagree.
5. **The push IS the client's job, and only the client's.** The database owns the in-app half — `notify_on_new_message` writes the customer's notification row on any *seller* insert, whichever client made it — and nothing at all owns the other half: there is **no `pg_net` trigger on `messages`**, and the only call site in the whole project was the app's `message_service.dart`, which invokes `send-message-push` itself once its insert returns. So a reply sent from this portal lit the customer's bell and never touched their phone; the seller did not hear about a web-sent customer message either. `sendMessage` now fires `triggerMessagePush` from the row the database just gave back (see `messagePush.js`), which is one call site for **both directions** — it is the same event for both sides, the function resolves the recipient from `sender_type`, and a second call site is a second place for one direction to quietly go missing. It is **fire and forget on purpose**: the message is already stored, so awaiting it would turn a timeout at Google's end into a failed-looking send for a reply the customer can read anyway, and the `catch` exists because a rejection in a composer is a console error at the moment everything else worked. The payload is four fields (`conversation_id`, `sender_id`, `sender_type`, `body`) and the rules are tested; the function takes the **title** from the database's own `stores.name` / `profiles.full_name`, so the portal cannot push a stale name.

6. **Unread means unread from the OTHER party, and the badge counts threads.** A customer's own message stays `is_read = false` until the maker opens the thread, so counting it as theirs would badge a conversation the moment they wrote in it. The row's pill is capped at `9+`; the account-menu badge is the app's own `if (count > 0) total++` — **threads**, never messages, so it can never outgrow the inbox.

**A thread that cannot read its history says so.** `threadHistoryState` answers four things — `ready`, `empty`, `failed`, `partial` — and the two that matter are the last pair, because both used to be silent. RLS filters denied rows instead of raising, so PostgREST answers a denied read with `200 []`: an empty list proves nothing, and the thread drew *"Say hello to …"* over conversations that may be months deep. Worse is the `partial` case, which is what a live thread on a failed read actually looks like: Postgres Realtime keeps delivering, the list fills up from the bottom, and the screen looks **complete** while everything older than the mount is missing — the exact shape of the report *"the history is missing but new messages arrive"*. `ThreadHistoryNotice` gives both a face: the whole panel with a retry when there is nothing to show, and a strip **above** the live messages when there is, because replacing them with an error would throw away the only messages the reader has. `isError` from the query is the only honest source for either state.

**An optimistic send no longer cancels a thread's first load.** Every optimistic write starts by cancelling the thread's query so a revalidation cannot land on top of the bubble just typed — but `cancelQueries` on a query that has **never resolved** is a different act: it is the only fetch that returns the messages from before the thread was opened, React Query will not re-run it on its own, and realtime hides the damage by keeping the bottom of the list moving. `cancelThreadRefetch` cancels only when the query has data — an empty thread is `[]`, not `undefined`, and an empty thread's revalidation *should* still be cancelled, because there is nothing to lose and a stale "no messages yet" is exactly what the optimistic send exists to replace.

**Realtime is wired up here, unlike notifications.** Both tables are in the `supabase_realtime` publication — the messaging migration added them explicitly and `notifications` was left out — so the thread subscribes to `messages` filtered by `conversation_id` and the inbox subscribes to `conversations` filtered by `customer_id` (the trigger already moves `last_message_at`, so one row per change beats streaming every message). Each event is folded in by **`mergeMessage`**, a pure tested function, rather than by a refetch per message: a channel can deliver the same row twice (a sender's own INSERT is echoed back to them, and a resubscribe replays), and a chat that repeats or reorders looks broken in a way no error message explains. The one thing realtime cannot deliver is a DELETE — `messages` has the default replica identity, so the event carries only the primary key and cannot be filtered by conversation — which is why the thread also refetches on window focus.

### The screens

`/messages` is one row per maker (the table is `UNIQUE(store_id, customer_id)`, so a customer who asked about a sandal in March and a repair in September has one thread, in date order). Unread is marked three ways — a clay rule down the edge, a bolder maker name, and the count — and the row's screen-reader label says "3 unread" in words. `/messages/:conversationId` is the thread: bubbles split by `sender_type` (never by `sender_id`, which is `ON DELETE SET NULL`), day separators, a read receipt under the customer's own last message, and a composer that sends on Enter with Shift+Enter for a newline.

**Sending is optimistic** and the bubble says `Sending…` until the stored row comes back; `buildOutgoingMessage` is the only place the INSERT payload is built, so `sender_type: 'customer'` — which the RLS policy requires — cannot be got wrong at a call site. A failed send puts the words back in the box rather than losing them.

### Where you can start one

Three entry points, and they are the app's: the account menu (**Messages**, with the unread badge), a maker's page (`Message the maker`), and an order (`Something to ask?` → the app's `order_quick_message_sheet.dart` — four canned questions that *fill* the box rather than send it, swapping to the after-the-fact pair once the order is cancelled, delivered or received, and sending the message tagged with `order_reference_id` so the maker sees which order is meant). A notification about a reply already linked to `/messages/:conversationId` from the feed's own `notificationDestination`, so that link now resolves instead of 404-ing.

### What was verified, and how

`501 tests / 133 suites pass`, build clean. Against the live project: every query shape returns `200` (the inbox select with its `stores(...)` embed, the badge's ids, the thread's messages, the per-thread unread filter, the find-or-create lookup) and both RPCs resolve with `204` — the check that caught the wrong parameter names. Because there is still **no signed-in account** for the portal, the signed-in rendering was driven in an isolated Chrome against a throwaway probe page that signed in at the module boundary (fake session, fake profile row, fake insert) and rendered the *real* pages: 2 inbox rows at a uniform 832×82 with the right previews (`No messages yet` for the empty thread) and a `3` pill on the unread one, 3 thread bubbles with the photo rendering at its natural size and a `Today` separator, the optimistic bubble appearing with the send button disabled and then being replaced by the stored row, the captured payload exactly `{conversation_id, sender_type: 'customer', body, order_reference_id: null}`, the menu's `Messages` row with its `1` badge, and a `postgres_changes` subscription reporting **SUBSCRIBED** with the anon key — which is what makes the live chat actually live. Anonymous paths were checked on the built app: `/messages` and `/messages/:id` both redirect to `/signin` with **zero** conversation or message requests, and a maker page's `Message the maker` sends a signed-out visitor to `/signin` without issuing any. No console exceptions. The probe and both harnesses are deleted.

⚠️ Still unclicked by a human: a signed-in session, so the read/write paths are rule-, query- and probe-verified rather than driven end to end by hand.

## Profile & avatar: what is editable, and what is deliberately not

The account page is a form (`components/account/ProfileForm.jsx`) over `profiles` — name, mobile number, birthday, gender and the photo, plus the optional bio. Four things about it are decisions rather than details:

1. **It writes five columns, and the database is the authority on the rest.** The owner UPDATE policy (`auth.uid() = id`) is whole-row, and a BEFORE UPDATE trigger (`guard_profiles_sensitive_columns`) raises if the row's owner changes `role`, `seller_status`, `suspended*`, or any seller-application column once an application is pending or approved. The form simply never sends those — `profileUpdatePayload` is the only place the payload is built, and a test pins its five keys.
2. **Empty means NULL.** Clearing the number or the birthday clears the column. The app only writes `birthday`/`gender` when it has a value, so it cannot clear one; a form that shows every current value and submits them together has to mean "null" when the field is empty, and `phone` already behaved that way in the app.
3. **The avatar path is a contract.** `{userId}/avatar.jpg`, uploaded with `upsert: true` — because the Storage INSERT/UPDATE/DELETE policies check `(storage.foldername(name))[1] = auth.uid()`, and because the app uploads to this exact path. A per-upload filename would satisfy the policy and orphan every previous photo. The public URL is therefore identical before and after a new upload, so `withAvatarCacheBust` stamps `?t=` exactly as the app does; without it the browser keeps serving the old face and the customer concludes the upload failed. The file is uploaded **before** the column is written, so a failed upload cannot leave the account pointing at a photo that never arrived.
4. **E-mail is shown read-only, on purpose.** Changing a sign-in address is `auth.updateUser({ email })` — a verification mail to the new address, not a column write. Doing it halfway here would leave `auth.users.email` and `profiles.email` disagreeing, with a UNIQUE constraint on the second. It is displayed rather than hidden so nobody goes hunting for it.

The gender field round-trips through a lossy encoding that is worth knowing about: choosing **Self-describe** at sign-up persists the *free text itself* into `profiles.gender`, not the string "Self-describe". So any stored value that is not one of the four options IS a self-description, and `genderDraftFrom` infers that — without it, editing an unrelated field would rewrite somebody's gender.

## The cart is a checklist, in the app's order

The portal had the app's order of operations **backwards**. Its cart totalled everything and sent the customer to checkout, where the *first* question was which maker to pay — so "which of these am I buying?" was answered one screen after the total was already on the page. The app asks it in the cart: a tick per line, a tri-state tick per store, a master tick, and a summary that reads only the selected lines (`CartProvider.selectedKeys` and the six getters built on it).

`cartRules.js` now carries that as pure rules, and `useCart` carries the state:

- **`cartItemKey`** is the app's own key — `productId-size-color`, `'$productId-$size-${color ?? 'none'}'` in `addToCart`. Deliberately *not* the cart row's id: a line that has not reached the server yet has no id, and a line whose quantity changes keeps its identity, so a tick survives the stepper.
- **`selectedUnitCount` is units, not lines** — two pairs of one sandal is two things, and the Checkout button has to agree with the header badge that says 2.
- **`storeSelection` returns `all` / `some` / `none`**, and toggling a *partly* selected store **completes** it rather than clearing it. That is `CartProvider.toggleStore`, and it is what makes the indeterminate box behave like "select all of these" instead of a coin toss.
- **The selection lives in the cart context, not the cart page.** `/checkout` is a different route; a selection held in a page's state is gone by the time the customer gets there, which is the whole bug. It is deliberately not persisted — the app keeps `_selectedKeys` in memory too, and a cart that reopens with yesterday's ticks still on it charges for things the customer was not looking at. (Pairs added *now* are ticked automatically, exactly as `addToCart` does, so add-a-pair-then-pay stays a two-click path.)

### It also fixed a delivery-fee contradiction

The cart used to show `DELIVERY_FEE × makers` in its estimate while the checkout charges **one** fee for the **one** order and payment it creates. On the two-maker cart in the screenshot that is ₱651 quoted and ₱551 taken. The app's rule is flat — `selectedDeliveryFee => selectedSubtotal > 0 ? 100.0 : 0.0` — and porting it aligns the estimate with what the customer is actually charged. The ported rule takes the fee as a parameter rather than importing it, because `checkoutRules.js` already imports `cartRules.js` and reaching back would be a cycle; `useCart` passes the same `DELIVERY_FEE` the payment intent adds.

`Checkout` now renders `selectedItems`, and its empty state distinguishes an **empty cart** from a **cart with nothing ticked** — the second is who this change is for, and telling them their cart is empty would be a lie.

⚠️ Not click-verified: `/cart` and `/checkout` are both behind `RequireAuth`, so the selection is rule-verified (`458 tests pass`, including the tri-state semantics, the fee-once rule and the ghost-key case) and build-verified, not driven in a browser.

## Checkout: the parts that are easy to get wrong

Checkout is `/checkout` → `/checkout/pay/:orderId` for GCash, and `/checkout` → `/orders/:orderId` for cash. On the GCash path the portal never writes an order's total or its payment status: the order and the PayMongo session are created server-side by `create-gcash-payment-intent`, and a signature-verified webhook is the only thing that marks it paid.

A footnote worth knowing, because it cost a detour: the portal was first built on `create_gcash_checkout`, the gateway-free attempt-#5 RPC. That route was **deprecated and closed on 2026-09-05** (`20260905000000_fix_t5_manual_gcash_dedupe_audit.sql` §5) and answers `42501 permission denied` to a signed-in caller — verified against the deployed project, not inferred from the migration. Two migrations in this repo deal with the fallout (`20260925120000` closes an `anon` EXECUTE hole on those dead RPCs; `20260925130000` fixes the sale-pricing bug inside them).

1. **One maker per order, because the flow is shaped that way.** An order has one `store_id` and so does its payment session. A cart mixing makers cannot become one payment, so it is split, the customer picks a maker, and the rest of the cart stays put.
2. **The two-tab redirect.** PayMongo sends the customer back to the app's own deep link (`PAYMONGO_SUCCESS_URL`, a `solvision://` URL), which a browser cannot follow. So the hosted page opens in a **new tab** and the portal's tab goes to `/checkout/pay/:orderId`, where it polls `get-payment-status`. Success is never inferred from a redirect — the app's rule, kept.
3. **The amount is checked, not assumed.** The storefront quotes from its own sale-aware rules (`pricing.js`) plus the GCash fee it *read* from `get_gcash_fee`; the intent returns what it will actually charge. `reconcileServerTotal` compares the order total (against `amount - fee_amount`, so it holds even when the fee read failed) and the charged total, and on a mismatch **stops before sending anyone to a payment page**, showing both figures and a one-tap cancel. An overcharge the customer cannot see is the failure a checkout must never ship with.
4. **Stock is not reserved until paid** (`defer-until-paid`), so an abandoned checkout holds nothing, and `order_items` legitimately stays empty while a payment is pending. The pay page therefore renders the order's own `items_snapshot` — which is what makes a resumed visit show the same basket as a fresh one, with no navigation state involved.
5. **The cart clears only on confirmation.** Items stay in the cart while the payment is pending, so the customer can see what they are paying for and cancel freely; `cartLinesToClear` then matches the order's lines back onto the cart on `(product_id, size)` when the poll reports paid.
6. **The deadline is the server's clock.** 15 minutes, returned as `expires_at` on the intent and re-read on every poll. The countdown is a UI hint; the sweep and PayMongo decide.
7. **The address is typed, not inferred.** Region, province and city start blank: a pre-filled province is a value nobody chose, and the silent failure it produces is a Manila order addressed to Cebu. The pin comes from the browser's own location API when the customer allows it — without it the form says what will be stored, because `customer_addresses` requires a coordinate.

The fixed **₱100 delivery fee** is added by the server to every order, and the Model B GCash surcharge (2.23% + 12% VAT at the time of writing, from `payment_fee_config`) is added on top of it — so the quote reads Subtotal → Delivery → GCash fee → what you pay.

### The second payment method the app has had all along

There is one method above the fold that the app has always offered and the portal did not: **Cash on Pickup**. The app's checkout is a `RadioGroup` of exactly two — `GCash` (*Pay the store directly via GCash*) and `Cash on Pickup` (*Pay cash at Carcar studio*) — so a portal that only takes GCash is a portal that cannot do half of what the phone can.

The two are not a label on one flow, and that is why they are separate code paths rather than a flag:

| | GCash | Cash on Pickup |
|---|---|---|
| order created by | `create-gcash-payment-intent` (server) | the client, in three inserts |
| status on creation | `awaiting_payment` | `pending` |
| `payment_status` | `paid` once the webhook fires | `unpaid`, and stays that way until the maker is handed the cash |
| stock | not reserved until paid (`defer-until-paid`) | reserved **immediately** — `order_items` is what decrements inventory |
| where the customer goes | a new tab, then `/checkout/pay/:orderId` | straight to the order |
| the surcharge | Model B fee, quoted and reconciled | none |

`PAYMENT_METHODS`, `normalizePaymentMethod`, `paymentMethodLabel`, `isOnlinePayment`, `cashOrderInsert`, `orderItemInserts` and `stockUnavailableMessage` are all in `checkoutRules.js`; `placeCashOrder` in `checkout.js` does the writing. Five things about the cash path are the app's, not inventions:

1. **`payment_method` is normalized before it is stored.** The column is `TEXT NOT NULL DEFAULT 'cash'` with **no CHECK constraint**, so nothing stops `'Cash on Pickup'` ending up in it — but the app normalizes (`_normalizePaymentMethod`: gcash → `'gcash'`, card → `'card'`, **everything else → `'cash'`**), and other screens read those words. The portal normalizes identically, and that fallback is exactly why an unrecognised value must never reach the column.
2. **`fulfillment` is `'pickup'`**, which is what the app writes for *every* online order — delivery included — so the portal writes it too rather than inventing a delivery/cash combination the seller side has never seen. `orders.notes` carries the formatted address and `shipping_address` the snapshot, both as the app sends them.
3. **The item inserts are what reserve the pair.** `decrement_inventory_on_order` (`SECURITY DEFINER`) decrements inside each `order_items` insert and raises `Insufficient stock for product <id> size <size>` when it cannot. Sizes are matched by **digits** (`regexp_replace(size, '\D', '', 'g')`), so the cart's own `EU 40` reaches the same inventory row the app's resolved size would — `orderItemInserts` therefore sends the cart's string, and no inventory fetch is needed.
4. **A failed line rolls the whole thing back.** The app deletes the orphan order (customers may delete their own `pending` orders) and the items it managed to insert; the portal does the same, then says which pair sold out — the raw message has a UUID in it, and `stockUnavailableMessage` turns it into *"Artisan Chelsea Boot (size EU 41) is no longer available in that quantity"* with the cart as the way out.
5. **The fee is only asked for when GCash is chosen.** Switching to cash stops the `get_gcash_fee` query (verified: one call with GCash selected, none after the switch) and drops the fee row from the summary entirely, so the quote reads Subtotal → Delivery → **Pay at pickup**.

The order page grew two things for this: the meta line now names the method (`2 pairs · Pickup · Cash on Pickup · …`, from the stored column, so a phone order and a web order print the same words), and a cash order gets a **"Paying in cash"** card with the amount — *not* the GCash "Payment not finished" card, which is driven by `isUnpaidOrder(status)` (`awaiting_payment` only) precisely so the two states cannot be confused. Arriving from checkout it also gets a confirmation band, which is this portal's version of the app's "Order Confirmed" screen (Order ID / Total / **Payment Type**).

**Verified** with `515 tests / 137 suites` and a clean build, plus two browser runs of the real pages against a mocked session (cart seeded, order inserts captured): the checkout defaulted to GCash with both options rendered and a `Pay ₱857.03 with GCash` button; switching to cash changed the button to `Place order · ₱850.00 at pickup`, named the store's own `location` in the explanation, dropped the fee row, and issued **no** second fee call; submitting captured an `orders` insert identical to the app's payload (`pending` / `pickup` / `cash` / `unpaid` / `source: online` / notes + snapshot) and one `order_items` row per line, removed the two cart lines, and landed on the order page showing *"Thank you — your order is with Janella. Keep ₱850.00 in cash for when you collect it."* with the payment label in the meta line. The failure path was driven too, with the database's own `P0001`: the inserted item and the orphan order were both deleted, the customer stayed on checkout, and the message named the pair that sold out. Against the deployed project, both insert payloads reach RLS (`42501 new row violates row-level security policy`) rather than a `PGRST204` unknown-column error, which is what proves every column those inserts use actually exists. ⚠️ Still not clicked by a human with a real session — the same missing-credentials caveat as everywhere else.

## Auth: the parts that are easy to get wrong

These are database constraints, not preferences — each one is copied from the app rather than reinvented:

1. **There is no `on auth.users` trigger.** The `profiles` INSERT policy is `auth.uid() = id`, so a session must already exist to write the row. With e-mail confirmation on, `signUp` returns **no session** — so the sign-up fields are stashed in the user's metadata and the row is written afterwards by `/auth/confirm` (`writeProfileFromMetadata`).
2. **`profiles.seller_status` defaults to `'pending'`**, which is what an unapproved seller application looks like. Every customer insert must set `'none'` explicitly.
3. **Suspension cannot be enforced by RLS at login** — the migration that added the flag says so outright, because auth runs before any policy. The client must read `suspended` and act on it; RLS is the second, server-side layer.
4. **The redirect must be the deployed origin** (`authConfirmRedirect()`), and that origin has to be in Supabase → Authentication → URL Configuration → **Redirect URLs**. A browser has no handler for the app's `solvision://` scheme — this is the web counterpart of that same allow-list step.

### ⚠️ Open finding: every profile row is world-readable

`profiles` carries the base schema's `"Public profiles are viewable by everyone"` SELECT policy — `USING (true)` — and it has never been narrowed. Measured against the deployed project on 2026-09-25, with **only the public anon key and no session at all**:

```
GET /rest/v1/profiles?select=full_name,phone,birthday,gender,email&limit=5
→ 200  [{ "full_name": "…", "phone": "0917…", "email": "…@gmail.com" }, …]
```

So anything with the anon key — which ships inside every client — can page through every customer's name, phone number, birthday, gender and e-mail address. The storefront does not depend on it: the only profile reads it makes are the signed-in customer's own row, plus `stores` joins for a maker's name. A narrower policy (own row, plus sellers' public display fields) is a production change and has been left for a decision rather than slipped into a feature branch.

**The role rule here:** the storefront admits any *active* account as a shopper, because a CUFMAI artisan also buys shoes. Only `suspended` is a hard block, and that is the app's rule too. Seller tools stay in the app, and the sign-up page says so.
