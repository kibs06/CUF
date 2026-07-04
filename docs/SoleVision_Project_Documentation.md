# SoleVision — Project Documentation

**Version:** 1.0.0  
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
    id            BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    name          TEXT NOT NULL,
    category      TEXT NOT NULL,
    price         NUMERIC NOT NULL CHECK (price >= 0),
    description   TEXT,
    images        TEXT[] NOT NULL DEFAULT '{}',
    sizes         JSONB NOT NULL DEFAULT '{}',
    store_id      UUID REFERENCES public.stores(id),
    is_featured   BOOLEAN NOT NULL DEFAULT false,
    collection    TEXT,
    created_at    TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL
);
```

### 4.3 Orders Table
```sql
CREATE TABLE public.orders (
    id               BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    customer_id      UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    product_id       BIGINT REFERENCES public.products(id) ON DELETE SET NULL,
    status           TEXT NOT NULL DEFAULT 'placed'
                     CHECK (status IN ('placed', 'preparing', 'ready', 'received')),
    size             TEXT NOT NULL,
    color            TEXT NOT NULL,
    quantity         INTEGER NOT NULL CHECK (quantity > 0),
    total_amount     NUMERIC NOT NULL CHECK (total_amount >= 0),
    delivery_address TEXT NOT NULL,
    payment_method   TEXT NOT NULL,
    created_at       TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL
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

### 4.6 Story Entries Table
```sql
CREATE TABLE public.story_entries (
    id             BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    store_id       UUID REFERENCES public.stores(id) ON DELETE CASCADE,
    title          TEXT NOT NULL,
    body_text      TEXT NOT NULL,
    image_url      TEXT,
    display_order  INTEGER NOT NULL DEFAULT 0,
    created_at     TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL
);
```

### 4.7 Store Follows Table
```sql
CREATE TABLE public.store_follows (
    user_id    UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    store_id   UUID REFERENCES public.stores(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc', now()) NOT NULL,
    PRIMARY KEY (user_id, store_id)
);
```

### 4.8 Seed Data
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

## Appendix A: File Structure Reference

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

*Document generated by Codebuff on June 28, 2026.*
