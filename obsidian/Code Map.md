# 🗺️ Code Map — lib/ → MOCs

> The **inverse index**: start from a file or folder, jump to its documentation. Use this when you know *where* the code is but want *why* it works. The forward direction (docs → code) lives in the MOCs. **#moc**

**How to use:** find your folder below → the arrow tells you which MOC documents that area. Key files are listed with their role so you can also search by filename.

---

## 📱 App root (`lib/`)

| File | Role | → MOC |
|------|------|-------|
| `main.dart` | Entry point: `CUFMAIApp`, MultiProvider setup, Material 3 theme, `DeepLinkHost` (`solvision://checkout/gcash/*` cold-start resume) | 🏠 Home |
| `firebase_options.dart` | FCM config | [[obsidian/MOCs/06 - Notifications & Messaging|🔔 Notifications]] |

## 🧭 Screens (`lib/screens/`)

| Folder | What's in it | → MOC |
|--------|-------------|-------|
| `screens/customer/` | 4-tab `CustomerShell` + home (hero, sticky search), product detail, cart, checkout, GCash payment, tracking, customization, AR/foot scan (wall calibration), addresses, reviews, my-orders, inbox, buy-again, recently viewed, tag products | [[obsidian/MOCs/02 - Customer App|📱 Customer App]] |
| `screens/seller/` | 5-tab `SellerShell`: dashboard, orders, products, POS (+ barcode scanner, receipt, history), reports, GCash queue/settings/ref-scanner, inbox, notification center, store profile/schedule/reviews, business verification, store CRUD (create/edit/location picker) | [[obsidian/MOCs/03 - Seller Module|👞 Seller Module]] |
| `screens/admin/` | Mobile admin: `admin_shell`, `admin_dashboard_screen`, `manage_users_screen`, `monitor_products_screen`, `seller_approval_screen` (Tier 1 queue + Business Docs tab), `seller_business_docs_review_screen`, `admin_analytics_screen`, `admin_orders_screen`, `admin_reports_screen`, `admin_transactions_screen`, `admin_settings_screen`, `manage_deletion_requests_screen` | [[obsidian/MOCs/04 - Admin Portal|🛡️ Admin Portal]] + [[obsidian/MOCs/00 - Auth & Accounts|🔐 Auth]] |
| `screens/auth/` | `account_entry_screen` (merged create/signin), `customer_register_screen`, `seller_application_flow`, `foot_profile_onboarding_screen`, `pending_approval_screen`, splash, onboarding, edit_profile, `seller_approved_celebration_screen` | [[obsidian/MOCs/00 - Auth & Accounts|🔐 Auth]] |
| `screens/shared/` | `profile_screen`, `settings_screen`, `account_switcher_screen`, `account_security_screen`, `manage_login_device_screen`, `terms_privacy_screen`, `about_cufmai_screen`, `faq_screen`, `whats_new_screen`, `help_menu_screen`, `support_chat_screen`, `wrong_account_screen`, `following_list_dialog` | [[obsidian/MOCs/02 - Customer App|📱 Customer App]] + [[obsidian/MOCs/00 - Auth & Accounts|🔐 Auth]] (account management) |
| `screens/customer/widgets/` | `home_hero.dart` (full-bleed hero), `home_sticky_search_bar.dart` (sticky search) | 📱 Customer |
| `screens/store/` | `store_screen`, `store_profile_screen`, `collection_screen`, `rate_store_screen` + `widgets/` (hero card/carousel, cross-store product row, stitch painter) | [[obsidian/MOCs/07 - Products, Stores & Features|🛍️ Products & Stores]] |
| `screens/auth_gate.dart` | Post-auth role routing + suspended-account screen | [[obsidian/MOCs/00 - Auth & Accounts|🔐 Auth]] |
| `screens/notifications_screen.dart` | Customer notification feed (category tabs) | [[obsidian/MOCs/06 - Notifications & Messaging|🔔 Notifications]] |

## 🔌 Services (`lib/services/` — data access, singletons)

| Service | Role | → MOC |
|---------|------|-------|
| `auth_service.dart` | Signup/login, `ensureUser`, `completeSellerApplication`, Tier 2 + admin verdict RPCs, 5× profile retry | [[obsidian/MOCs/00 - Auth & Accounts|🔐 Auth]] |
| `biometric_service.dart` | Biometric auth + FlutterSecureStorage | 🔐 Auth |
| `verification_document_service.dart` | Private-bucket uploads + signed URLs | 🔐 Auth |
| `cart_service.dart` | Cart CRUD, `validateCartForCheckout()` (reads `inventory`) | [[obsidian/MOCs/01 - Checkout, Orders & Payments|💳 Checkout]] |
| `order_service.dart` | Order placement, store filtering, recent orders, counts | 💳 Checkout / 👞 Seller |
| `supabase_service.dart` | Legacy catch-all; `createOrder()` (**cash-on-pickup only** now), `fetchProducts`, `_syncVariantStock` | 💳 Checkout / [[obsidian/MOCs/05 - Database & Supabase|🗄️ DB]] |
| `gcash_payment_service.dart` | **Attempt #6** intent create / status poll / cancel / fee fetch | 💳 Checkout |
| `direct_gcash_service.dart` | **DORMANT (#5)** RPC wrappers for legacy direct flow | 💳 Checkout |
| `deep_link_service.dart` | `solvision://checkout/gcash/*` stream + matcher | 💳 Checkout |
| `product_service.dart` | Product CRUD, images, variants, `_syncInventoryFromVariants()`, `syncProductActiveStatus()` | [[obsidian/MOCs/07 - Products, Stores & Features|🛍️ Products]] / 👞 Seller |
| `sales_service.dart` | Revenue (online+POS), today/weekly/monthly/trend, reports | 👞 Seller |
| `store_service.dart` | Store CRUD, follow/unfollow, stories, `getMyStore` | 🛍️ Products & Stores |
| `review_service.dart` / `report_service.dart` | Reviews (product + store) / user reports | 🛍️ Products & Stores |
| `sale_tag_service.dart` / `sale_price` utils | On-sale tags/pricing | 🛍️ Products & Stores |
| `address_service.dart` | Customer addresses | 📱 Customer |
| `foot_measurement_service.dart` / `ar_core_channel.dart` | Foot scan + AR (simulated) | 📱 Customer |
| `notification_service.dart` | Customer notifications CRUD | [[obsidian/MOCs/06 - Notifications & Messaging|🔔 Notifications]] |
| `seller_notification_service.dart` | Seller notifications + creation helpers (`createStaleOrder`) | 🔔 Notifications |
| `push_notification_service.dart` | FCM token mgmt + foreground display | 🔔 Notifications |
| `message_service.dart` | Chat CRUD, realtime subs, typing, push trigger | 🔔 Messaging |
| `connectivity_service.dart` | Online/offline stream | 🏠 Home (cross-cutting) |
| `update_checker.dart` | Release notes / update info | 🗺️ Roadmap & Logs |
| `upload_service.dart` | Generic Storage upload/delete | 🗄️ DB |
| `profile_service.dart` | Profile CRUD, avatar upload, account management | 🔐 Auth |
| `seller_application_draft_store.dart` | 30-min draft resume for seller application (SharedPreferences + FlutterSecureStorage) | 🔐 Auth |

## 🧠 Providers (`lib/providers/` — state management)

| Provider | Role | → MOC |
|----------|------|-------|
| `auth_provider.dart` | Session, profile, `signUpCustomer/Seller`, saveFootProfile | 🔐 Auth |
| `seller_application_controller.dart` | Scoped seller-flow form/upload state | 🔐 Auth |
| `cart_provider.dart` | Hybrid cart, selection, totals, delivery fee | 💳 Checkout |
| `order_provider.dart` | `placeOrder()`, orders state, customizations | 💳 Checkout / 👞 Seller |
| `product_provider.dart` | Browsing, categories, search, `loadSellerProducts()`, low-stock | 🛍️ Products / 👞 Seller |
| `address_provider.dart` | Address book | 📱 Customer |
| `foot_measurement_provider.dart` | Foot scan state | 📱 Customer |
| `review_provider.dart` | Reviews + store reviews + replies | 🛍️ Products & Stores |
| `follow_provider.dart` | Store follows | 🛍️ Products & Stores |
| `sale_tag_provider.dart` | On-sale state | 🛍️ Products & Stores |
| `notification_provider.dart` | Customer notification state | 🔔 Notifications |
| `seller_notification_provider.dart` | Seller state + realtime + unread badge | 🔔 Notifications |
| `message_provider.dart` | Inbox-level chat state + unread badge | 🔔 Messaging |
| `chat_attachment_provider.dart` | Failed-attachment persistence | 🔔 Messaging |
| `update_provider.dart` | What's-new / release notes | 🗺️ Roadmap & Logs |
| `banner_provider.dart` | Home screen banner carousel data | 📱 Customer |

## 🧩 Models (`lib/models/`)

`product_models.dart` (variants/customizations) · `cart_item_with_details.dart` (incl. `CartValidationResult`) · `store.dart` · `seller_report_data.dart` · `sales_trend_data.dart` · `revenue_point.dart` · `app_notification.dart` + `notification_category.dart` · `foot_measurement.dart` · `address_model.dart` · `followed_store.dart` · `seller_application_data.dart` · `update_info.dart`
→ spread across all MOCs (mostly [[obsidian/MOCs/05 - Database & Supabase|🗄️ DB]] shapes).

## 🛠️ Utils (`lib/utils/`)

| File | Role | → MOC |
|------|------|-------|
| `cart_helpers.dart` | Shared `resolveVariant()`, `resolveInventoryStock()`, `normalizeSize()` | 💳 Checkout |
| `product_stock.dart` | `purchasableProducts()` — hide/reappear logic | 🛍️ Products |
| `sale_price.dart` | Sale pricing helpers | 🛍️ Products |
| `recently_viewed.dart` | Recently-viewed cache (SharedPreferences) | 📱 Customer |
| `delivery_date.dart` | Estimated delivery text | 📱 Customer / 💳 Checkout |
| `gcash_ref_extractor.dart` | Scan/parse GCash reference numbers | 💳 Checkout |
| `customer_profile_fields.dart` | Birthday/gender validation, EU sizes, `formatBirthdayForDb` | 🔐 Auth |
| `auth_error_messages.dart` | Friendly auth error mapping | 🔐 Auth |
| `foot_detector.dart` / `mlkit_*` / `qr_image_crop.dart` / `ar_foot_measurement_pipeline.dart` / `foot_measurement_utils.dart` | Foot scan/AR pipeline | 📱 Customer |
| `notification_formatters.dart` | Notification display formatting | 🔔 Notifications |
| `product_grid_ratio.dart` | Grid aspect-ratio helper for product grids | 📱 Customer |
| `dev_mode.dart` | Dev-mode bypass (swipe gesture) — REMOVE BEFORE RELEASE | 🔐 Auth |

## 🧱 Widgets (`lib/widgets/`)

| Folder / file | Role | → MOC |
|---------------|------|-------|
| `widgets/` root (`sole_*.dart`, `SoleCard`, `SolePrimaryButton`, `SoleTimeline`, `SoleStarRating`, `SoleStatusChip`, `ShimmerBox`, `EmptyStateWidget`, …) | **Design system** — reuse these, don't introduce raw Material | 🏠 Home (app-wide) |
| `widgets/seller/` | `seller_metric_card`, `seller_sparkline`, `seller_alert_chip`, `seller_order_card`, `seller_stacked_area_chart`, `seller_revenue_doughnut`, `seller_status_chip`, … | 👞 Seller |
| `widgets/auth/` | `signup_scaffold`, `auth_text_field`, `password_strength_meter`, `document_upload_tile`, `step_progress_indicator`, `terms_policy_tile` | 🔐 Auth |
| `widgets/chat/` | `chat_view.dart` — the shared chat UI (both roles) | 🔔 Messaging |
| `widgets/admin/` | `verification_doc_viewer.dart` (signed-URL doc review zoom) | 🔐 Auth |
| `sole_status_chip.dart` | Styles `awaiting_payment`, `payment_conflict`, etc. | 💳 Checkout |
| `customer_foot_profile_banner.dart` | Foot-profile reminder on Home | 🔐 Auth |
| `pending_gcash_checkout_sheet.dart`, `order_cancellation_sheet.dart`, `order_change_request_sheet.dart`, `order_quick_message_sheet.dart`, `messages_quick_preview_sheet.dart`, `report_modal.dart`, `size_guide_modal.dart`, `sale_countdown_overlay.dart`, `hanging_sale_tag.dart` | Feature sheets/overlays | Spread (checkout/customer/products) |
| `buy_again_section.dart` | Buy-again products section (order history → cart) | 📱 Customer |
| `recently_viewed_section.dart` | Recently-viewed products row on home | 📱 Customer |
| `connectivity_banner.dart` | Offline/online status banner | 🏠 Home (cross-cutting) |
| `horizontal_product_card.dart` | Horizontal product card for lists | 📱 Customer |
| `sole_badge.dart` | Badge/notification dot | 🏠 Home (app-wide) |
| `sole_switch.dart` | Toggle switch | 🏠 Home (app-wide) |
| `sole_ar_pill.dart` | AR fitting pill button | 📱 Customer |
| `error_retry_widget.dart` | Error state with retry | 🏠 Home (cross-cutting) |
| `shimmer_group.dart` | Grouped shimmer loading placeholder | 🏠 Home (cross-cutting) |
| `no_internet_view.dart` | Full-screen offline view | 🏠 Home (cross-cutting) |
| `countdown_delete_button.dart` | Timer-based delete confirmation | 🏠 Home (cross-cutting) |
| `floating_message_button.dart` | Floating action button for messages | 🔔 Messaging |
| `fly_to_cart_animation.dart` | Add-to-cart fly animation | 📱 Customer |
| `custom_popup_menu.dart` | Custom popup menu | 🏠 Home (app-wide) |
| `sale_price_tape.dart` | Sale price tape overlay | 🛍️ Products |
| `release_note_card.dart` | What's-new release note card | 🗺️ Roadmap & Logs |
| `app_error_toast.dart` | Error toast notification | 🏠 Home (cross-cutting) |

## ⚙️ Constants & exceptions

| File | Role | → MOC |
|------|------|-------|
| `constants/app_constants.dart` | **Supabase URL + anon key, colors, typography, roles, statuses** — the config hub | 🏠 Home (everything routes here) |
| `constants/seller_theme_constants.dart` | Seller espresso/cream theme | 👞 Seller |
| `exceptions/stock_unavailable_exception.dart` | Friendly out-of-stock error | 💳 Checkout |

---

## 🔁 Quick cross-reference (file → doc by name)

Looking for a specific doc? The reverse index lives in [[obsidian/Onboarding|🧑‍💻 Onboarding]] (Step 2) and the [[docs/AI/feature_file_lookup_guide|🔍 Feature file lookup guide]] (features → exact files). For DB schema shapes see [[SCHEMA_REFERENCE|SCHEMA_REFERENCE.md]] and [[docs/SoleVision_Complete_Documentation|📘 Master documentation]].

## 🔗 Related

- [[obsidian/Home|🏠 Home]] · [[obsidian/Onboarding|🧑‍💻 Onboarding]] · [[obsidian/Tasks|✅ Task board]]
