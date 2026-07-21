# SoleVision Customer-Side UI/UX Audit

**Date:** July 21, 2026  
**Auditor:** Buffy (AI Product Design Review)  
**Scope:** Home, Store, Notifications, Profile, Cart, Checkout, Orders, Tracking, Product Detail, AR Fitting

---

## 1. Overall Consistency

### ✅ Strengths
- **Unified color system**: `AppConstants` defines a cohesive palette (primary teal, secondary dark, accent teal, error red, surface cream) used consistently across all screens.
- **Shared component library**: `SoleCard`, `SolePrimaryButton`, `SoleBadge`, `SoleStatusChip`, `SoleTimeline`, and `EmptyStateWidget` are reused across screens, creating visual consistency.
- **Typography**: `AppConstants.headlineStyle()` and `AppConstants.bodyStyle()` are used throughout, ensuring consistent text hierarchy.
- **Noise overlay**: The subtle `AppConstants.noiseOverlay(opacity: 0.03)` adds texture consistently across all scaffold backgrounds.
- **Card patterns**: `SoleCard` with `AppConstants.warmShadow` and `AppConstants.cardRadius` creates a unified card aesthetic.

### ⚠️ Inconsistencies Found
| Issue | Screens Affected | Severity |
|-------|-----------------|----------|
| AppBar transparency varies — some use `Colors.transparent`, others use `AppConstants.surfaceLight` | Profile uses `surfaceLight`, Home/Orders/Notifications use `transparent` | Low |
| Section header styles differ — some use `headlineStyle(fontSize: 20)`, others use `bodyStyle(fontWeight: FontWeight.bold, fontSize: 16)` | My Orders section headers vs. Checkout section headers | Low |
| Inconsistent use of `withValues(alpha:)` vs `withOpacity()` for transparency | Cart screen uses `withOpacity()`, Checkout uses `withValues(alpha:)` | Low |
| Bottom padding varies — some screens use 80px, others use 40px | Home (80px), Checkout (40px), Profile (80px) | Medium |

---

## 2. Missing UI Elements

### 🔴 High Priority (Expected by users)
| Missing Element | Impact | Recommendation |
|----------------|--------|----------------|
| **Wishlist/Favorites** | No way to save products for later — major conversion blocker | Add heart icon on product cards + dedicated wishlist screen |
| **Promo banners / Sales section** | Home screen has static featured banners but no dynamic sale/discount indicators | Add "Sale" badges on discounted products, seasonal promo section |
| **Estimated delivery times** | Checkout shows delivery fee but no estimated arrival date | Add "Estimated delivery: 3-5 days" in checkout and order tracking |
| **Return/refund policy visibility** | Terms & Privacy page shows "Coming soon" placeholder | Implement actual policy page |
| **Secure checkout indicators** | No padlock icon or "Secure Payment" text in checkout | Add security badge near payment method selection |

### 🟡 Medium Priority
| Missing Element | Impact | Recommendation |
|----------------|--------|----------------|
| **Search filters/sort** | Search bar exists on Home but no sort by price/rating/popularity or filter by size/price range | Add filter bottom sheet or sort dropdown |
| **Quantity limit display** | Cart allows quantity changes but doesn't show max available stock | Show "Max: X" near quantity stepper |
| **Order progress percentage** | Tracking shows timeline but no visual percentage bar | Add progress indicator (e.g., "60% complete") |
| **Recently viewed products** | No history of browsed items | Add "Recently Viewed" section on Home |

### 🟢 Low Priority
| Missing Element | Impact | Recommendation |
|----------------|--------|----------------|
| **Social sharing** | Cannot share products with friends | Add share button on product detail |
| **Size guide** | No size conversion chart for EU sizing | Add size guide modal on product detail |

---

## 3. Navigation & Information Architecture

### ✅ Strengths
- **Clear bottom nav**: 4-tab structure (Home → Store → Notifications → Profile) is intuitive for a marketplace app.
- **Deep-linking works**: Notification taps correctly navigate to order tracking or chat.
- **"Continue Browsing" chip**: Nice touch on Home screen to return to last visited store.
- **Cart icon in AppBar**: Always accessible via `CartIconButton` on Home and Product Detail.

### ⚠️ Issues Found
| Issue | Severity | Details |
|-------|----------|---------|
| **No direct access to My Orders from bottom nav** | Medium | Users must go Profile → My Orders (2 taps). Consider adding Orders as a 5th tab or a prominent shortcut |
| **Store tab unclear** | Medium | "Store" tab label is ambiguous — is it "Browse Stores" or "My Store"? Consider renaming to "Browse" or "Shops" |
| **Cart not accessible from all screens** | Medium | Cart icon only appears on Home and Product Detail — not on Store, Notifications, or Profile |
| **Back navigation inconsistency** | Low | Some screens have AppBar back buttons, others rely on system back. Customer Shell uses IndexedStack (no back stack) |
| **AR Fitting entry point** | Low | Only accessible from product detail "Try On" — no dedicated section for AR on Home |

---

## 4. Feedback & Status Communication

### ✅ Strengths
- **Add to cart animation**: `FlyToCartAnimation` provides delightful visual feedback when adding items.
- **Checkout success**: Animated checkmark with `ScaleTransition` and elastic curve on order confirmation.
- **SnackBars for actions**: Delete from cart, profile save, order confirm all show appropriate SnackBars.
- **Optimistic updates**: Cart and notification operations update UI immediately, then sync with server.
- **Undo support**: Notifications screen supports undo on delete with SnackBar action.
- **Stock validation**: Checkout validates stock and prices before submission, showing clear banners for issues.

### ⚠️ Issues Found
| Issue | Severity | Details |
|-------|----------|---------|
| **"Buy Now" is misleading** | High | Tapping "Buy Now" adds to cart then shows "Processing checkout..." SnackBar but doesn't navigate to checkout. Users expect immediate checkout |
| **No loading skeleton on Home grid** | Medium | Initial load shows a single `CircularProgressIndicator` — shimmer skeletons would feel faster |
| **Checkout "Go to Cart" on error** | Medium | When stock error occurs, the SnackBar has a "Go to Cart" button but it just pops the screen — doesn't actually navigate to cart |
| **No haptic feedback** | Low | Only notifications screen uses `HapticFeedback` — add to cart add/remove, checkout confirm |
| **Quantity change feedback** | Low | No animation when quantity changes in cart |

---

## 5. Accessibility

### ✅ Strengths
- **Semantics on Following stat**: Profile screen uses `Semantics(label: ...)` for screen reader support.
- **Notification badge semantics**: The new bell icon badge includes `Semantics(label: 'Notifications, N unread')`.
- **Sufficient contrast**: Primary teal on white background passes WCAG AA. Error red on white is also compliant.

### ⚠️ Issues Found
| Issue | Severity | Details |
|-------|----------|---------|
| **Tap target sizes** | High | Quantity buttons in cart are only 28x28px — below Apple's 44pt minimum. Size selector chips are 48x48px (good) |
| **Missing Semantics on most interactive elements** | High | Cart checkboxes, delete buttons, payment radio buttons lack `Semantics` labels |
| **Color-only status indicators** | Medium | `SoleStatusChip` uses color + text, but some status colors are similar (amber pending vs. processing blue) |
| **No screen reader labels on product cards** | Medium | `SoleProductCard` lacks Semantics for product name, price, and action buttons |
| **Font size concerns** | Low | Some text at 9-10px (badge counts, timestamps) may be hard to read for users with mild visual impairments |

---

## 6. Onboarding & Empty States

### ✅ Strengths
- **Cart empty state**: Uses `EmptyStateWidget` with icon, title, and helpful subtitle ("Browse products and try them on in AR!").
- **Orders empty state**: Uses `EmptyStateWidget` with contextual message.
- **Notifications empty state**: Clear icon + text explaining "Order updates will appear here".
- **Reviews empty state**: "No reviews yet — be the first!" encourages action.
- **Search no results**: Shows "No shoes match your criteria" with search icon.

### ⚠️ Issues Found
| Issue | Severity | Details |
|-------|----------|---------|
| **No first-time onboarding** | High | New users get thrown directly into the Home screen with no walkthrough of key features (AR fitting, following stores, messaging) |
| **Empty cart doesn't show recommendations** | Medium | "Your cart is empty" doesn't suggest popular or recently viewed products |
| **No "Getting Started" checklist** | Medium | No guidance for new users to complete profile, browse stores, or make first purchase |
| **Profile "Terms & Privacy" is placeholder** | Medium | Shows "Coming soon" — erodes trust for new users |
| **No empty state for Following** | Low | If no stores followed, the Following dialog should show suggestions |

---

## 7. Trust & Conversion Elements

### ✅ Strengths
- **Reviews with star ratings**: Product detail shows aggregate rating breakdown with bar chart.
- **"Write a Review" button**: Encourages social proof collection.
- **Order tracking timeline**: `SoleTimeline` provides clear visibility into order progress.
- **Store profile pages**: Users can visit individual artisan stores.
- **AR Virtual Fitting**: Unique differentiator that builds confidence in purchase.
- **Following stores**: Creates engagement loop and repeat visits.

### ⚠️ Issues Found
| Issue | Severity | Details |
|-------|----------|---------|
| **No price comparison / value indicator** | Medium | No "Original price" vs "Sale price" or "Best value" markers |
| **No secure payment badges** | Medium | Checkout shows GCash/Card options but no trust badges (Visa/Mastercard logos, SSL badge) |
| **No delivery guarantee text** | Medium | No "Free returns within 7 days" or satisfaction guarantee messaging |
| **No seller ratings visible** | Medium | Store profiles exist but seller rating/trust score isn't prominent |
| **No "X people bought this"** | Low | Social proof count missing from product cards |
| **No estimated delivery date** | High | Critical for purchase confidence — users don't know when they'll receive the item |

---

## 8. Mobile Usability Specifics

### ✅ Strengths
- **Pull-to-refresh**: Implemented on Home, Orders, and Notifications screens.
- **Sticky checkout bar**: Cart checkout bar stays visible at bottom while scrolling.
- **Floating message button**: Draggable chat FAB doesn't block important content.
- **Responsive grid**: Home uses `SliverMasonryGrid` with 2 columns for product browsing.

### ⚠️ Issues Found
| Issue | Severity | Details |
|-------|----------|---------|
| **Quantity buttons too small** | High | 28x28px is below iOS minimum 44pt tap target |
| **Delete button in cart is tiny** | High | 16px icon with 4px padding — hard to tap accurately |
| **Checkout address card** | Medium | "Change" text link is small — consider making the entire card tappable |
| **Payment radio buttons** | Medium | `RadioListTile` hit area is fine, but text labels are small |
| **Product detail "Add to Cart"** | Good | Full-width button at 52px height — excellent thumb reach |
| **Bottom nav bell icon badge** | Good | Positioned at top-right, doesn't overlap other nav items |

---

## 9. Prioritized Recommendations

### 🔴 High Impact (Implement First)
| # | Recommendation | Reason |
|---|---------------|--------|
| 1 | **Add estimated delivery time** to Checkout and Order Tracking | #1 factor in purchase confidence for e-commerce |
| 2 | **Fix "Buy Now" button** — should navigate to checkout, not just add to cart | Misleading UX causes frustration and abandoned checkouts |
| 3 | **Add Wishlist/Favorites feature** | Standard e-commerce expectation — captures high-intent users who aren't ready to buy |
| 4 | **Increase tap target sizes** to minimum 44x44px | Accessibility compliance (WCAG) and reduces accidental taps |
| 5 | **Add first-time onboarding** | New users need guidance to discover AR, Following, and Messaging features |

### 🟡 Medium Impact (Next Sprint)
| # | Recommendation | Reason |
|---|---------------|--------|
| 6 | **Add search filters/sort** | Users can't efficiently find products by size, price, or rating |
| 7 | **Implement Terms & Privacy page** | "Coming soon" erodes trust — legal requirement in many regions |
| 8 | **Add shimmer loading skeletons** to Home grid | Perceived performance improvement — feels faster than spinner |
| 9 | **Add secure checkout badges** in Checkout | Builds trust at the critical conversion moment |
| 10 | **Make Cart accessible from all screens** | Users should be able to check cart contents from anywhere |

### 🟢 Low Impact (Polish)
| # | Recommendation | Reason |
|---|---------------|--------|
| 11 | **Add haptic feedback** on key actions (add to cart, checkout confirm) | Micro-interaction delight |
| 12 | **Add "Recently Viewed" section** on Home | Helps users return to products they were considering |
| 13 | **Add social sharing** on product detail | Organic growth channel |
| 14 | **Add size guide modal** | Reduces returns from incorrect sizing |
| 15 | **Rename "Store" tab to "Browse" or "Shops"** | Reduces ambiguity about tab purpose |

---

## Summary

**Overall Score: 7.5/10**

SoleVision has a solid UI foundation with consistent design language, thoughtful components, and several standout features (AR fitting, store following, real-time messaging). The main gaps are in **conversion-critical elements** (delivery estimates, wishlist, trust badges) and **mobile accessibility** (tap targets, screen reader support). The app feels polished but would benefit from addressing the high-impact items to improve conversion rates and user retention.

---

*Generated by Buffy — Freebuff AI Assistant*
