# SoleVision — What Is This App?

**Last Updated:** August 12, 2026

---

## One-Liner

SoleVision is a **multi-role marketplace app** that connects artisans, customers, and admins for handcrafted leather footwear retail in **Carcar City, Cebu, Philippines** — the hometown of the region's shoe industry.

---

## The Problem It Solves

Carcar City is a known hub for handcrafted shoes and sandals, but local artisans (mostly members of CUFMAI — the Carcar United Footwear Manufacturers Association Inc.) sell through traditional channels with no digital storefront. Customers outside the city have no easy way to discover, order, and track these handcrafted products.

SoleVision bridges that gap with a single platform where:

- **Customers** discover and buy artisan footwear online (with delivery or pickup).
- **Sellers/artisans** get a digital storefront, order management, and a POS for walk-in sales.
- **Admins** curate the marketplace by approving sellers and monitoring activity.

---

## The Three Roles

| Role | Who | What They Can Do |
|------|-----|------------------|
| **Customer** | Shoe buyers | Browse stores and products, add to cart, checkout (cash / GCash / card), track orders, follow stores, message sellers, order custom-designed shoes, virtual try-on |
| **Seller** | CUFMAI member artisans | Run a store page, manage products and inventory, process online orders (prepare → ready → received), execute in-person POS sales, view revenue and sales reports, chat with customers |
| **Admin** | Marketplace operator | Approve/reject seller applications, manage users and products, view analytics (revenue, orders, trends) via mobile app and a web portal |

---

## Key Features

### Customer Side
- **Product catalog** — category filtering, search, featured and on-sale sections, store discovery with follow/unfollow
- **Cart & checkout** — store-grouped cart, per-item selection, stock validation before order, delivery fee, address book with map pin-drop
- **Payments** — cash on pickup/delivery and GCash (via PayMongo / QR)
- **Order tracking** — vertical timeline: Placed → Preparing → Ready for Pickup → Received
- **Customization** — 5-step wizard to design bespoke shoes (base design, color, material, special requests)
- **Virtual try-on** — AR-style fitting screen (simulated, current version)
- **Messaging** — chat with sellers, attachments included
- **Notifications** — order updates, categorized (Unpaid, Processing, Shipped, Review, Returns)

### Seller Side
- **Dashboard** — today's sales, order metrics, revenue
- **Product & inventory management** — upload products, manage variants (size/color/stock)
- **Order flow** — online orders with status management and delivery/pickup handling
- **POS** — register-based point of sale for walk-in transactions (cash / GCash / card), including custom orders
- **Reports & revenue** — combines online orders + POS transactions
- **Ratings & reviews** — store ratings from customers

### Admin Side
- **Seller approval** — review and approve/reject seller applications
- **Analytics** — revenue, orders, top products, trends
- **User & product management**
- Available as a **Flutter admin app** and a **React web portal**

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Mobile app | Flutter (Dart), Provider for state management |
| Admin portal | React + Vite + Tailwind CSS, TanStack React Query |
| Backend | Supabase (PostgreSQL with Row-Level Security, Auth, Storage) |
| Payments | PayMongo (GCash) + manual GCash QR verification |
| Mapping | MapTiler (address pin-drop, geocoding) |
| Currency | Philippine Peso (₱) |

---

## Architecture in One Diagram

```
┌──────────────┐    ┌──────────────┐
│  Flutter App │    │ React Admin  │
│ (customer /  │    │  Portal      │
│  seller /    │    └──────┬───────┘
│  admin)      │           │
└──────┬───────┘           │
       │                   │
       └────────┬──────────┘
                ▼
          SUPABASE
   ┌────────────────────────┐
   │ Auth (email/password,  │
   │  JWT, biometrics)      │
   │ Postgres + RLS         │
   │ Storage (images)       │
   │ Realtime (messaging)   │
   └────────────────────────┘
```

**Layering inside the Flutter app:**

```
Screen (UI) → Provider (state) → Service (data access) → Supabase
```

---

## Core Business Rules

1. **Sellers must be approved** — anyone can apply to sell during sign-up, but they get only a "pending" screen until an admin approves them.
2. **Inventory is authoritative** — stock is validated against the `inventory` table at checkout, and DB triggers decrement stock on every order/POS sale.
3. **Revenue = online orders + POS** — reporting always combines both sources.
4. **Profile defines access** — routing is decided by `profiles.role` (`customer` / `seller` / `admin`) and `seller_status` (`none` / `pending` / `approved` / `rejected`).

---

## Why It Matters (The Story)

SoleVision is a capstone project that digitizes an entire local industry. Instead of replacing the artisans, it gives them the same tools big brands have — a storefront, order tracking, and a POS — while preserving the craftsmanship story of Carcar: full-grain leather, hand-stitched welts, and designs rooted in Cebuano tradition.

---

## Related Documentation

| Document | What It Covers |
|----------|----------------|
| `docs/AI_PROJECT_SUMMARY.md` | AI-agent quick reference for the whole project |
| `docs/SoleVision_Complete_Documentation.md` | Master reference (schema, RLS, services, history) |
| `docs/PROJECT_HANDOFF.md` | Decisions, known issues, what's next |
| `docs/SIGNUP_ARCHITECTURE.md` | Customer & seller sign-up flow deep-dive |
| `docs/CUSTOMER_ARCHITECTURE.md` | Customer module deep-dive |
| `docs/SELLER_MODULE_GUIDE.md` | Seller module deep-dive |
| `docs/AI/SIGNUP_ARCHITECTURE.md` | Condensed sign-up reference for AI agents |
