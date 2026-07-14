# SoleVision — AI Development Guide

**Last Updated:** July 9, 2026  
**Purpose:** Comprehensive reference for AI agents working on this codebase.

---

## Quick Summary

SoleVision is a multi-role marketplace connecting **customers**, **sellers** (artisans), and **admins** for handcrafted shoe retail in Carcar City, Cebu, Philippines. It's built with Flutter (mobile), React (admin portal), and Supabase (backend).

---

## Tech Stack

| Layer | Technology | Key Packages |
|-------|-----------|--------------|
| **Mobile App** | Flutter 3.12+ | provider, supabase_flutter, google_fonts, flutter_map |
| **Admin Portal** | React 18 + Vite | TanStack Query, Supabase JS, Tailwind CSS, Recharts |
| **Backend** | Supabase | PostgreSQL, Auth, Storage, RLS |
| **Maps** | MapTiler + flutter_map | Address entry with pin-drop |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Supabase Cloud                          │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐  ┌──────────┐ │
│  │   Auth   │  │ Postgres │  │  Storage   │  │ Realtime │ │
│  │ (JWT)   │  │   (RLS)  │  │ (images)   │  │ (unused) │ │
│  └────┬─────┘  └────┬─────┘  └─────┬──────┘  └──────────┘ │
└───────┼──────────────┼──────────────┼───────────────────────┘
        │              │              │
   ┌────┴────┐    ┌────┴────┐    ┌───┴────┐
   │ Flutter │    │ React   │    │ Admin  │
   │ Mobile  │    │  Web    │    │ Portal │
   └─────────┘    └─────────┘    └────────┘
```

**Key Architectural Decisions:**
- `store_id` is a direct column on `orders` (not joined via products)
- Two-tier inventory: `product_variants` (per size+color) + `inventory` (aggregated per size)
- Services throw exceptions; Providers catch and set `_errorMessage` for UI
- All storage buckets are public (product images, avatars, store assets)

**⚠️ Schema Drift:** `supabase/schema.sql` is outdated. Always refer to documentation, not schema.sql.

---

## User Roles

| Role | Permissions | Access |
|------|------------|--------|
| **Customer** | Browse, order, track, request customization | Mobile app |
| **Seller** | Manage store/products/orders, POS | Mobile app |
| **Admin** | Approve sellers, monitor, analytics | Mobile + Admin Portal |

---

## Project Structure

```
app/
├── lib/
│   ├── main.dart                    # App entry, Supabase init, Provider setup
│   ├── constants/app_constants.dart # Colors, typography, Supabase creds, roles
│   ├── models/                      # Data models (ProductVariant, etc.)
│   ├── providers/                   # ChangeNotifier state management
│   │   ├── auth_provider.dart       # Login/logout/profile
│   │   ├── cart_provider.dart       # Cart with optimistic updates
│   │   ├── order_provider.dart      # Orders with stock error handling
│   │   └── product_provider.dart    # Product browsing
│   ├── services/                    # Supabase API calls (singletons)
│   │   ├── supabase_service.dart    # createOrder(), fetchProducts()
│   │   ├── product_service.dart     # CRUD, variants, inventory sync
│   │   ├── cart_service.dart        # Cart CRUD, validateCartForCheckout()
│   │   ├── sales_service.dart       # POS, revenue calculations
│   │   └── auth_service.dart        # Auth with retry logic
│   ├── screens/
│   │   ├── auth/                    # Login, register, onboarding, splash
│   │   ├── customer/                # Home, product detail, cart, checkout, orders
│   │   ├── seller/                  # Dashboard, POS, products, orders, reports
│   │   └── admin/                   # Dashboard, users, approvals, monitor
│   ├── widgets/                     # Reusable UI components (SoleCard, SolePrimaryButton, etc.)
│   ├── utils/cart_helpers.dart      # Shared helpers: resolveVariant(), normalizeSize()
│   └── exceptions/                  # Custom exceptions (StockUnavailableException)
├── supabase/
│   ├── schema.sql                   # ⚠️ OUTDATED - use docs as reference
│   └── migrations/                  # SQL migrations (check dates, verify applied)
├── admin-portal/
│   ├── src/
│   │   ├── pages/                   # Dashboard, Users, Products, Orders, Analytics
│   │   ├── components/              # Layout, Products, Users, UI components
│   │   ├── hooks/                   # React Query hooks for data fetching
│   │   └── lib/supabase.js         # Supabase client config
│   └── .env                         # VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY
└── docs/                            # All documentation (you are here)
```

---

## Key Patterns to Follow

### 1. Service Layer Pattern
```dart
// Services are singletons that throw exceptions
class ProductService {
  static final ProductService instance = ProductService._();
  
  Future<String> createProduct({...}) async {
    // Do work, throw on error
    throw Exception('Failed to create product: $e');
  }
}
```

### 2. Provider Pattern
```dart
// Providers catch exceptions and set _errorMessage
class OrderProvider extends ChangeNotifier {
  String? _errorMessage;
  
  Future<void> placeOrder(...) async {
    try {
      _errorMessage = null;
      await SupabaseService.instance.createOrder(...);
    } catch (e) {
      _errorMessage = e.toString(); // UI reads this
    }
  }
}
```

### 3. Inventory Sync Pattern
```dart
// product_variants = source of truth (per size+color)
// inventory = derived table (aggregated per size)
// Always call _syncInventoryFromVariants() after variant changes
```

### 4. Size Resolution Pattern
```dart
// Used in createOrder, recordSale, validateCartForCheckout
// 1. Exact match: cart size matches inventory size
// 2. Numeric match: strip "EU"/"US" prefix, then compare
// 3. Fallback: first available inventory size
```

---

## Critical Gotchas

### ⚠️ DO NOT
- **Don't use `supabase/schema.sql`** — it's outdated and misleading
- **Don't hardcode API keys** — use AppConstants or environment variables
- **Don't bypass RLS** — all data access must go through RLS policies
- **Don't assume `product_variants.stock` is accurate** — use `inventory.stock` as authoritative
- **Don't modify DB triggers without understanding RLS** — triggers without SECURITY DEFINER run as the calling user

### ⚠️ ALWAYS
- **Always verify SQL migrations are applied** — check live database, not just file existence
- **Always use `maybeSingle()` or `limit(1)` when expecting single rows**
- **Always handle null `variant_id` in cart** — AR fitting or legacy products may not have variants
- **Always use `resolveInventoryStock()` for size resolution** — don't reimplement

### ⚠️ KNOWN ISSUES
- `isFollowing()` returns false synchronously (use `isFollowingAsync()`)
- `story_entries` has NO `title` column (removed from live DB)
- Products table PK is `TEXT` (UUID stored as text, not native UUID)
- CSV export is a stub (shows SnackBar only)

---

## Color Palette

| Name | Hex | Usage |
|------|-----|-------|
| Primary (Burnished Clay) | `#8B5A2B` | Buttons, active states, brand accent |
| Secondary (Carob Dark) | `#3B2314` | Text, icons, sidebar background |
| Accent (Celadon Teal) | `#4ECDC4` | AR mode, CTAs, highlights |
| Surface Light (Off-White Suede) | `#F5F0EB` | Backgrounds |
| Success (Olive Stitch) | `#6B8F47` | Success states |
| Error (Crimson Welt) | `#D64545` | Error states |

**Typography:**
- Headlines: Playfair Display
- Body: DM Sans
- Monospace: JetBrains Mono

---

## Key Files Reference

### Configuration
- `lib/constants/app_constants.dart` — All constants (colors, Supabase creds, roles)
- `admin-portal/src/lib/supabase.js` — Admin portal Supabase client
- `admin-portal/src/lib/constants.js` — Admin portal roles, statuses, formatting

### Critical Services
- `lib/services/supabase_service.dart` — `createOrder()` with orphan cleanup
- `lib/services/product_service.dart` — `_syncInventoryFromVariants()`
- `lib/services/cart_service.dart` — `validateCartForCheckout()`
- `lib/utils/cart_helpers.dart` — Shared helpers: `resolveVariant()`, `normalizeSize()`

### Critical Screens
- `lib/screens/customer/checkout_screen.dart` — Full checkout with validation
- `lib/screens/customer/product_detail_screen.dart` — `_buildSizesMap()`, `_addToCart()`
- `lib/screens/seller/pos_screen.dart` — Point-of-sale

---

## Common Tasks

### Adding a New Feature
1. Create service method in appropriate `*_service.dart`
2. Add provider method in appropriate `*_provider.dart` (catch exceptions!)
3. Create screen in appropriate `screens/` subfolder
4. Add navigation if needed
5. Test all three roles (customer, seller, admin)

### Modifying Database
1. Create migration file in `supabase/migrations/` with timestamp prefix
2. Document in `docs/` with before/after
3. **Actually apply to live database** — don't forget!
4. Update this documentation

### Fixing Bugs
1. Check if the bug is in app code or database (RLS, triggers, constraints)
2. For stock issues: check `inventory.stock` not `product_variants.stock`
3. For checkout issues: check `createOrder()` and `decrement_inventory_on_order()` trigger
4. Test with console logging — add `[TAG]` prefixed logs

---

## Environment Variables

| Variable | Location | Description |
|----------|----------|-------------|
| `AppConstants.url` | `lib/constants/app_constants.dart` | Supabase project URL |
| `AppConstants.anonKey` | `lib/constants/app_constants.dart` | Supabase anon key |
| `AppConstants.maptilerKey` | `lib/constants/app_constants.dart` | MapTiler API key |
| `VITE_SUPABASE_URL` | `admin-portal/.env` | Same Supabase URL |
| `VITE_SUPABASE_ANON_KEY` | `admin-portal/.env` | Same anon key |

---

## Running the Project

### Flutter Mobile App
```bash
cd app
flutter pub get
flutter run
```

### React Admin Portal
```bash
cd admin-portal
npm install
cp .env.example .env  # Add your Supabase credentials
npm run dev
# Opens at http://localhost:5173
```

---

## Database Tables Reference

| Table | Purpose | Key Columns |
|-------|---------|-------------|
| `profiles` | Users with roles | id (FK→auth.users), role, seller_status |
| `stores` | Artisan stores | id, owner_id→profiles, name, is_active |
| `products` | Products | id (TEXT), store_id→stores, seller_id→profiles, price, is_active |
| `product_variants` | Stock per size+color | id, product_id→products, size, color, stock |
| `inventory` | Aggregated stock per size | product_id+size (PK), stock |
| `orders` | Online orders | id, customer_id→profiles, store_id→stores, status, total_amount |
| `order_items` | Line items per order | order_id→orders, product_id→products, size, quantity |
| `sales_transactions` | POS transactions | id, store_id→stores, seller_id→profiles |
| `cart_items` | Server-side cart | user_id→profiles, product_id→products, size |

---

## SQL Migrations

| File | Date | Purpose | Applied? |
|------|------|---------|----------|
| `20260702_notifications.sql` | July 2 | Notifications table | ✅ |
| `20260703_add_cart_items_size.sql` | July 3 | Add size column to cart_items | ✅ |
| `20260704_add_orders_delete_policy.sql` | July 4 | DELETE RLS on orders | ✅ |
| `20260704_fix_trigger_security_definer.sql` | July 4 | SECURITY DEFINER on triggers | ✅ |
| `20260705_add_customer_addresses.sql` | July 5 | Customer addresses table | ✅ |
| `20260708_fix_customer_addresses_rls.sql` | July 8 | Fix RLS for addresses | ✅ |
| `20260709_one_store_per_seller.sql` | July 9 | Enforce one store per seller | ✅ |
| `20260709_tighten_products_rls.sql` | July 9 | Tighten product RLS | ✅ |

---

## Debugging Tips

### Stock Issues
```sql
-- Check inventory for a product
SELECT * FROM inventory WHERE product_id = 'PRODUCT_ID';

-- Check product_variants
SELECT * FROM product_variants WHERE product_id = 'PRODUCT_ID';

-- Compare: inventory.stock vs product_variants.stock
```

### RLS Issues
```sql
-- Check current user's role
SELECT role FROM profiles WHERE id = auth.uid();

-- Check RLS policies
SELECT * FROM pg_policies WHERE tablename = 'TABLE_NAME';
```

### Trigger Issues
```sql
-- Check trigger functions
SELECT * FROM pg_proc WHERE proname LIKE 'decrement_inventory%';

-- Check if SECURITY DEFINER is set
SELECT proconfig FROM pg_proc WHERE proname = 'decrement_inventory_on_order';
```

---

## Documentation Files

| File | Purpose |
|------|---------|
| `docs/SoleVision_Complete_Documentation.md` | Full project documentation |
| `docs/SESSION_LOG_*.md` | Session logs with fix history |
| `docs/VERIFICATION_AUDIT_JULY_4_2026.md` | Audit proving fixes were never deployed |
| `docs/createOrder_function_reference.md` | Annotated createOrder() flow |
| `docs/addToCart_and_fetchCart_reference.md` | Add-to-cart flow |
| `docs/PROJECT_HANDOFF.md` | Project handoff with decisions |

---

## Version Control

**⚠️ CRITICAL:** This project has NO git repository. All changes are raw file modifications with no audit trail. When making changes:
1. Document what you changed
2. Include before/after comparisons
3. Note any SQL migrations that need to be applied
4. Test thoroughly before marking as complete

---

*SoleVision AI Development Guide — July 9, 2026*
