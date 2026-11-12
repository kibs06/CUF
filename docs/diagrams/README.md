# Customer-facing diagrams

These are the pictures to show the shop owner — plain English, no screen names, no
table names, no code. The developer-facing diagrams live in `docs/AI/diagrams/`.

## `customer-journey-flowchart.drawio` — the whole journey (14 pages)

One page per part of the journey, so nothing is squeezed. Pages are tabs in
draw.io (`1 Open the app` … `14 Settings in detail`).

| Page | What it covers | Continues to |
|---|---|---|
| 1 Open the app | loading check, already-signed-in shortcut, welcome slides, Sign up / Sign in screen | 2, 5 and 6 |
| 2 Create an account | the full form, fix-ups, email already used, confirm-or-straight-in branch | 3 and 4 |
| 3 Confirm the email | the 6-digit code, the email button, wrong/expired codes, back to sign in | 4 and 5 |
| 4 Add their foot size | scan, type it in, or skip — from code done or no code needed | 6 |
| 5 Sign in | forgot-password link, same-error rule, new-phone code, suspended, retry, extra code | 6 |
| 6 Home | what Home shows, the four tabs, foot-size tip when missing, bell/messages check, where they can go | 7, 10, 11, 12, 13 |
| 7 Browse the shops | shops, search and filters, the product page, size-in-stock check, hold-for-pickup branch, reserve for pickup | 8, 9, 10 |
| 8 Try the shoes on | camera permission check, camera try-on, swapping shoes, the recommended size, fit check | 10 |
| 9 Make it their own | ready-made options vs. a fully custom pair | 10, or END |
| 10 Cart and payment | cart, voucher code, address, GCash or cash on pickup, payment-result check, order placed | 11 |
| 11 Track the order | My Orders, unpaid pay-now branch, cancelling, confirm receipt, per-pair stars, photos and edits, buy-again loop | 6 |
| 12 Talk to the shop | starting a chat, custom-pair request branch, ready notes, photos, typing dots, read ticks, solved-or-follow-up loop, the bell badge | 6 |
| 13 Profile and settings | profile overview, edit-name/photo branch, foot size, reservations with hold-longer request, the gear to Settings | 14 |
| 14 Settings in detail | security, accounts, theme, addresses, help, log out, delete | END |

**Symbols** (same reading as the flowcharts in the capstone document):

- oval = the start or the end, rectangle = a step, parallelogram = typing or a message, diamond = a question
- **pentagon = off-page connector** — "Continue on page N" / "From page N"; the flow
  picks up on that page, which is how one long journey is spread over 14 pages
- **small circle with a letter = on-page connector** — the flow jumps back to the same
  letter instead of drawing a long line back across the page (used for the form fix-up,
  the wrong code, the forgot-password return, another shoe, the cart changes,
  the address, the retry and the wait for delivery)

## Previews

`previews/` holds one `.png` (2× scale, ready to paste into the document) and one `.svg`
per page, named `01-open-the-app.png` … `14-settings-in-detail.png`. They are rendered
from the same coordinates the `.drawio` stores, so the drawing does not move.

Every diagram page is one sheet of A4 paper (827 × 1169): the generator lays the
flow out at full size, then scales it down to fit the sheet, so printing
"fit to page" never spills onto a second sheet. A flow that would shrink past
40 percent — denser than the densest seller sheet — does not fit: split it
across pages with off-page connectors instead.

Off-page connectors name the target page by a short code, not the full title:
AP open the app · CA create an account · CE confirm the email ·
AFS add their foot size · SI sign in · Hm home · BS browse the shops ·
TSO try the shoes on · CP cart and payment · TO track the order ·
TTS talk to the shop · PS profile and settings · SD settings in detail.

## `in-store-customer-journey.drawio` — the manual in-store purchase flow

A one-page replica of the reference flowchart: Start → enters store → browses →
inquires → owner checks stocks manually → availability decision (No → ask about
another size/design/price → still-browsing decision) → present shoe → fit/inspect →
purchase decision (No exits down the left side; Yes → confirm price → pay → change →
receipt → manual inventory update → logbook) → End. Black page, white boxes with
black text, white arrows. Wording (including the reference's own spellings) is
transcribed verbatim — edit the `.drawio`, not the picture.

## `customer-signup-flow.drawio` — the one-page sign-up view

The earlier single-page version of just the account-creation part, kept as the
one-glance summary (preview: `customer-signup-flow-preview.png` / `.svg`).

## `database-erd.drawio` — database ERD (7 subject-area pages)

Entity-relation diagram of the Supabase database, distilled from
`supabase/migrations/*.sql` (`supabase/schema.sql` is reference-only).
Open it in draw.io (app.diagrams.net) — pages are tabs, one per subject area.

The schema is too large for one sheet, so it is split into normalized
subject-area modules — not flowchart off-page connectors, and not one
combined mega-page. Each page draws only its own domain's relations;
a foreign key into another domain appears as `FK→table` text naming the
referenced table and its page. That keeps every page overlap-free by
construction.

| Page | Tables |
|---|---|
| 1 Identity (8 tables) | profiles, customer_addresses, trusted_devices, device_secrets, device_enforcement_policy, failed_logins, account_session_log, deletion_requests |
| 2 Catalog (13 tables) | stores, store_follows, story_entries, products, product_images, product_variants, product_customizations, product_color_images, inventory, product_models, product_ar_effects, store_reviews, banners |
| 3 Orders (9 tables) | orders, order_items, order_status_history, cart_items, pickup_reservations, pickup_reservation_extension_grants, bulk_reservations, bulk_reservation_deposits, customization_requests |
| 4 Payments (11 tables) | sales_transactions, sales_transaction_items, payment_intents, payment_webhook_events, gcash_payment_proofs, gcash_payment_decision_audit, order_payment_events, payment_fee_config, function_rate_limits, vouchers, voucher_redemptions |
| 5 Reviews (4 tables) | product_reviews, product_review_images, reviews, review_images |
| 6 Messaging (5 tables) | conversations, messages, notifications, seller_notifications, device_tokens |
| 7 Moderation (7 tables) | reports, seller_business_docs, seller_application_audit_log, seller_activity_log, shoe_model_requests, foot_measurements, foot_scan_jobs |

**How to read it:** bold key glyph = primary key, diamond = foreign key,
`FK→table` = the referenced table, crow's-foot connectors = one-to-many.
A line is drawn only when both tables live on the same subject-area page;
FKs pointing at another page are `FK→table` text only — look up the table
in the page list above. There are no off-page-connector symbols and no
combined all-tables page, by design.
Live DB uses UUID for `products.id` / `orders.id` / `order_items.id`.

## Regenerating

```
python tool/generate_database_erd.py
```

```
node tool/generate_customer_journey_diagram.mjs --png
```

It rewrites the `.drawio` and every preview, and fails loudly if a connector crosses a
box, a label lands on a box, an off-page connector points at a page that does not point
back, or any wording slips back into developer language.
