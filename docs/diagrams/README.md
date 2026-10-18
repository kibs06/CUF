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
| 6 Home | what Home shows, the four tabs, where they can go | 7, 10, 11, 12, 13 |
| 7 Browse the shops | shops, search and filters, the product page, reserve for pickup | 8, 9, 10 |
| 8 Try the shoes on | camera try-on, swapping shoes, the recommended size | 10 |
| 9 Make it their own | ready-made options vs. a fully custom pair | 10, or END |
| 10 Cart and payment | cart, address, GCash or cash on pickup, order placed | 11 |
| 11 Track the order | My Orders, cancelling, confirm receipt, per-pair stars, photos and edits | 6 |
| 12 Talk to the shop | starting a chat, ready notes, photos, typing dots, read ticks, the bell badge | 6 |
| 13 Profile and settings | profile overview, foot size, reservations, the gear to Settings | 14 |
| 14 Settings in detail | security, accounts, theme, addresses, help, log out, delete | END |

**Symbols** (same reading as the flowcharts in the capstone document):

- oval = the start or the end, rounded rectangle = a step, diamond = a question
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

## `customer-signup-flow.drawio` — the one-page sign-up view

The earlier single-page version of just the account-creation part, kept as the
one-glance summary (preview: `customer-signup-flow-preview.png` / `.svg`).

## Regenerating

```
node tool/generate_customer_journey_diagram.mjs --png
```

It rewrites the `.drawio` and every preview, and fails loudly if a connector crosses a
box, a label lands on a box, an off-page connector points at a page that does not point
back, or any wording slips back into developer language.
