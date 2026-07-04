# SoleVision — Project Documentation

**Version:** 1.1.0  
**Date:** June 28, 2026  
**Platform:** Flutter (Mobile) + React (Admin Portal)  
**Backend:** Supabase (PostgreSQL + Auth + Storage)  
**Target Market:** Artisan footwear retail — Carcar City, Cebu, Philippines

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Technology Stack](#3-technology-stack)
4. [Database Schema](#4-database-schema)
5. [User Roles & Permissions](#5-user-roles--permissions)
6. [Mobile App — Flutter](#6-mobile-app--flutter)
7. [Admin Portal — React](#7-admin-portal--react)
8. [Services Layer](#8-services-layer)
9. [Data Models](#9-data-models)
10. [State Management](#10-state-management)
11. [Authentication & Security](#11-authentication--security)
12. [UI Design System](#12-ui-design-system)
13. [Feature Breakdown](#13-feature-breakdown)
14. [Setup & Installation](#14-setup--installation)
15. [Deployment Notes](#15-deployment-notes)
16. [Future Enhancements](#16-future-enhancements)
17. [Changelog & Bug Fixes](#17-changelog--bug-fixes)

---

## 1. Project Overview

**SoleVision** is a multi-role marketplace platform for artisan footwear in Carcar City, Cebu. It connects three user types — **customers**, **sellers** (artisans), and **admins** — through a unified mobile application and a web-based admin dashboard.

### Core Value Proposition
- Customers browse and purchase handcrafted shoes from local Carcar artisans
- Sellers manage their stores, products, orders, and point-of-sale operations
- Admins oversee the platform: approve sellers, manage users, monitor products, and view analytics

### Key Highlights
- **Multi-store marketplace**: Customers discover and follow multiple artisan stores
- **Point-of-Sale (POS)**: Sellers process in-person transactions with cash, GCash, or card
- **Custom shoe orders**: Customers request bespoke footwear with custom color, material, and special requests
- **Real-time order tracking**: Order status flows through placed → preparing → ready → received
- **Biometric login**: Fingerprint/face authentication for returning users
- **Admin analytics dashboard**: Revenue trends, order status breakdowns, top products, and seller application trends

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Supabase Cloud                          │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐  ┌──────────┐ │
│  │   Auth   │  │ Postgres │  │  Storage   │  │ Realtime │ │
│  │ (JWT)   │  │   (RLS)  │  │ (images)   │  │          │ │
│  └────┬─────┘  └────┬─────┘  └─────┬──────┘  └──────────┘ │
└───────┼──────────────┼──────────────┼───────────────────────┘
        │              │              │
   ┌────┴────┐    ┌────┴────┐    ┌───┴────┐
   │ Flutter │    │ React   │    │ Admin  │
   │  Mobile │    │  Web    │    │ Portal │
   └─────────┘    └─────────┘    └────────┘
```

### Communication Pattern
- Both the Flutter app and React admin portal connect to the **same Supabase project**
- All data access is governed by **Row Level Security (RLS)** policies
- Supabase Auth handles JWT token management for both clients
- Storage buckets handle image uploads (avatars, product images, store assets)

---

## 3. Technology Stack

### Mobile App (Flutter)
| Component | Technology |
|-----------|-----------|
| Framework | Flutter 3.x (Dart SDK ^3.12.1) |
| State Management | Provider (`provider: ^6.1.2`) |
| Backend | Supabase Flutter SDK (`supabase_flutter: ^2.10.3`) |
| Typography | Google Fonts (`google_fonts: ^6.2.1`) — Playfair Display, DM Sans, JetBrains Mono |
| Image Handling | `cached_network_image: ^3.4.1`, `image_picker: ^1.1.2` |
| SVG Rendering | `flutter_svg: ^2.0.10` |
| Animations | `shimmer: ^3.0.0` |
| Local Storage | `shared_preferences: ^2.2.3`, `flutter_secure_storage: ^9.0.0` |
| Biometrics | `local_auth: ^2.2.0` |
| Unique IDs | `uuid: ^4.5.1` |

### Admin Portal (React)
| Component | Technology |
|-----------|-----------|
| Framework | React 18.3.1 |
| Bundler | Vite 6.2.2 |
| Routing | React Router DOM 6.30.0 |
| State/Data | TanStack React Query 5.67.2 |
| Backend | Supabase JS SDK 2.49.1 |
| Styling | Tailwind CSS 3.4.17 |
| Charts | Recharts 2.15.1 |
| Icons | Lucide React 1.21.0 |

### Backend (Supabase)
| Component | Technology |
|-----------|-----------|
| Database | PostgreSQL with Row Level Security (RLS) |
| Authentication | Supabase Auth (email/password, JWT) |
| Storage | Supabase Storage (avatars, product-images, store-assets buckets) |
| Realtime | Supabase Realtime (for live updates) |
| Edge Functions | Available for server-side logic |

---

## 4. Database Schema

### 4.1 Profiles Table
```sql
CREATE TABLE public.profiles (
    id           UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
    full_name    TEXT NOT NULL,
    email        TEXT NOT NULL UNIQUE,
    phone        TEXT,
    role         TEXT NOT NULL DEFAULT 'customer'
                 CHECK (role IN ('customer', 'seller', 'admin')),
    seller_status TEXT NOT NULL DEFAULT 'pending'
                 CHECK (seller_status IN ('pending', 'approved', 'rejected')),
    avatar_url   TEXT,
    created_at   TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL
);
```

### 4.2 Products Table
```sql
CREATE TABLE public.products (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id      UUID REFERENCES public.stores(id) NOT NULL,
    seller_id     UUID REFERENCES public.profiles(id) NOT NULL,
    name          TEXT NOT NULL,
    description   TEXT,
    price         NUMERIC NOT NULL,
    category      TEXT NOT NULL DEFAULT 'General',
    collection    TEXT,
    sku           TEXT,
    is_featured   BOOLEAN NOT NULL DEFAULT false,
    is_published  BOOLEAN NOT NULL DEFAULT true,
    is_active     BOOLEAN DEFAULT true,   -- false when all stock = 0
    tags          TEXT[] DEFAULT '{}',
    created_at    TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at    TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);
```

### 4.3 Orders Table
```sql
CREATE TABLE public.orders (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id         UUID REFERENCES public.stores(id) NOT NULL,
    customer_id      UUID REFERENCES public.profiles(id),
    status           TEXT NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'placed', 'preparing', 'ready', 'received', 'cancelled')),
    fulfillment      TEXT CHECK (fulfillment IN ('pickup', 'delivery')),
    total_amount     NUMERIC NOT NULL,
    payment_method   TEXT,
    payment_status   TEXT DEFAULT 'unpaid'
                     CHECK (payment_status IN ('unpaid', 'paid')),
    notes            TEXT,
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL,
    updated_at       TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);
```

### 4.3a Order Items Table
```sql
CREATE TABLE public.order_items (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id    UUID REFERENCES public.orders(id) ON DELETE CASCADE,
    product_id  UUID REFERENCES public.products(id) ON DELETE SET NULL,
    size        TEXT,
    quantity    INTEGER NOT NULL,
    unit_price  NUMERIC NOT NULL,
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);
```

### 4.4 Customizations Table
```sql
CREATE TABLE public.customizations (
    id             BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    customer_id    UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    base_name      TEXT NOT NULL,
    color          TEXT NOT NULL,
    material       TEXT NOT NULL,
    special_request TEXT,
    status         TEXT NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'approved', 'in_progress', 'completed', 'rejected')),
    created_at     TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL
);
```

### 4.5 Stores Table
```sql
CREATE TABLE public.stores (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name         TEXT NOT NULL,
    tagline      TEXT,
    location     TEXT NOT NULL,
    brand_color  TEXT DEFAULT '#8B5A2B',
    banner_url   TEXT,
    logo_url     TEXT,
    rating       NUMERIC(2,1) DEFAULT 5.0,
    is_open      BOOLEAN DEFAULT true,
    is_active    BOOLEAN DEFAULT true,
    owner_id     UUID REFERENCES public.profiles(id),
    created_at   TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL
);
```

### 4.6 Inventory Table
Tracks stock per product per size. A product's `is_active` flag is automatically managed based on this table.
```sql
CREATE TABLE public.inventory (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id  UUID REFERENCES public.products(id) ON DELETE CASCADE NOT NULL,
    size        TEXT NOT NULL,
    stock       INTEGER NOT NULL DEFAULT 0,
    updated_at  TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);
```

### 4.7 Product Variants Table
Tracks stock per product per size+color combination with optional pricing and SKU overrides.
```sql
CREATE TABLE public.product_variants (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id       UUID REFERENCES public.products(id) ON DELETE CASCADE NOT NULL,
    size             TEXT NOT NULL,
    color            TEXT,
    stock            INTEGER DEFAULT 0,
    additional_price NUMERIC DEFAULT 0,
    sku              TEXT,
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT now()
);
```

### 4.8 Sales Transactions Table
POS (in-person) transactions recorded via the seller's Point of Sale screen.
```sql
CREATE TABLE public.sales_transactions (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    store_id         UUID REFERENCES public.stores(id) NOT NULL,
    seller_id        UUID REFERENCES public.profiles(id) NOT NULL,
    total_amount     NUMERIC NOT NULL,
    payment_method   TEXT,
    amount_tendered  NUMERIC,
    change_amount    NUMERIC,
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);
```

### 4.9 Sales Transaction Items Table
Line items for each POS transaction.
```sql
CREATE TABLE public.sales_transaction_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id  UUID REFERENCES public.sales_transactions(id) ON DELETE CASCADE,
    product_id      UUID REFERENCES public.products(id) ON DELETE SET NULL,
    size            TEXT,
    quantity        INTEGER NOT NULL,
    unit_price      NUMERIC NOT NULL
);
```

### 4.10 Product Images Table
```sql
CREATE TABLE public.product_images (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id    UUID REFERENCES public.products(id) ON DELETE CASCADE,
    image_url     TEXT NOT NULL,
    display_order INTEGER DEFAULT 0,
    created_at    TIMESTAMP WITH TIME ZONE DEFAULT now()
);
```

### 4.11 Product Customizations Table
```sql
CREATE TABLE public.product_customizations (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id  UUID REFERENCES public.products(id) ON DELETE CASCADE,
    -- additional customization option fields
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT now()
);
```

### 4.12 Customization Requests Table
Customer requests for bespoke footwear.
```sql
CREATE TABLE public.customization_requests (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id      UUID REFERENCES public.profiles(id),
    store_id         UUID REFERENCES public.stores(id),
    base_product_id  UUID REFERENCES public.products(id) ON DELETE SET NULL,
    -- request detail fields (color, material, special_request, status, etc.)
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT now()
);
```

### 4.13 Notifications Table
```sql
CREATE TABLE public.notifications (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- recipient, type, message, read status fields
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT now()
);
```

### 4.14 Story Entries Table
```sql
CREATE TABLE public.story_entries (
    id             BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    store_id       UUID REFERENCES public.stores(id) ON DELETE CASCADE,
    body_text      TEXT NOT NULL,
    image_url      TEXT,
    display_order  INTEGER NOT NULL DEFAULT 0,
    created_at     TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL
);
```

> **Note:** The `title` column was removed from `story_entries` in the live database. Do not reference it in queries.

### 4.15 Store Follows Table
```sql
CREATE TABLE public.store_follows (
    user_id    UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    store_id   UUID REFERENCES public.stores(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL,
    PRIMARY KEY (user_id, store_id)
);
```

### 4.16 Seed Data
Three initial stores are seeded:
1. **Valladolid Leather Co.** — "Handcrafted footwear since 1992" (Valladolid, Carcar City)
2. **Carcar Sole Works** — "Where tradition meets comfort" (Poblacion, Carcar City)
3. **Cebu Heritage Shoes** — "Crafted with Cebuano pride" (Carcar City, Cebu) — initially closed

---

## 5. User Roles & Permissions

### Role Hierarchy
| Role | Description | Access Level |
|------|-------------|-------------|
| **Customer** | End users who browse and purchase shoes | Full shopping + order tracking |
| **Seller** | Artisans who manage their own store(s) | Store management + POS + order fulfillment |
| **Admin** | Platform administrators | Full platform oversight + analytics |

### RLS Policy Summary

| Table | Customer | Seller | Admin |
|-------|----------|--------|-------|
| profiles | Read all, Update own | Read all, Update own | Read all, Update any |
| products | Read all | Read all, CRUD own store | Read all, CRUD any |
| orders | Read/Insert own | Read all, Update status | Read all, Update status |
| customizations | Read/Insert own | Read all, Update status | Read all, Update any |
| stores | Read all | CRUD own store | CRUD any |
| store_follows | Read/Insert/Delete own | — | — |
| story_entries | Read all | — | CRUD any |

> **Note (v1.1.0):** The `products` table DELETE policy was missing on initial release and has been added. See [Section 17](#17-changelog--bug-fixes) for details.

### Seller Approval Flow
1. User registers with "Apply as a seller" toggle enabled
2. Profile created with `seller_status = 'pending'`
3. User sees "Pending Approval" screen in the app
4. Admin reviews in admin portal → Approve or Reject
5. On approval: `role` → `seller`, `seller_status` → `approved`
6. User can now access the seller dashboard

---

## 6. Mobile App — Flutter

### 6.1 App Entry & Navigation

**Entry Point:** `lib/main.dart`
- Initializes Supabase with project URL and anon key
- Sets up `MultiProvider` with `AuthProvider`, `ProductProvider`, `CartProvider`, `OrderProvider`
- Applies global Material 3 theme with custom color palette
- Handles global errors gracefully

**Navigation Flow:**
```
SplashScreen (2s animated)
    └→ AuthGate (StreamBuilder on auth state)
        ├→ OnboardingScreen (first-time users)
        ├→ LoginScreen / RegisterScreen
        ├→ CustomerShell (customer role)
        ├→ SellerShell (seller role, approved)
        ├→ AdminShell (admin role)
        └→ PendingApprovalScreen (seller_status = 'pending')
```

### 6.2 Screen Architecture

#### Customer Shell (`lib/screens/customer/customer_shell.dart`)
| Tab | Screen | Description |
|-----|--------|-------------|
| Home | `CustomerHomeScreen` | Featured products, store discovery |
| Store | `StoreScreen` | Browse stores, follow/unfollow |
| Orders | `OrdersScreen` | View order history & tracking |
| Profile | `ProfileScreen` | Account settings, avatar, logout |

#### Seller Shell (`lib/screens/seller/seller_shell.dart`)
| Tab | Screen | Description |
|-----|--------|-------------|
| Dashboard | `SellerDashboardScreen` | Today's sales, weekly trends, store metrics |
| POS | `POSScreen` | Point-of-sale for in-person transactions |
| Products | `ManageProductsScreen` | Add/edit/delete products with images |
| Orders | `ManageOrdersScreen` | View and update order statuses |
| Profile | `ProfileScreen` | Account settings |

#### Admin Shell (`lib/screens/admin/admin_shell.dart`)
| Tab | Screen | Description |
|-----|--------|-------------|
| Dashboard | `AdminDashboardScreen` | Platform-wide stats |
| Users | `ManageUsersScreen` | User management & role changes |
| Requests | `SellerApprovalScreen` | Approve/reject seller applications |
| Monitor | `MonitorProductsScreen` | Product catalog oversight |
| Profile | `ProfileScreen` | Account settings |

### 6.3 Screen Details

#### Auth Screens
- **SplashScreen**: Animated logo with shoe sole SVG, auto-navigates to AuthGate after 2 seconds
- **OnboardingScreen**: First-time user introduction (tracked via SharedPreferences)
- **LoginScreen**: Email/password form with biometric login option, hero gradient header
- **RegisterScreen**: Full registration with "Apply as seller" toggle and info chip
- **AuthGate**: StreamBuilder that listens to Supabase auth state, routes by role

#### Customer Screens
- **CustomerHomeScreen**: Product browsing with category filtering, search, and featured products
- **StoreScreen**: Multi-store discovery, follow/unfollow stores, store profiles
- **ProductDetailScreen**: Full product view with size selection, add to cart, customization request
- **CartScreen**: Cart management with quantity controls, delivery fee calculation
- **CheckoutScreen**: Order placement with payment method selection (cash/GCash/card)
- **OrdersScreen**: Order history with status tracking timeline
- **TrackingScreen**: Real-time order status visualization
- **ARFittingScreen**: Augmented reality shoe fitting placeholder
- **CustomizationScreen**: Custom shoe order request form (color, material, special requests)

#### Seller Screens
- **SellerDashboardScreen**: Today's sales, weekly bar chart, store health metrics
- **POSScreen**: Quick product selection, size/quantity, payment processing, receipt generation
- **ManageProductsScreen**: Product list with add/edit/delete, image upload, variant management
- **ManageOrdersScreen**: Order list with status update actions
- **CreateStoreScreen**: Store creation with name, tagline, location, brand color, logo/banner upload
- **EditStoreScreen**: Store profile editing
- **StoreProfileScreen**: Public store view for customers
- **ManageInventoryScreen**: Stock level management per product/size
- **ReportsScreen**: Sales reports and analytics for the store
- **SellerMoreScreen**: Additional seller features

#### Admin Screens
- **AdminDashboardScreen**: Platform stats (users, products, orders, pending applications)
- **ManageUsersScreen**: User list with role management
- **SellerApprovalScreen**: Pending seller applications with approve/reject actions
- **MonitorProductsScreen**: Product catalog monitoring

#### Shared Screens
- **ProfileScreen**: Unified profile management (edit name, phone, avatar, logout, role switching for testing)

---

## 7. Admin Portal — React

### 7.1 Pages & Routes

| Route | Page | Description |
|-------|------|-------------|
| `/login` | Login | Admin-only authentication |
| `/` | Dashboard | Stats cards, recent applications, recent orders |
| `/users` | Users | User management table with role/suspension actions |
| `/seller-applications` | Seller Applications | Approve/reject pending seller applications |
| `/products` | Products | Product catalog management |
| `/orders` | Orders | Order management with status updates |
| `/analytics` | Analytics | Revenue charts, order trends, top products, seller trends |
| `/settings` | Settings | Admin profile & password management |

### 7.2 Component Architecture

```
src/
├── App.jsx                    # Root with Routes
├── components/
│   ├── layout/
│   │   ├── AppLayout.jsx      # Sidebar + TopBar + Outlet
│   │   ├── ProtectedRoute.jsx # Auth guard (redirects to /login)
│   │   ├── Sidebar.jsx        # Navigation sidebar with logo
│   │   └── TopBar.jsx         # Top bar with mobile toggle + profile
│   ├── products/
│   │   ├── AddProductModal.jsx
│   │   ├── ProductCard.jsx
│   │   ├── ProductDetailModal.jsx
│   │   ├── ProductListRow.jsx
│   │   └── StoreGroup.jsx
│   ├── ui/
│   │   ├── AvatarInitials.jsx
│   │   ├── Badge.jsx
│   │   ├── DataTable.jsx
│   │   ├── EmptyState.jsx
│   │   ├── Modal.jsx
│   │   ├── Skeleton.jsx
│   │   ├── StatCard.jsx
│   │   └── Toast.jsx
│   └── users/
│       ├── UserDetailModal.jsx
│       ├── UserRow.jsx
│       └── UserSection.jsx
├── hooks/
│   ├── useAnalytics.js        # Analytics data with Recharts formatting
│   ├── useAuth.jsx            # Auth state + login/logout/profile
│   ├── useDashboard.js        # Dashboard stats, recent data, seller actions
│   ├── useOrders.js           # Orders CRUD with React Query
│   ├── useProducts.js         # Products CRUD with React Query
│   ├── useSellerApplications.js # Seller application management
│   └── useUsers.js            # User management with React Query
├── lib/
│   ├── constants.js           # Roles, statuses, formatting utilities
│   └── supabase.js            # Supabase client initialization
├── pages/
│   ├── Analytics.jsx
│   ├── Dashboard.jsx
│   ├── Login.jsx
│   ├── Orders.jsx
│   ├── Products.jsx
│   ├── SellerApplications.jsx
│   ├── Settings.jsx
│   └── Users.jsx
```

### 7.3 Key Features

#### Dashboard
- **StatCards**: Total users, pending applications, total products, total orders
- **Recent Applications**: Latest 5 pending seller applications
- **Recent Orders**: Latest 5 orders with customer info and store name
- **Orders Sparkline**: 7-day order count chart

#### Analytics
- **Orders Over Time**: Daily order count line chart (30-day)
- **Revenue Over Time**: Daily revenue line chart (30-day)
- **Users Over Time**: Daily new user registrations (30-day)
- **Orders by Status**: Pie chart breakdown
- **Top Products**: Bar chart of best-selling products
- **Seller Application Trend**: Monthly pending/approved/rejected stacked bar

#### User Management
- Searchable user table
- Role display with badges (Customer, Seller, Admin)
- Seller status badges (Pending, Approved, Rejected)
- User detail modal with full profile info
- Role change capability

#### Seller Applications
- Dedicated view for pending applications
- Approve button (sets role to 'seller', status to 'approved')
- Reject button with optional rejection reason
- Real-time updates via React Query cache invalidation

---

## 8. Services Layer

### Mobile App Services (`lib/services/`)

| Service | Singleton | Responsibility |
|---------|-----------|---------------|
| `SupabaseService` | `SupabaseService.instance` | Core CRUD: products, orders, customizations, profiles, seller approvals |
| `AuthService` | `AuthService.instance` | Auth: sign in, sign up, profile fetch with retry logic |
| `ProductService` | `ProductService.instance` | Product CRUD with image upload to Supabase Storage |
| `OrderService` | `OrderService._()` | Order placement, status updates, store order filtering |
| `StoreService` | `StoreService.instance` | Store CRUD, image upload, follow/unfollow, story entries |
| `ProfileService` | `ProfileService.instance` | Avatar picking and upload |
| `UploadService` | `UploadService._()` | Generic file upload/delete for Supabase Storage |
| `SalesService` | `SalesService._()` | POS transactions, daily/weekly sales aggregation |
| `BiometricService` | `BiometricService._()` | Biometric auth, credential storage via FlutterSecureStorage |

### Key Service Patterns
- **Singleton pattern**: All services use private constructors with static instances
- **Supabase client access**: Via `Supabase.instance.client` (initialized in `main.dart`)
- **Error handling**: Services throw exceptions; providers catch and set `_errorMessage`
- **Image uploads**: Stored in `product-images` bucket (public), `avatars` bucket, and `store-assets` bucket

---

## 9. Data Models

### Product Models (`lib/models/product_models.dart`)

#### ProductVariant
```dart
class ProductVariant {
  final String? id;
  final String size;         // e.g., "38", "39", "40"
  final String? color;
  final int stock;
  final double additionalPrice;
  final String? sku;
}
```

#### ProductCustomization
```dart
class ProductCustomization {
  final String? id;
  final String optionName;    // e.g., "Monogram"
  final String optionType;    // 'text', 'select', 'color'
  final List<String> options;
  final bool isRequired;
  final double additionalPrice;
}
```

### Store Model (`lib/models/store.dart`)

```dart
class Store {
  final String id;
  final String name;
  final String? tagline;
  final String location;
  final String brandColor;      // Hex string, e.g., '#8B5A2B'
  final String? bannerUrl;
  final String? logoUrl;
  final double rating;
  final bool isOpen;
  final bool isActive;
  final String? ownerId;
  final DateTime createdAt;

  Color get color => AppConstants.parseBrandColor(brandColor);
  String get initials { /* first two words initials */ }
  LinearGradient get cardGradient { /* brand color gradient */ }
}
```

---

## 10. State Management

### Provider Architecture (Mobile)

| Provider | Scope | Key State |
|----------|-------|-----------|
| `AuthProvider` | App-wide | `_currentUser`, `_profile`, `_isLoading`, `_errorMessage` |
| `ProductProvider` | Product browsing | `_products[]`, `_selectedCategory`, `categories` |
| `CartProvider` | Shopping cart | `_items{}`, `subtotal`, `deliveryFee`, `total` |
| `OrderProvider` | Orders & admin | `_orders[]`, `_customizations[]`, `_profiles[]` |

### React Query (Admin Portal)

| Hook | Queries | Mutations |
|------|---------|-----------|
| `useDashboardStats` | Dashboard counts | — |
| `useRecentPendingApplications` | Recent pending sellers | — |
| `useRecentOrders` | Recent orders | — |
| `useOrdersSparkline` | 7-day order counts | — |
| `useApproveSeller` | — | Approve seller |
| `useRejectSeller` | — | Reject seller |
| `useAnalytics(days)` | Revenue, orders, users, trends | — |
| `useUsers` | User list | Update roles |
| `useOrders` | Order list | Update status |
| `useProducts` | Product list | CRUD |

### Cart Logic
- Items keyed by `productId-size-color`
- Flat ₱100 delivery fee for local Cebu area
- Quantity increment/decrement with auto-removal at 0

---

## 11. Authentication & Security

### Authentication Flow
1. **Registration**: Email/password → Supabase Auth → Profile row created via DB trigger or manual upsert
2. **Login**: Email/password → Supabase Auth JWT → Profile fetch with retry (up to 5 attempts)
3. **Session restore**: `AuthGate` checks `currentSession` on app start
4. **Session expiry**: Detected via `StreamBuilder<AuthState>`, shows non-dismissible bottom sheet

### Biometric Authentication
- **Available check**: `LocalAuthentication.canCheckBiometrics` + `isDeviceSupported()`
- **Credential storage**: Encrypted via `FlutterSecureStorage` (email + password)
- **Flow**: User enables after first successful login → credentials saved → future logins use fingerprint/face
- **Decline tracking**: Once declined, not asked again (stored in secure storage)

### Security Measures
- **RLS on all tables**: Every database table has Row Level Security enabled
- **JWT-based auth**: Supabase manages token refresh automatically
- **Secure storage**: Biometric credentials stored in `FlutterSecureStorage` (not SharedPreferences)
- **Admin-only policies**: Admin actions gated by `role = 'admin'` check in RLS
- **Profile creation retry**: AuthService retries profile fetch 5 times with exponential backoff before manual creation

### Storage Buckets
| Bucket | Access | Contents |
|--------|--------|----------|
| `avatars` | Public | User profile pictures |
| `product-images` | Public | Product photos |
| `store-assets` | Public | Store logos and banners |

---

## 12. UI Design System

### Color Palette
| Name | Hex | Usage |
|------|-----|-------|
| **Primary** (Burnished Clay) | `#8B5A2B` | Buttons, active states, brand accent |
| **Secondary** (Carob Dark) | `#3B2314` | Text, icons, sidebar background |
| **Accent** (Celadon Teal) | `#4ECDC4` | AR mode, CTAs, highlights |
| **Surface Light** (Off-White Suede) | `#F5F0EB` | Backgrounds |
| **Surface Dark** (Midnight Canvas) | `#1A1208` | Dark mode / AR overlay |
| **Success** (Olive Stitch) | `#6B8F47` | Success states |
| **Error** (Crimson Welt) | `#D64545` | Error states |
| **Border Gray** | `#D2C7BC` | Borders, dividers |

### Typography
| Style | Font | Usage |
|-------|------|-------|
| Headlines | Playfair Display | Titles, headings, wordmarks |
| Body & Labels | DM Sans | Body text, labels, buttons |
| Monospace | JetBrains Mono | Codes, IDs, timestamps |

### Visual Language
- **Card radius**: 16px rounded corners
- **Button radius**: 12px rounded corners
- **Warm shadow**: Primary-colored with 8% opacity, 12px blur
- **Dark shadow**: Black with 20% opacity, 8px blur
- **Noise overlay**: Organic texture via custom `_NoisePainter` (pseudo-random speckles)

### Reusable Widgets (`lib/widgets/`)
| Widget | Description |
|--------|-------------|
| `SoleCard` | Rounded card with warm shadow |
| `SolePrimaryButton` | Primary action button with loading state |
| `SoleTextField` | Styled text field with label and prefix icon |
| `SoleBottomNav` | Role-aware bottom navigation bar |
| `SoleBadge` | Status badge with color variants |
| `SoleStatusChip` | Order/product status chip |
| `SoleMetricCard` | Dashboard metric display card |
| `SoleProductCard` | Product display card for grids |
| `SoleTimeline` | Order status tracking timeline |
| `ShimmerBox` | Loading skeleton placeholder |
| `EmptyStateWidget` | Empty list state with icon and message |
| `ErrorRetryWidget` | Error state with retry button |
| `CartIconButton` | Cart icon with item count badge |
| `ArViewPlaceholder` | AR fitting mode placeholder |

### Seller-Specific Widgets (`lib/widgets/seller/`)
| Widget | Description |
|--------|-------------|
| `SellerMetricCard` | Dashboard metric with icon and trend |
| `SellerProductRow` | Product list item for management |
| `SellerOrderCard` | Order card with status actions |
| `SellerInventoryRow` | Inventory level row with stock indicator |
| `SellerStatusChip` | Order status display chip |
| `SellerPaymentMethodPill` | Payment method badge (Cash/GCash/Card) |
| `SellerAlertChip` | Warning/alert notification chip |
| `SellerWeeklyBar` | 7-day sales bar chart |
| `SellerSparkline` | Mini line chart for trends |

---

## 13. Feature Breakdown

### 13.1 Customer Features
| Feature | Description | Status |
|---------|-------------|--------|
| User Registration | Email/password with optional seller application | ✅ |
| Biometric Login | Fingerprint/face authentication | ✅ |
| Onboarding | First-time user introduction screen | ✅ |
| Product Browsing | Browse products with category filtering and search | ✅ |
| Store Discovery | Discover and follow artisan stores | ✅ |
| Product Details | View product with images, sizes, descriptions | ✅ |
| Shopping Cart | Add/remove items, quantity controls | ✅ |
| Checkout | Order placement with payment method selection | ✅ |
| Order Tracking | Real-time order status timeline | ✅ |
| Custom Orders | Request bespoke footwear (color, material, special requests) | ✅ |
| Profile Management | Edit name, phone, avatar | ✅ |
| Password Reset | Email-based password reset | ✅ |

### 13.2 Seller Features
| Feature | Description | Status |
|---------|-------------|--------|
| Store Creation | Create store with branding (name, tagline, color, logo, banner) | ✅ |
| Store Management | Edit store profile, toggle open/closed | ✅ |
| Product Management | Add/edit/delete products with images, variants, customizations | ✅ |
| Inventory Management | Track stock levels per size | ✅ |
| Order Management | View orders, update statuses | ✅ |
| POS (Point of Sale) | In-person transaction processing | ✅ |
| Sales Tracking | Today's sales, weekly trends | ✅ |
| Reports | Sales analytics for the store | ✅ |
| Store Stories | Workshop stories displayed on store profile | ✅ |

### 13.3 Admin Features
| Feature | Description | Status |
|---------|-------------|--------|
| Dashboard | Platform-wide stats and recent activity | ✅ |
| User Management | View users, change roles | ✅ |
| Seller Applications | Approve/reject with optional reason | ✅ |
| Product Monitoring | View and manage all products | ✅ |
| Order Monitoring | View all orders across stores | ✅ |
| Analytics | Revenue, orders, users, top products, seller trends | ✅ |
| Settings | Admin profile and password management | ✅ |

### 13.4 Admin Portal (Web) Features
| Feature | Description | Status |
|---------|-------------|--------|
| Responsive Sidebar | Collapsible navigation with mobile support | ✅ |
| Protected Routes | Auth guard redirects to login | ✅ |
| Dashboard Stats | Real-time counts via React Query | ✅ |
| Interactive Charts | Recharts-based analytics (line, bar, pie) | ✅ |
| Data Tables | Searchable, sortable user/product/order tables | ✅ |
| Modals | Detail views for users, products, orders | ✅ |
| Toast Notifications | Action feedback | ✅ |
| Skeleton Loading | Placeholder loading states | ✅ |

---

## 14. Setup & Installation

### Prerequisites
- Flutter SDK 3.x
- Node.js 18+
- Supabase account and project
- Google Chrome (for admin portal development)

### Mobile App Setup

```bash
# Clone the repository
git clone <repository-url>
cd app

# Install Flutter dependencies
flutter pub get

# Configure Supabase credentials
# Edit lib/constants/app_constants.dart with your Supabase URL and anon key

# Run the app
flutter run
```

### Admin Portal Setup

```bash
cd admin-portal

# Install dependencies
npm install

# Create environment file
cp .env.example .env

# Edit .env with Supabase credentials
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your_anon_key_here

# Start development server
npm run dev

# Open http://localhost:5173
```

### Database Setup

1. Create a Supabase project
2. Run `supabase/schema.sql` in the SQL Editor
3. Ensure the following Storage buckets exist (public):
   - `avatars`
   - `product-images`
   - `store-assets`
4. Enable Realtime on the `profiles` table for live admin updates

### Required Environment Variables

| Variable | Location | Description |
|----------|----------|-------------|
| `AppConstants.url` | `lib/constants/app_constants.dart` | Supabase project URL |
| `AppConstants.anonKey` | `lib/constants/app_constants.dart` | Supabase anon/public key |
| `VITE_SUPABASE_URL` | `admin-portal/.env` | Same Supabase URL |
| `VITE_SUPABASE_ANON_KEY` | `admin-portal/.env` | Same anon key |

---

## 15. Deployment Notes

### Mobile App
- **Android**: Configure `android/app/build.gradle` with signing config
- **iOS**: Configure `ios/Runner.xcodeproj` with development team and provisioning profile
- **Build**: `flutter build apk --release` (Android) or `flutter build ios --release` (iOS)

### Admin Portal
- **Build**: `npm run build` produces `dist/` directory
- **Deploy**: Host `dist/` on Vercel, Netlify, or any static hosting
- **Custom Domain**: Configure DNS and SSL certificate

### Supabase
- **Production**: Upgrade Supabase plan for production traffic
- **Backups**: Enable automatic backups
- **RLS**: Never disable RLS in production
- **Storage**: Ensure bucket policies are correctly configured

---

## 16. Future Enhancements

### High Priority
- [ ] Real-time order updates via Supabase Realtime subscriptions
- [ ] Push notifications for order status changes
- [ ] Payment gateway integration (GCash API, card processing)
- [ ] Product image gallery with zoom and carousel
- [ ] Search with fuzzy matching and filters

### Medium Priority
- [ ] AR shoe fitting with real 3D models (currently placeholder)
- [ ] Seller analytics dashboard with more detailed reports
- [ ] Customer reviews and ratings system
- [ ] Wishlist / favorites feature
- [ ] Store following feed with product updates

### Low Priority
- [ ] Multi-language support (Filipino, Cebuano)
- [ ] Offline mode with local caching
- [ ] Seller-to-customer chat
- [ ] Admin role delegation
- [ ] Export reports as PDF/CSV

---

## 17. Changelog & Bug Fixes

This section documents all bugs identified, investigated, and resolved during the development session of **June 28, 2026**, along with the database schema corrections discovered by verifying the live Supabase database against the original documentation.

---

### 17.1 Database Schema Corrections (v1.1.0)

During a full schema audit on June 28, 2026, the live Supabase database was compared against the original v1.0.0 documentation. The following discrepancies were found and corrected in this document:

| Area | Original (Docs) | Actual (Live DB) |
|------|----------------|-----------------|
| `products.id` | `BIGINT` identity | `UUID` |
| `orders.id` | `BIGINT` identity | `UUID` |
| `orders` structure | Single table with inline product/size/color | Separate `orders` + `order_items` tables |
| `orders.store_id` | Not documented (join via products) | Direct column on `orders` |
| `orders.status` | `placed\|preparing\|ready\|received` | Added `pending` and `cancelled` |
| `orders.payment_status` | Not documented | `unpaid\|paid` column exists |
| `story_entries.title` | `TEXT NOT NULL` column | Column does not exist in live DB |
| Missing tables | Not documented | `inventory`, `product_variants`, `product_images`, `product_customizations`, `sales_transactions`, `sales_transaction_items`, `customization_requests`, `notifications`, `order_items` |

**Action taken:** Section 4 (Database Schema) has been fully updated to reflect the live database schema.

---

### 17.2 Bug Fix — Login Freeze When Switching Accounts

**Date:** June 28, 2026  
**Severity:** High  
**Affected Screen:** `lib/screens/auth/login_screen.dart`, `lib/providers/auth_provider.dart`, `lib/screens/auth/auth_gate.dart`

#### Symptom
When a user logged out and attempted to log in with a **different account**, the app froze on the login screen with no error, no navigation, and no response to input. The only recovery was to fully close and reopen the app.

#### Root Causes Identified
1. **Stale `AuthProvider` state** — `_currentUser` and `_profile` were not fully cleared on logout before the next `signIn()` was called, leaving the provider in an inconsistent state
2. **Supabase auth stream not re-emitting** — `AuthGate`'s `StreamBuilder` on `onAuthStateChange` did not correctly handle the `signedOut → signedIn` transition for a different account
3. **Profile fetch retry loop not resetting** — The 5-attempt retry counter and backoff state were not reset between sessions, causing silent profile fetch failures that left `_isLoading = true` indefinitely
4. **Biometric credential conflict** — Credentials stored in `FlutterSecureStorage` for Account A interfered with a manual login as Account B
5. **`_isLoading` flag stuck** — If a previous session left `_isLoading = true` (due to a failed retry or partial logout), the login button remained permanently disabled with no visible indicator

#### Fixes Applied
| File | Fix |
|------|-----|
| `auth_provider.dart` | Clear `_currentUser`, `_profile`, `_errorMessage`, `_isLoading` on `signOut()`; reset all state at the start of each new `signIn()` call; wrap entire flow in `try/catch/finally` to guarantee `_isLoading` resets |
| `auth_service.dart` | Reset retry counter before each new `signIn()`; call `Supabase.signOut()` before `signIn()` if a session already exists |
| `auth_gate.dart` | Handle `AuthChangeEvent.signedOut` + `AuthChangeEvent.signedIn` transition explicitly; force route rebuild on `signedIn` event |
| `login_screen.dart` | Ensure submit button disabled state is tied only to `_isLoading`; surface `AuthProvider._errorMessage` visibly in the UI |
| `biometric_service.dart` | Clear stored biometric credentials from `FlutterSecureStorage` on logout so they do not interfere with the next user's session |

---

### 17.3 Feature — Seller Dashboard Real Data Integration

**Date:** June 28, 2026  
**Type:** Feature / Data Integration  
**Affected Screen:** `lib/screens/seller/seller_dashboard_screen.dart`

#### Summary
The seller dashboard was displaying hardcoded mock data for all metrics. It has been wired to real Supabase data.

#### Data Sources
| Metric | Source |
|--------|--------|
| Today's revenue | `orders` (online, `payment_status = 'paid'`, `status != 'cancelled'`) + `sales_transactions` (POS) |
| Weekly revenue | Same two sources, filtered to current Mon–Sun date range |
| Total orders | COUNT from `orders` where `store_id = storeId` and `status != 'cancelled'` |
| Pending orders | COUNT from `orders` where `status IN ('placed', 'preparing')` |
| Weekly bar chart | 7-day daily revenue aggregation from both sources, grouped by `weekday` in Dart |
| Recent orders | `orders` joined with `profiles` (customer name) and `order_items → products` (product name), last 5 |
| Store rating | `stores.rating` via `StoreService.getStoreByOwnerId()` |

#### Key Implementation Notes
- Revenue must always combine **both** `orders` and `sales_transactions` — neither alone is complete
- `store_id` is a **direct column on `orders`** (not via a product join as originally documented)
- `store_id` is not on `profiles` — fetch store via `stores.owner_id = currentUserId`
- All queries run in parallel via `Future.wait` for performance
- `ShimmerBox` placeholders shown while loading; `ErrorRetryWidget` on failure; pull-to-refresh supported

---

### 17.4 Feature — Reports Screen Real Data Integration

**Date:** June 28, 2026  
**Type:** Feature / Data Integration  
**Affected Screen:** `lib/screens/seller/reports_screen.dart`

#### Summary
The Reports screen (Sales Overview, Top Products, Export) was displaying hardcoded mock data. It has been wired to real Supabase data.

#### Sections Updated

**Sales Overview (Weekly Total + Bar Chart)**
- Total = sum of `orders.total_amount` (paid, non-cancelled) + `sales_transactions.total_amount` for current Mon–Sun
- 7-bar chart: one bar per day of the week, combining both sources, grouped by `DateTime.weekday` index
- Today's bar highlighted in Celadon Teal (`#4ECDC4`); other bars in Burnished Clay (`#8B5A2B`)

**Top Products**
- Aggregates `order_items` (from online orders) + `sales_transaction_items` (from POS) by `product_id`
- Sorted by total units sold descending; top 5 shown
- Product names fetched in a single batch query using `.inFilter('id', productIds)`
- Displays: rank, product name, units sold, total revenue

**Export**
- "Download Sales Report (CSV)" button implemented as a stub `SnackBar` pending full CSV/file export implementation in a future release

#### Data Model
A `SellerReportData` class was introduced to hold all report values cleanly:
```dart
class SellerReportData {
  final double weeklyTotal;
  final List<double> dailyRevenue;        // length 7, Mon=0 Sun=6
  final List<Map<String, dynamic>> topProducts; // [{name, units, revenue}]
  final DateTime weekStart;
  final DateTime weekEnd;
}
```

---

### 17.5 Feature — Product Hard Delete & Auto-Deactivation

**Date:** June 28, 2026  
**Type:** Feature  
**Affected Files:** `lib/screens/seller/products_screen.dart`, `lib/services/product_service.dart`, `lib/widgets/seller/seller_product_card.dart`

#### Hard Delete

Sellers can now permanently delete their own products. The delete flow:

1. Seller taps delete (swipe or three-dot menu) on a product card
2. A confirmation `AlertDialog` appears warning that the action is permanent and order history is preserved
3. On confirmation, `ProductService.deleteProduct()` executes in this order:
   - Nullify `product_id` in `order_items`, `sales_transaction_items`, `customization_requests` (preserves history)
   - Delete rows from `inventory`, `product_variants`, `product_images`, `product_customizations` (CASCADE, explicit for clarity)
   - Delete the product row from `products`
4. Product is removed from the local list immediately via `setState`
5. Success or error `SnackBar` is shown

#### Auto-Deactivation / Auto-Activation

`products.is_active` is now automatically managed based on stock levels:

| Condition | Result |
|-----------|--------|
| All rows in `inventory` AND `product_variants` for a product have `stock = 0` | `is_active` set to `false` |
| Any row in `inventory` OR `product_variants` has `stock > 0` | `is_active` set to `true` |
| Product has no rows in either table | Treated as inactive (`is_active = false`) |

`ProductService.syncProductActiveStatus(productId)` is called after every stock-changing operation: inventory edits, variant edits, POS sales, and order fulfillment.

Product cards display an `Active` (teal) or `Out of Stock` (red) badge, and inactive cards are rendered at 50% opacity.

---

### 17.6 Bug Fix — Product Delete Silently Failing (RLS + FK + Missing `await`)

**Date:** June 28, 2026  
**Severity:** High  
**Affected File:** `lib/services/product_service.dart`

#### Symptom
After implementing the hard delete feature, product deletion appeared to succeed (no error, success SnackBar) but the product reappeared on refresh — meaning the delete never actually completed in the database.

#### Investigation
Three root causes were identified through database inspection:

**Cause 1 — Missing DELETE RLS policy (primary cause)**

The `products` table RLS policies at the time of discovery:

| Policy | Command |
|--------|---------|
| Seller inserts own products | INSERT |
| Anyone can view published products | SELECT |
| Seller views own products including drafts | SELECT |
| Admin views all products | SELECT |
| Seller updates own products | UPDATE |
| Admin updates any product | UPDATE |

There was **no DELETE policy**. In Supabase, when RLS is enabled and no policy covers an operation, that operation is silently rejected — no Dart exception is thrown, the query returns normally but does nothing.

**Cause 2 — FK constraints set to `NO ACTION` (secondary cause, now resolved)**

At the time of initial investigation, three FK constraints were blocking the delete:
- `order_items.product_id → products.id` (NO ACTION)
- `sales_transaction_items.product_id → products.id` (NO ACTION)
- `customization_requests.base_product_id → products.id` (NO ACTION)

These were subsequently updated to `ON DELETE SET NULL` directly in the database, resolving the FK issue.

**Cause 3 — Missing `await` on `_removeStorageFile`**

```dart
// ❌ Before fix
_removeStorageFile(url);  // fire-and-forget, errors silently lost

// ✅ After fix
await _removeStorageFile(url);
```

#### Fixes Applied

**Database (Supabase SQL Editor):**
```sql
-- Allow sellers to delete their own products
CREATE POLICY "Seller deletes own products"
ON products FOR DELETE TO public
USING (auth.uid() = seller_id);

-- Allow admins to delete any product
CREATE POLICY "Admin deletes any product"
ON products FOR DELETE TO public
USING (current_user_role() = 'admin'::text);

-- Fix FK constraints (if not already SET NULL)
ALTER TABLE order_items
  DROP CONSTRAINT IF EXISTS order_items_product_id_fkey,
  ADD CONSTRAINT order_items_product_id_fkey
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL;

ALTER TABLE sales_transaction_items
  DROP CONSTRAINT IF EXISTS sales_transaction_items_product_id_fkey,
  ADD CONSTRAINT sales_transaction_items_product_id_fkey
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL;

ALTER TABLE customization_requests
  DROP CONSTRAINT IF EXISTS customization_requests_base_product_id_fkey,
  ADD CONSTRAINT customization_requests_base_product_id_fkey
    FOREIGN KEY (base_product_id) REFERENCES products(id) ON DELETE SET NULL;
```

**Flutter (`product_service.dart`):**
- Added `await` to `_removeStorageFile(url)` call
- Wrapped entire delete flow in `try/catch` with rethrow so UI displays real error SnackBars

#### Current FK Constraint State (Confirmed)
| Table | Column | Delete Rule |
|-------|--------|-------------|
| `customization_requests` | `base_product_id` | SET NULL ✅ |
| `order_items` | `product_id` | SET NULL ✅ |
| `sales_transaction_items` | `product_id` | SET NULL ✅ |
| `inventory` | `product_id` | CASCADE ✅ |
| `product_customizations` | `product_id` | CASCADE ✅ |
| `product_images` | `product_id` | CASCADE ✅ |
| `product_variants` | `product_id` | CASCADE ✅ |

#### Current RLS DELETE Policies on `products` (Confirmed)
| Policy | Condition |
|--------|-----------|
| Seller deletes own products | `auth.uid() = seller_id` |
| Admin deletes any product | `current_user_role() = 'admin'` |

---

*Section 17 added June 28, 2026. Document version updated to 1.1.0.*

```
app/
├── admin-portal/              # React admin dashboard
│   ├── src/
│   │   ├── components/        # Reusable UI components
│   │   ├── hooks/             # React Query hooks
│   │   ├── lib/               # Utilities and Supabase client
│   │   ├── pages/             # Route pages
│   │   └── App.jsx            # Root component
│   ├── package.json
│   └── vite.config.js
├── lib/                       # Flutter mobile app
│   ├── constants/             # App-wide constants
│   │   └── app_constants.dart
│   ├── models/                # Data models
│   │   ├── product_models.dart
│   │   └── store.dart
│   ├── providers/             # State management
│   │   ├── auth_provider.dart
│   │   ├── cart_provider.dart
│   │   ├── order_provider.dart
│   │   └── product_provider.dart
│   ├── screens/               # All screens organized by role
│   │   ├── admin/
│   │   ├── auth/
│   │   ├── customer/
│   │   ├── seller/
│   │   ├── shared/
│   │   └── store/
│   ├── services/              # Backend service layer
│   │   ├── auth_service.dart
│   │   ├── biometric_service.dart
│   │   ├── order_service.dart
│   │   ├── product_service.dart
│   │   ├── profile_service.dart
│   │   ├── sales_service.dart
│   │   ├── store_service.dart
│   │   ├── supabase_service.dart
│   │   └── upload_service.dart
│   ├── widgets/               # Reusable UI widgets
│   │   ├── seller/            # Seller-specific widgets
│   │   └── *.dart             # Shared widgets
│   └── main.dart              # App entry point
├── supabase/
│   └── schema.sql             # Database schema and RLS policies
├── pubspec.yaml               # Flutter dependencies
└── analysis_options.yaml      # Dart lint rules
```

---

## Appendix B: API Reference (Supabase Tables)

### Query Examples

#### Fetch all active products with store info
```dart
final data = await client
    .from('products')
    .select('*, stores(name), product_images(image_url, display_order), inventory(size, stock)')
    .eq('is_active', true)
    .order('created_at', ascending: false);
```

#### Place an order
```dart
// 1. Insert order
final order = await client.from('orders').insert({
    'customer_id': userId,
    'store_id': storeId,
    'status': 'pending',
    'total_amount': totalAmount,
    'payment_method': 'gcash',
    'payment_status': 'paid',
}).select().single();

// 2. Insert order items
await client.from('order_items').insert({
    'order_id': order['id'],
    'product_id': productId,
    'size': selectedSize,
    'quantity': quantity,
    'unit_price': unitPrice,
});
```

#### Follow a store
```dart
await client.from('store_follows').upsert({
    'user_id': userId,
    'store_id': storeId,
});
```

#### Admin: Approve seller
```dart
await client.from('profiles').update({
    'role': 'seller',
    'seller_status': 'approved',
}).eq('id', userId);
```

---

## Appendix C: Constants Reference

### Order Statuses
| Status | Description |
|--------|-------------|
| `pending` | Order received, awaiting confirmation |
| `placed` | Order confirmed |
| `preparing` | Being prepared/crafted |
| `ready` | Ready for pickup/delivery |
| `received` | Customer has received the order |
| `cancelled` | Order cancelled |

### Seller Statuses
| Status | Description |
|--------|-------------|
| `pending` | Application submitted, awaiting review |
| `approved` | Seller access granted |
| `rejected` | Application denied |
| `none` | Not applied as seller |

### Payment Methods
| Method | Description |
|--------|-------------|
| `cash` | In-person cash payment |
| `gcash` | GCash mobile wallet |
| `card` | Credit/debit card |

---

*Document generated by Codebuff on June 28, 2026. Updated to v1.1.0 on June 28, 2026.*


# SoleVision — Session Log: June 30, 2026

## Overview

This document details all bug fixes, improvements, and code changes made during the
June 30, 2026 development session. Three critical bugs were resolved across the
authentication flow and product catalog, along with several UX improvements.

---

## Table of Contents

1. [Bug #1: Login Freeze When Switching Accounts](#bug-1-login-freeze-when-switching-accounts)
2. [Bug #2: Navigator Stack Conflict on Account Switch](#bug-2-navigator-stack-conflict-on-account-switch)
3. [Bug #3: Product Size Selector Empty — Inventory Never Written](#bug-3-product-size-selector-empty--inventory-never-written)
4. [Improvement #1: Profile Fetch Timeout](#improvement-1-profile-fetch-timeout)
5. [Improvement #2: Offline Detection](#improvement-2-offline-detection)
6. [Improvement #3: Size Selector Loading Skeleton](#improvement-3-size-selector-loading-skeleton)
7. [Reference Copies](#reference-copies)
8. [SQL Migration](#sql-migration)
9. [Files Modified](#files-modified)
10. [Testing Checklist](#testing-checklist)

---

## Bug #1: Login Freeze When Switching Accounts

### Severity: Critical

### Symptom

When a seller or customer logs out and attempts to log in with a different account,
the app freezes on the login screen:

- No error message is shown
- No navigation occurs
- The login button appears disabled or unresponsive
- The only recovery is to fully close and reopen the app

This does **not** happen on a fresh app launch — only when switching from one
account to another within the same session.

### Root Causes (5 total)

| # | Cause | File |
|---|-------|------|
| 1 | Stale `AuthProvider` state — `_currentUser` and `_profile` not cleared before next `signIn()` | `auth_provider.dart` |
| 2 | Supabase Auth stream not re-emitting correctly for `signedOut → signedIn` transition | `auth_gate.dart` |
| 3 | Profile fetch retry counter not resetting between sessions | `auth_service.dart` |
| 4 | Biometric credentials from Account A interfering with Account B's login | `biometric_service.dart` |
| 5 | `_isLoading` flag stuck `true` — login button permanently disabled | `auth_provider.dart` |

### Fixes Applied

#### Fix 1: `lib/providers/auth_provider.dart`

**`signOut()`** — Clears all state before calling Supabase:

```dart
Future<void> signOut() async {
  // Clear all local state FIRST
  _currentUser = null;
  _profile = null;
  _errorMessage = null;
  _isLoading = false;
  notifyListeners();

  // Clear biometric credentials so they don't bleed into the next session
  await BiometricService.instance.clearCredentials();
  await AuthService.instance.signOut();
}
```

**`login()`** — Resets everything at the very top, uses `try/catch/finally`:

```dart
Future<bool> login(String email, String password) async {
  // Reset ALL state at the very start
  _currentUser = null;
  _profile = null;
  _errorMessage = null;
  _isLoading = true;
  notifyListeners();

  try {
    final res = await _auth.signIn(email: email, password: password);
    _currentUser = res['user'];
    _profile = res['profile'];
    return true;
  } catch (e) {
    _errorMessage = e.toString().replaceAll('Exception: ', '');
    return false;
  } finally {
    // ALWAYS reset _isLoading — even if an exception is thrown mid-flow
    _isLoading = false;
    notifyListeners();
  }
}
```

#### Fix 2: `lib/services/auth_service.dart`

**`signIn()`** — Forces sign-out of any existing session before signing in:

```dart
Future<Map<String, dynamic>> signIn({
  required String email,
  required String password,
}) async {
  // Force sign-out any existing session — critical when switching accounts.
  final existing = _client.auth.currentSession;
  if (existing != null) {
    await _client.auth.signOut();
  }

  final response = await _client.auth.signInWithPassword(
    email: email.trim(),
    password: password,
  );
  // ...
}
```

**Why this is the primary fix:** Without clearing the lingering session, Supabase
rejects the new sign-in silently, leaving the app stuck with `_isLoading = true`.

#### Fix 3: `lib/screens/auth_gate.dart`

**`_FirstTimeOrLoginRouter`** — Returns widgets directly instead of using
`Navigator.pushReplacement` (see Bug #2 below for full details).

**`PendingApprovalScreen`** — Uses `context.read<AuthProvider>().logout()` instead
of `AuthService.instance.signOut()` for full state cleanup.

#### Fix 4: `lib/services/biometric_service.dart`

**`clearCredentials()`** — Already existed and was already called inside
`AuthProvider.signOut()`. No additional changes needed.

```dart
Future<void> clearCredentials() async {
  await _secureStorage.delete(key: _keyEmail);
  await _secureStorage.delete(key: _keyPassword);
  await _secureStorage.delete(key: _keyDeclined);
}
```

#### Fix 5: Login button state

Already correctly implemented — button `onPressed` is `null` only when
`auth.isLoading == true`. `auth.errorMessage` is displayed via SnackBar.

### Interaction Map

| If you skip... | What still breaks |
|---|---|
| Fix 1 (AuthProvider reset) | `_isLoading` stays `true`, button stays disabled |
| Fix 2 (AuthService session clear) | Supabase rejects the new sign-in silently |
| Fix 3 (AuthGate routing) | Stream emits but UI doesn't re-route |
| Fix 4 (biometric clear) | Secure storage credentials from Account A corrupt flow |
| Fix 5 (button state) | No feedback, button appears stuck |

**All 5 fixes must be applied together.**

---

## Bug #2: Navigator Stack Conflict on Account Switch

### Severity: Critical

### Symptom

After logging out and logging in with a different account, the app stays on the
login screen even though the auth stream has emitted `signedIn` and the correct
shell has been rendered underneath.

### Root Cause

`_FirstTimeOrLoginRouter` used `Navigator.pushReplacement` to push `LoginScreen`
onto the navigator stack. This placed `LoginScreen` on a **separate stack layer**
on top of `AuthGate`, disconnected from the `StreamBuilder`. When the stream
emitted `signedIn`, `AuthGate` rebuilt with the correct shell underneath, but
`LoginScreen` was never popped — it remained on top, blocking the shell.

```
Step 1: User logs out → Stream emits signedOut → AuthGate rebuilds
Step 2: _FirstTimeOrLoginRouter pushes LoginScreen via Navigator.pushReplacement
Step 3: LoginScreen is now ON TOP of AuthGate — disconnected from StreamBuilder
Step 4: User logs in → Stream emits signedIn → AuthGate rebuilds correctly
Step 5: BUT LoginScreen is still on top → App appears frozen
```

### Fix: `lib/screens/auth_gate.dart`

Replaced `_FirstTimeOrLoginRouter` to return widgets directly from `build()`:

```dart
class _FirstTimeOrLoginRouterState extends State<_FirstTimeOrLoginRouter> {
  bool? _hasSeenOnboarding;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasSeenOnboarding == null) return const _LoadingScreen();

    // Return directly — do NOT use Navigator.pushReplacement
    if (!_hasSeenOnboarding!) return const OnboardingScreen();
    return const LoginScreen();
  }
}
```

**Why this works:** When `LoginScreen` is returned directly from `build()`, it is
part of `AuthGate`'s widget subtree. When the stream emits `signedIn`, `AuthGate`
rebuilds and naturally replaces `LoginScreen` with the correct shell — no manual
`Navigator.pop()` needed.

### Secondary Fix: `PendingApprovalScreen` Logout

Changed from `AuthService.instance.signOut()` (bypasses `AuthProvider`) to
`context.read<AuthProvider>().logout()` for full state cleanup:

```dart
// Before:
Future<void> _logout() => AuthService.instance.signOut();

// After:
onPressed: () => context.read<AuthProvider>().logout(),
```

---

## Bug #3: Product Size Selector Empty — Inventory Never Written

### Severity: Critical

### Symptom

Customer product detail screen shows the "Select Size (EU)" label but no size
chips underneath. "Add to Cart" always shows "Please select an available size."

### Root Causes (2 total)

| # | Cause | File |
|---|-------|------|
| 1 | `product_detail_screen.dart` reads non-existent `widget.product['sizes']` key | `product_detail_screen.dart` |
| 2 | `product_service.dart` `createProduct()` and `updateProduct()` never write to the `inventory` table | `product_service.dart` |

### Fix 1: `lib/services/product_service.dart` — Write Path

**Added `_syncInventoryFromVariants()` helper:**

```dart
/// Sync the inventory table from a variants list.
///
/// Groups variants by size and sums their stock across all colors,
/// then replaces all inventory rows for this product with one row
/// per unique size.
Future<void> _syncInventoryFromVariants(
  String productId,
  List<ProductVariant> variants,
) async {
  // Group stock by size — sum across all colors
  final Map<String, int> stockBySize = {};
  for (final v in variants) {
    final size = v.size.trim();
    if (size.isEmpty) continue;
    stockBySize[size] = (stockBySize[size] ?? 0) + v.stock;
  }

  // Delete existing inventory rows (BEFORE early return to clear stale data)
  await _client
      .from('inventory')
      .delete()
      .eq('product_id', productId);

  if (stockBySize.isEmpty) return;

  // Insert one row per unique size
  await _client.from('inventory').insert(
    stockBySize.entries.map((e) => {
      'product_id': productId,
      'size': e.key,
      'stock': e.value,
      'updated_at': DateTime.now().toIso8601String(),
    }).toList(),
  );
}
```

**Called in `createProduct()` after variants insert:**

```dart
// 4. Insert variants
if (variants.isNotEmpty) {
  await _client.from('product_variants').insert(
        variants.map((v) => v.toInsertMap(productId)).toList(),
      );
}

// 5. Sync inventory from variants — one row per unique size
await _syncInventoryFromVariants(productId, variants);

// 6. Insert customizations
```

**Called in `updateProduct()` after variants replace:**

```dart
// 3. Replace variants (delete + re-insert)
await _client.from('product_variants').delete().eq('product_id', productId);
if (variants.isNotEmpty) {
  await _client.from('product_variants').insert(
        variants.map((v) => v.toInsertMap(productId)).toList(),
      );
}

// 4. Sync inventory after variants are replaced
await _syncInventoryFromVariants(productId, variants);

// 5. Replace customizations
```

### Fix 2: `lib/services/product_service.dart` — Read Path

**`getProduct()`** — Added `inventory(*)` to select:

```dart
Future<Map<String, dynamic>> getProduct(String productId) async {
  return await _client
      .from('products')
      .select(
          '*, product_images(*), product_variants(*), product_customizations(*), inventory(*)')
      .eq('id', productId)
      .single();
}
```

**`getSellerProducts()`** — Added `inventory(*)` to select:

```dart
Future<List<Map<String, dynamic>>> getSellerProducts() async {
  final sellerId = _client.auth.currentUser!.id;
  final data = await _client
      .from('products')
      .select(
          '*, product_images(*), product_variants(*), product_customizations(*), inventory(*)')
      .eq('seller_id', sellerId)
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(data);
}
```

### Fix 3: `lib/screens/customer/product_detail_screen.dart`

**Added `_buildSizesMap()` helper:**

```dart
Map<String, int> _buildSizesMap() {
  final Map<String, int> sizes = {};

  // From inventory table (primary source)
  final inventory = widget.product['inventory'] as List<dynamic>? ?? [];
  for (final row in inventory) {
    final size = row['size']?.toString();
    final stock = row['stock'] as int? ?? 0;
    if (size != null && size.isNotEmpty) {
      sizes[size] = (sizes[size] ?? 0) + stock;
    }
  }

  // From product_variants table (fallback / supplementary)
  final variants = widget.product['product_variants'] as List<dynamic>? ?? [];
  for (final row in variants) {
    final size = row['size']?.toString();
    final stock = row['stock'] as int? ?? 0;
    if (size != null && size.isNotEmpty) {
      sizes[size] = ((sizes[size] ?? 0) < stock) ? stock : (sizes[size] ?? 0);
    }
  }

  // Sort numerically by EU size
  return Map.fromEntries(
    sizes.entries.toList()
      ..sort((a, b) =>
          (int.tryParse(a.key) ?? 0).compareTo(int.tryParse(b.key) ?? 0)),
  );
}
```

**Fixed `initState()` and `build()`** to use `_buildSizesMap()` instead of
the non-existent `widget.product['sizes']` key.

### Database Schema

**`inventory` table** — one row per product per size:

```sql
CREATE TABLE public.inventory (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id  UUID REFERENCES public.products(id) ON DELETE CASCADE NOT NULL,
    size        TEXT NOT NULL,
    stock       INTEGER NOT NULL DEFAULT 0,
    updated_at  TIMESTAMP WITH TIME ZONE DEFAULT now() NOT NULL
);
```

**`product_variants` table** — one row per product per size+color:

```sql
CREATE TABLE public.product_variants (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id       UUID REFERENCES public.products(id) ON DELETE CASCADE NOT NULL,
    size             TEXT NOT NULL,
    color            TEXT,
    stock            INTEGER DEFAULT 0,
    additional_price NUMERIC DEFAULT 0,
    sku              TEXT,
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT now()
);
```

**Relationship:** `product_variants` holds granular stock per size+color.
`inventory` holds aggregated stock per size (summed across all colors).

---

## Improvement #1: Profile Fetch Timeout

### Problem

If the network is slow, the profile fetch in `AuthGate` could take indefinitely,
leaving the user stuck on the loading spinner.

### Solution: `lib/screens/auth_gate.dart`

Added a **12-second timeout** on the profile fetch:

```dart
static const _profileTimeout = Duration(seconds: 12);

Future<Map<String, dynamic>?> _profileFor(User user) {
  if (_profileFuture == null || _profileUserId != user.id) {
    _profileUserId = user.id;
    _profileFuture = _authService
        .getProfile(user.id)
        .timeout(_profileTimeout);
  }
  return _profileFuture!;
}
```

Added `import 'dart:async';` for `TimeoutException` support.

When the timeout fires, the `FutureBuilder` catches the error and shows the
`ErrorRetryWidget` with a retry button.

---

## Improvement #2: Offline Detection

### Problem

When the device has no internet connection, the loading screen spins forever
with no feedback.

### Solution: `lib/screens/auth_gate.dart`

**Added `_hasConnection()` method:**

```dart
Future<bool> _hasConnection() async {
  try {
    final result = await InternetAddress.lookup('google.com')
        .timeout(const Duration(seconds: 5));
    return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}
```

**Added `_ProfileErrorView` widget** that checks connectivity on init:

- Shows a brief loading spinner while checking
- If **offline**: displays a "No Internet Connection" screen with wifi-off icon,
  message, and retry button
- If **online** but profile fetch failed: shows the existing `ErrorRetryWidget`
  with a friendly timeout message

Applied to **both paths** in `AuthGate`:
1. The `ConnectionState.waiting` path (existing session)
2. The stream-connected path (new login)

Added `import 'dart:io';` for `InternetAddress`.

---

## Improvement #3: Size Selector Loading Skeleton

### Problem

When inventory data is missing from the product map (e.g., parent screen didn't
include `inventory(*)` in its query), the size selector area is blank with no
indication that data is loading.

### Solution: `lib/screens/customer/product_detail_screen.dart`

**Added `_isLoadingSizes` state flag** and **`_fetchInventory()` fallback:**

```dart
Future<void> _fetchInventory() async {
  if (!mounted) return;
  setState(() => _isLoadingSizes = true);

  try {
    final productId = widget.product['id'].toString();
    final data = await Supabase.instance.client
        .from('products')
        .select('inventory(*), product_variants(*)')
        .eq('id', productId)
        .single();

    if (!mounted) return;

    setState(() {
      widget.product['inventory'] = data['inventory'];
      widget.product['product_variants'] = data['product_variants'];
      _isLoadingSizes = false;
    });

    // Auto-select first available size after data loads
    final sizesMap = _buildSizesMap();
    for (final entry in sizesMap.entries) {
      if (entry.value > 0) {
        _selectedSize = entry.key;
        break;
      }
    }
  } catch (_) {
    if (mounted) setState(() => _isLoadingSizes = false);
  }
}
```

**Added `_buildSizeSkeleton()` shimmer widget:**

```dart
Widget _buildSizeSkeleton() {
  return Shimmer.fromColors(
    baseColor: AppConstants.borderGray.withOpacity(0.3),
    highlightColor: AppConstants.borderGray.withOpacity(0.1),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(5, (_) => Container(
          width: 48, height: 48,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
        )),
      ),
    ),
  );
}
```

In `initState()`, if `_buildSizesMap()` returns empty, `_fetchInventory()` is
called and the skeleton is shown while loading.

---

## Reference Copies

All modified source files were copied to `docs/debug/` for reference:

| File | Source | Purpose |
|------|--------|---------|
| `auth_provider.dart` | `lib/providers/auth_provider.dart` | Auth state management with login/logout fixes |
| `auth_service.dart` | `lib/services/auth_service.dart` | Supabase auth calls with session-clear fix |
| `auth_gate.dart` | `lib/screens/auth_gate.dart` | Stream-based routing, timeout, offline detection |
| `login_screen.dart` | `lib/screens/auth/login_screen.dart` | Login form UI |
| `biometric_service.dart` | `lib/services/biometric_service.dart` | Biometric auth + credential storage |
| `product_detail_screen.dart` | `lib/screens/customer/product_detail_screen.dart` | Customer product detail with size selector fix |
| `product_service.dart` | `lib/services/product_service.dart` | Product CRUD with inventory sync |
| `inventory_backfill.sql` | *(new file)* | SQL script to populate inventory for existing products |
| `README.md` | *(new file)* | Overview of the debug folder |

---

## SQL Migration

### Backfill Script: `docs/debug/inventory_backfill.sql`

Run this **once** in the Supabase SQL Editor after deploying the code fix:

```sql
-- Step 1: Add unique constraint (skip if already exists)
ALTER TABLE public.inventory
  ADD CONSTRAINT inventory_product_size_unique UNIQUE (product_id, size);

-- Step 2: Backfill inventory from product_variants
INSERT INTO public.inventory (product_id, size, stock, updated_at)
SELECT
  product_id,
  size,
  SUM(stock) AS stock,
  now() AS updated_at
FROM public.product_variants
WHERE size IS NOT NULL AND size <> ''
GROUP BY product_id, size
ON CONFLICT (product_id, size) DO UPDATE
  SET stock = EXCLUDED.stock,
      updated_at = now();
```

**What this does:** Aggregates stock by size from `product_variants` (summing
across all colors) and inserts one row per unique size into `inventory`. Uses
`ON CONFLICT` to update rows that already exist.

---

## Files Modified

| # | File | Changes |
|---|------|---------|
| 1 | `lib/providers/auth_provider.dart` | State reset in `login()` and `signOut()` |
| 2 | `lib/services/auth_service.dart` | Session-clear before `signIn()` |
| 3 | `lib/screens/auth_gate.dart` | Direct widget returns, profile timeout, offline detection, `PendingApprovalScreen` logout fix |
| 4 | `lib/services/product_service.dart` | `_syncInventoryFromVariants()` helper, inventory sync in `createProduct()`/`updateProduct()`, `inventory(*)` in read queries |
| 5 | `lib/screens/customer/product_detail_screen.dart` | `_buildSizesMap()` helper, `_fetchInventory()` fallback, loading skeleton |
| 6 | `docs/debug/inventory_backfill.sql` | SQL backfill script for existing products |
| 7 | `docs/debug/README.md` | Debug folder overview |
| 8 | `docs/debug/*.dart` | Reference copies of all modified source files |

---

## Testing Checklist

### Auth Flow — Account Switching

- [ ] Log in as customer → Logout → Log in as seller → Navigates to SellerShell
- [ ] Log in as seller → Logout → Log in as admin → Navigates to AdminShell
- [ ] Log in as Account A → Logout → Log in as Account A again → Works correctly
- [ ] Rapid switch: Log in → Logout → Log in immediately → No freeze
- [ ] Log in as pending seller → Tap Log Out on PendingApprovalScreen → Returns to login with state cleared
- [ ] Fresh install → Onboarding shows → Complete onboarding → Login → Works

### Auth Flow — Error Handling

- [ ] Log in with wrong password → Error shown → Correct password → Login succeeds
- [ ] Slow network → 12s timeout → Retry screen with friendly message
- [ ] No internet → "No Internet Connection" screen with retry button

### Product Flow — Size Selector

- [ ] Open product with inventory rows only → Sizes appear, first available pre-selected
- [ ] Open product with product_variants rows only → Sizes appear correctly
- [ ] Open product with both tables → Sizes deduplicated, stock correct
- [ ] Open product with all stock = 0 → All chips strikethrough, no auto-selection
- [ ] Navigate from customer home → Product detail → Sizes load correctly
- [ ] Create new product with variants → Inventory table populated
- [ ] Update product stock → Inventory table updated
- [ ] Remove all variants from product → Inventory rows cleared

### SQL Backfill

- [ ] Run `inventory_backfill.sql` in Supabase SQL Editor
- [ ] Verify existing products now have inventory rows
- [ ] Verify customer size selector works for pre-existing products

---

## Design System Reference

| Token | Value | Usage |
|-------|-------|-------|
| Primary (Burnished Clay) | `AppConstants.primary` / `#8B5A2B` | Buttons, active states, selected chips |
| Surface Light (Off-White Suede) | `AppConstants.surfaceLight` / `#F5F0EB` | Backgrounds, selected chip text |
| Error (Crimson Welt) | `AppConstants.error` / `#D64545` | Error messages, out-of-stock strikethrough |
| Success | `AppConstants.success` | "Added to Cart" SnackBar |
| Border Gray | `AppConstants.borderGray` / `#D2C7BC` | Unselected chip borders |
| Secondary (Carob Dark) | `AppConstants.secondary` / `#3B2314` | Unselected chip text |
| Monospace font | JetBrains Mono via `AppConstants.monoStyle()` | Size chip labels, prices |
| Body font | DM Sans via `AppConstants.bodyStyle()` | All body text and labels |
| Headline font | Playfair Display via `AppConstants.headlineStyle()` | Screen titles |
| Button radius | `AppConstants.buttonRadius` (12px) | All buttons and chips |

---

*SoleVision v1.1.0 — Session documented June 30, 2026*
