# Capstone Paper — Updated HIPO (replaces pp. 45–47)

Files:
- `img_fig4a.png` … `img_fig4d.png` — the IPO figure images embedded in the docx (same box-and-arrow style as the original paper's Figure 4).
- `CUFMAI-Pages-45-47-HIPO-Updated.docx` — **drop-in replacement for pp. 45–47.** Same format as `CUFMAI FINALSSS.docx`: Letter, 1.5" left / 1" other margins, Arial 12, double-spaced, justified body, centered `Figure 4 / 4a / 4b` captions, black-header INPUT–PROCESS–OUTPUT tables in the same style as the original figures. Copy these pages straight into the paper.
- `CUFMAI-HIPO-Updated.drawio` — editable source, open in draw.io (app.diagrams.net).
Three draw.io pages (tabs at the bottom):

| Page in draw.io | What to paste in the paper | Replaces |
|---|---|---|
| 1 `Fig4-HIPO-Hierarchy-Updated` | Figure 4 — Hierarchical Input-Process-Output (hierarchy chart) | Old Figure 4 hierarchy |
| 2 `Fig4a-IPO-Customer-Seller` | Figure 4a — IPO Table 1 of 2 (Customer + Seller onboarding) | Old IPO text pp. 45–46 |
| 3 `Fig4b-IPO-Fitting-Orders-Admin` | Figure 4b — IPO Table 2 of 2 (Fitting / Fulfillment + Admin) | Old IPO text pp. 46–47 |

Print: Page Setup is A4-landscape-ready (1220 px wide). In draw.io: File → Print → Fit to 1 page, or Export as PNG (200%) for Word.

## What changed vs the old HIPO

Old text (p.45): "main function is inventory management, virtual fitting, order customization; inputs from owners (inventory, order customization) and customers (browsing, fitting); outputs are processed inventory, fitting, order customization."

Updated to what the app does today (Nov 2026):

- **Level 0 unchanged:** 0.0 CUFMAI — Footwear Retail Management System with Virtual Fitting Support.
- **Level 1 is now 5 modules (was 3 implied):**
  1.0 Customer Shopping & Services (Flutter `lib/screens/customer/`)
  2.0 Seller Operations (Flutter `lib/screens/seller/` — dashboard, products, inventory, POS, GCash queue, vouchers, reservations)
  3.0 Virtual Fitting & 3D Visualization (`.deepar` + `.glb` in `assets/models/`, `product_ar_effects`, `product_models`, `foot_measurements`, `foot_scan_jobs`, `shoe_model_requests` + `UploadModelModal` / `usePublishModel`)
  4.0 Orders, Payments & Fulfillment (`orders`, `order_items`, `payment_intents`, `gcash_payment_proofs`, `sales_transactions`, `order_status_history`, inventory triggers)
  5.0 Admin & System Management (React `admin-portal/src/pages/` + Flutter `lib/screens/admin/` — Users, SellerApplications, Products, ModelRequests, Orders, Transactions, Reports, Banners, AuditLogs, Settings + 2FA/suspension guards)
- **Level 2 (27 boxes)** now names the real screens/tables: OTP + foot-size onboarding, `_buildSizesMap()` live-stock merge, `CartService.validateForCheckout()`, `createOrder()`, pickup reservations + extension grants, POS barcode + receipts, GCash proof approve/reject audit, customization_requests, FCM push fan-out.
- **IPO tables** list concrete Input → Process → Output per module with live table names so panelists can trace each row to the DB (`profiles`, `products`, `product_variants`, `inventory`, `cart_items`, `orders`, `order_items`, `vouchers`, `conversations`, `messages`, `notifications`, etc.).

## Suggested caption text (paste under the figures)

> Figure 4 (Updated). Hierarchical Input-Process-Output. Level 0 is the CUFMAI system; Level 1 shows the five modules (Customer, Seller, Virtual Fitting, Orders/Payments, Admin); Level 2 shows the sub-processes implemented in the current build.
>
> Figure 4a–4b (Updated). Input-Process-Output tables. Each Level-2 sub-process lists its inputs (user entries / external data), processes (validation, app logic, Supabase tables and Edge Functions), and outputs (records, screens, and notifications).

## Source check

- Customer screens: `lib/screens/customer/` (cart, checkout, tracking, inbox, customization, addresses)
- Seller screens: `lib/screens/seller/` (dashboard, manage_products, manage_orders, pos_screen, gcash_payment_queue_screen, vouchers_screen, reservation_requests_screen, pickup_reservations_screen)
- Admin: `admin-portal/src/pages/` (Dashboard, Users, SellerApplications, Products, ModelRequests, Orders, Transactions, Reports, Banners, AuditLogs, Settings) + `lib/screens/admin/`
- Old paper text extracted from `CUFMAI FINALSSS.docx` (paras 226–234, Figure 4 caption) for comparison.
