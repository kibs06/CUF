# SoleVision — Capstone System Security Analysis

**Project:** SoleVision — AR-Powered Footwear Marketplace  
**Date:** August 21, 2026  
**Version:** 1.0

---

## 1. Capstone System Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              SOLEVISION SYSTEM ARCHITECTURE                      │
└─────────────────────────────────────────────────────────────────────────────────┘

                          ┌──────────────────────┐
                          │      END USERS        │
                          │  ┌────────────────┐   │
                          │  │   Customers    │   │
                          │  │ (Mobile App)   │   │
                          │  └────────┬───────┘   │
                          │  ┌────────┴───────┐   │
                          │  │    Sellers     │   │
                          │  │ (Mobile App)   │   │
                          │  └────────┬───────┘   │
                          │  ┌────────┴───────┐   │
                          │  │   Admins       │   │
                          │  │ (Web Portal)   │   │
                          │  └────────┬───────┘   │
                          └───────────┼───────────┘
                                      │
                     ┌────────────────┼────────────────┐
                     │                │                 │
                     ▼                ▼                 ▼
          ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
          │  Flutter App  │  │  Flutter App  │  │  Vue.js App  │
          │  (Customer/   │  │  (Seller)     │  │  (Admin      │
          │   Seller)     │  │               │  │   Portal)    │
          └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
                 │                  │                  │
                 │    HTTPS/REST    │    HTTPS/REST    │
                 └────────┬────────┘────────┬────────┘
                          │                 │
                          ▼                 ▼
         ┌─────────────────────────────────────────────────┐
         │              SUPABASE BACKEND                    │
         │  ┌─────────────┐  ┌─────────────┐  ┌────────┐  │
         │  │  PostgreSQL  │  │  Auth        │  │Storage │  │
         │  │  Database    │  │  (JWT/RLS)   │  │(Files) │  │
         │  │  + RLS       │  │              │  │        │  │
         │  └──────┬──────┘  └──────┬──────┘  └───┬────┘  │
         │         │                │              │        │
         │  ┌──────┴──────┐  ┌──────┴──────┐  ┌───┴────┐  │
         │  │   Realtime   │  │   Edge      │  │  S3    │  │
         │  │  (WebSocket) │  │  Functions  │  │Bucket  │  │
         │  └──────┬──────┘  └──────┬──────┘  └───┬────┘  │
         └─────────┼────────────────┼──────────────┼───────┘
                   │                │              │
                   ▼                ▼              ▼
    ┌──────────────────────────────────────────────────────┐
    │                 EXTERNAL SERVICES                     │
    │  ┌────────────┐ ┌────────────┐ ┌──────────────────┐ │
    │  │ Firebase    │ │ MapTiler   │ │ GCash/PayMongo   │ │
    │  │ (FCM Push)  │ │ (Maps)     │ │ (Payments)       │ │
    │  └────────────┘ └────────────┘ └──────────────────┘ │
    │  ┌────────────┐ ┌────────────┐ ┌──────────────────┐ │
    │  │ GitHub     │ │ Unsplash   │ │ ML Kit           │ │
    │  │ (Releases) │ │ (Images)   │ │ (On-Device AR)   │ │
    │  └────────────┘ └────────────┘ └──────────────────┘ │
    └──────────────────────────────────────────────────────┘
```

### Data Flow Diagram

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Customer   │────▶│  Supabase   │────▶│   Sellers   │
│  App        │     │  Realtime   │     │   App       │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       │   ┌───────────────┼───────────────┐   │
       │   │               │               │   │
       ▼   ▼               ▼               ▼   ▼
┌─────────────────────────────────────────────────────┐
│                    DATA LAYER                        │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌──────────┐ │
│  │profiles │ │products │ │ orders  │ │messages  │ │
│  │(PII)    │ │(catalog)│ │(txn)    │ │(chat)    │ │
│  └─────────┘ └─────────┘ └─────────┘ └──────────┘ │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌──────────┐ │
│  │stores   │ │reviews  │ │addresses│ │verify_   │ │
│  │(business)│ │(social) │ │(geo)    │ │docs(ID)  │ │
│  └─────────┘ └─────────┘ └─────────┘ └──────────┘ │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐              │
│  │foot_    │ │payment_ │ │conver-  │              │
│  │measure  │ │intents  │ │sations  │              │
│  │(AR data)│ │(GCash)  │ │(realtime)│             │
│  └─────────┘ └─────────┘ └─────────┘              │
└─────────────────────────────────────────────────────┘
```

---

## 2. Asset / Dependency Map

### 2.1 Primary Assets

| Asset | Type | Sensitivity | Storage Location | Access Controls |
|-------|------|-------------|------------------|-----------------|
| User credentials (email/password) | Authentication | **HIGH** | Supabase Auth (hashed) | Auth middleware + RLS |
| Profile PII (name, phone, email, gender, birthday) | Personal Data | **HIGH** | `profiles` table | RLS: self + admin |
| Delivery addresses | Personal Data | **MEDIUM** | `customer_addresses` table | RLS: self only |
| Government-issued ID photos | Identity Document | **CRITICAL** | Supabase Storage (private bucket) | RLS: owner + admin |
| Selfie verification photos | Biometric | **CRITICAL** | Supabase Storage (private bucket) | RLS: owner + admin |
| Business registration docs | Organizational | **HIGH** | Supabase Storage (private bucket) | RLS: owner + admin |
| Foot measurement data (AR) | Biometric | **HIGH** | `foot_measurements` table | RLS: self only |
| Order & transaction records | Financial | **HIGH** | `orders`, `order_items`, `payment_intents` | RLS: customer + seller + admin |
| GCash payment references | Financial | **HIGH** | `payment_intents`, `gcash_payment_queue` | RLS: customer + seller + admin |
| Chat messages | Communication | **MEDIUM** | `messages` table | RLS: conversation participants |
| Product images & store logos | Business IP | **MEDIUM** | Supabase Storage (public buckets) | RLS: owner + admin |
| FCM device tokens | Device Identity | **MEDIUM** | `device_tokens` table | RLS: self only |
| Admin portal credentials | Authentication | **CRITICAL** | Supabase Auth | Admin role check |
| Supabase API keys | System Secret | **CRITICAL** | App constants / env vars | Embedded in client |
| Service role key | System Secret | **CRITICAL** | Edge Function env | Server-side only |
| FCM service account key | System Secret | **CRITICAL** | Edge Function env | Server-side only |
| PayMongo secret key | System Secret | **CRITICAL** | Edge Function env | Server-side only |

### 2.2 Software Dependencies

| Dependency | Purpose | Risk Level | Notes |
|------------|---------|------------|-------|
| **Flutter SDK** | Mobile app framework | Low | Cross-platform (Android/iOS) |
| **Supabase Flutter SDK** | Backend integration | Medium | Handles auth, DB, storage |
| **Provider** | State management | Low | Local state only |
| **Google ML Kit** | AR foot measurement | Medium | On-device processing only |
| **Firebase Messaging** | Push notifications | Medium | Requires FCM token management |
| **GCash/PayMongo SDK** | Payment processing | High | Financial transaction handling |
| **MapTiler** | Map tiles | Low | Read-only tile service |
| **shared_preferences** | Local caching | Low | No sensitive data stored |
| **flutter_secure_storage** | Secure local storage | Medium | Auth tokens, biometric prefs |
| **local_auth** | Biometric auth | Medium | Local device auth only |
| **camera** | AR capture | Medium | Device permission required |
| **image_picker** | Photo selection | Low | User-initiated only |
| **url_launcher** | Deep links | Low | External URL handling |
| **connectivity_plus** | Network status | Low | Read-only system info |
| **mobile_scanner** | Barcode scanning | Low | POS feature only |
| **sensors_plus** | Device sensors | Low | AR calibration support |

### 2.3 External Service Dependencies

| Service | Provider | Purpose | Data Exchanged | Risk Level |
|---------|----------|---------|----------------|------------|
| **Supabase** | Supabase Inc. | Database, Auth, Storage, Realtime, Edge Functions | All app data | **HIGH** |
| **Firebase Cloud Messaging** | Google | Push notifications | Device tokens, notification payloads | **MEDIUM** |
| **MapTiler** | MapTiler | Map tiles, geocoding | Map tile requests, coordinates | **LOW** |
| **GCash/PayMongo** | Globe/PayMongo | Payment processing | Payment amounts, transaction refs | **HIGH** |
| **GitHub Releases** | GitHub | APK distribution | App binaries, version manifests | **LOW** |
| **Unsplash** | Getty Images | Placeholder images | Image URLs (dev only) | **LOW** |

### 2.4 Infrastructure Dependencies

| Component | Location | Purpose | Redundancy |
|-----------|----------|---------|------------|
| Supabase Database | Supabase Cloud (US) | PostgreSQL hosting | Auto-backups (paid plan) |
| Supabase Auth | Supabase Cloud | JWT authentication | Built-in redundancy |
| Supabase Storage | Supabase Cloud | File storage (S3) | S3 durability |
| Supabase Edge Functions | Supabase Cloud | Serverless compute | Auto-scaling |
| GitHub | GitHub Cloud | Source control + releases | Git distributed |
| Firebase | Google Cloud | Push notification delivery | Google infrastructure |

---

## 3. Threat List

### 3.1 Threat Categories

#### T1: Authentication & Access Control Threats

| ID | Threat | Description | Affected Assets | Attack Vector |
|----|--------|-------------|-----------------|---------------|
| T1.1 | **Credential Stuffing** | Attackers use leaked email/password pairs to gain unauthorized access | User accounts, profiles | Supabase Auth login endpoint |
| T1.2 | **Brute Force Attack** | Automated attempts to guess user passwords | User accounts | Login endpoint (rate limited: 30/5min) |
| T1.3 | **JWT Token Theft** | Stealing JWT tokens from client storage or network traffic | All authenticated resources | Device compromise, MITM |
| T1.4 | **Session Hijacking** | Reusing stolen refresh tokens to impersonate users | User sessions | Token leakage, device theft |
| T1.5 | **Role Escalation** | Customer or seller manipulating role to gain admin access | Admin functions, all data | Client-side tampering, API abuse |
| T1.6 | **Missing MFA** | No multi-factor authentication enabled for any user role | All accounts | Credential compromise |
| T1.7 | **Weak Password Policy** | Minimum 6 characters, no complexity requirements enforced | User accounts | Password guessing |

#### T2: Authorization & Access Control Threats

| ID | Threat | Description | Affected Assets | Attack Vector |
|----|--------|-------------|-----------------|---------------|
| T2.1 | **IDOR (Insecure Direct Object Reference)** | Accessing other users' orders, addresses, or data by manipulating IDs | Orders, addresses, messages | API parameter manipulation |
| T2.2 | **RLS Policy Bypass** | Exploiting RLS gaps to read/write unauthorized data | All RLS-protected tables | SQL injection, policy misconfiguration |
| T2.3 | **Cross-Seller Data Access** | Seller A accessing Seller B's products or orders | Products, orders, sales data | RLS policy gap (fixed in migration 20260712) |
| T2.4 | **Admin Panel Unauthorized Access** | Non-admin users accessing admin portal functions | User management, approvals | Missing server-side role check |
| T2.5 | **Storage Bucket Unauthorized Access** | Accessing private verification documents | ID photos, selfies, business docs | Storage RLS misconfiguration |
| T2.6 | **Message Read Unauthorized** | Reading other users' private chat messages | Conversations, messages | Conversation RLS gaps |

#### T3: Data Exposure Threats

| ID | Threat | Description | Affected Assets | Attack Vector |
|----|--------|-------------|-----------------|---------------|
| T3.1 | **PII Leakage via Profiles** | Public profile SELECT exposes email addresses to all users | Email, phone, personal info | RLS policy `USING (true)` |
| T3.2 | **API Key Exposure** | Supabase anon key embedded in client bundle | API access | Reverse engineering, decompilation |
| T3.3 | **Git History Credentials** | Hardcoded Supabase URL and anon key in git history | API credentials | Repository access, git log |
| T3.4 | **Verification Document Exposure** | Private ID documents becoming publicly accessible | Government IDs, selfies | Storage bucket policy error |
| T3.5 | **Foot Measurement Data Leak** | AR biometric data exposed to unauthorized parties | Foot length, width, arch height | RLS bypass on foot_measurements |
| T3.6 | **Payment Reference Exposure** | GCash account identifiers visible to other users | Payment methods, transaction refs | API response over-exposure |

#### T4: Injection & Input Validation Threats

| ID | Threat | Description | Affected Assets | Attack Vector |
|----|--------|-------------|-----------------|---------------|
| T4.1 | **SQL Injection** | Malicious SQL in search queries, product names, or forms | Database, all tables | User input fields |
| T4.2 | **Cross-Site Scripting (XSS)** | Script injection in product descriptions, reviews, or chat | Admin portal, web views | Stored XSS in user content |
| T4.3 | **NoSQL Injection** | Manipulating Supabase query parameters | Database queries | API parameter tampering |
| T4.4 | **Edge Function Injection** | Exploiting unvalidated inputs in Edge Functions | Push notifications, payments | Function endpoint abuse |
| T4.5 | **File Upload Malware** | Uploading malicious files disguised as images | Storage, other users | Product images, avatars |

#### T5: Payment & Financial Threats

| ID | Threat | Description | Affected Assets | Attack Vector |
|----|--------|-------------|-----------------|---------------|
| T5.1 | **Payment Tampering** | Modifying order amounts during checkout | Order totals, payment records | Client-side manipulation |
| T5.2 | **Double Spending** | Submitting multiple payment requests for one order | Payment integrity | Race condition, replay attack |
| T5.3 | **GCash QR Forgery** | Displaying fake GCash QR codes to intercept payments | Seller payments | Visual social engineering |
| T5.4 | **Webhook Forgery** | Fake PayMongo webhook calls to confirm unpaid orders | Payment status | Unauthenticated webhook endpoint |
| T5.5 | **Refund Fraud** | Requesting refunds for delivered orders | Financial records | Customer-side abuse |

#### T6: Availability & Service Threats

| ID | Threat | Description | Affected Assets | Attack Vector |
|----|--------|-------------|-----------------|---------------|
| T6.1 | **DDoS on Supabase** | Overwhelming the database with requests | All services | Distributed request flood |
| T6.2 | **Edge Function Abuse** | Spamming push notification functions | Notification system | Unauthenticated function calls |
| T6.3 | **Storage Exhaustion** | Uploading excessive files to fill storage | Storage quota | Repeated large file uploads |
| T6.4 | **Realtime Connection Flooding** | Exhausting WebSocket connections | Realtime messaging | Connection pool exhaustion |
| T6.5 | **Supabase Free Tier Limits** | Hitting row, storage, or bandwidth limits | Service availability | Normal usage on free tier |

#### T7: Mobile Device Threats

| ID | Threat | Description | Affected Assets | Attack Vector |
|----|--------|-------------|-----------------|---------------|
| T7.1 | **Device Theft** | Physical access to unlocked device exposes app data | Local storage, sessions | Device loss/theft |
| T7.2 | **Rooted/Jailbroken Device** | Running app on compromised device bypasses security | All app data | Device compromise |
| T7.3 | **Man-in-the-Middle (MITM)** | Intercepting HTTPS traffic on compromised networks | API communications | Rogue WiFi, DNS hijacking |
| T7.4 | **Screen Recording/Capture** | Capturing sensitive screens (payment, verification) | UI content | Malware, screen recorder |
| T7.5 | **App Reverse Engineering** | Decompiling APK to extract secrets or logic | API keys, business logic | APK decompilation tools |
| T7.6 | **Local Storage Extraction** | Extracting SharedPreferences/SecureStorage data | Auth tokens, cached data | Root access, backup extraction |

#### T8: Third-Party Service Threats

| ID | Threat | Description | Affected Assets | Attack Vector |
|----|--------|-------------|-----------------|---------------|
| T8.1 | **Supabase Outage** | Supabase service becomes unavailable | All app functionality | Provider infrastructure failure |
| T8.2 | **Firebase Compromise** | FCM service credentials leaked | Push notification delivery | Credential exposure |
| T8.3 | **PayMongo API Breach** | Payment processor security incident | Payment data, transactions | Third-party breach |
| T8.4 | **MapTiler Service Disruption** | Map tiles fail to load | Store locations, AR calibration | Provider outage |
| T8.5 | **GitHub Repository Breach** | Source code or release artifacts compromised | Source code, APK binaries | Repository access |

#### T9: Privacy & Compliance Threats

| ID | Threat | Description | Affected Assets | Attack Vector |
|----|--------|-------------|-----------------|---------------|
| T9.1 | **GDPR/DPA Violation** | Processing personal data without proper consent | All PII | Missing privacy controls |
| T9.2 | **Data Retention Violation** | Keeping user data longer than necessary | All user data | No deletion mechanism |
| T9.3 | **Biometric Data Misuse** | Using foot measurement data for unauthorized purposes | Foot measurements | Data repurposing |
| T9.4 | **Cross-Border Data Transfer** | Storing Philippine user data on US servers | All data | Supabase hosting location |
| T9.5 | **Minor Data Collection** | Collecting data from users under 13 | All user data | No age verification enforcement |

#### T10: Operational Threats

| ID | Threat | Description | Affected Assets | Attack Vector |
|----|--------|-------------|-----------------|---------------|
| T10.1 | **No Audit Logging** | Inability to track who did what and when | Forensics, compliance | Missing audit trail |
| T10.2 | **No Incident Response Plan** | No documented procedure for security incidents | All assets | Unprepared response |
| T10.3 | **Single Point of Failure** | All infrastructure on Supabase cloud | Service availability | Provider failure |
| T10.4 | **No Penetration Testing** | System has never been professionally tested | All assets | Unknown vulnerabilities |
| T10.5 | **Dependency Vulnerabilities** | Known CVEs in Flutter/Dart packages | App security | Outdated dependencies |

---

## 4. Risk Rationale

### 4.1 Risk Scoring Matrix

| Likelihood | Impact | Risk Level |
|------------|--------|------------|
| Rare (1) | Negligible (1) | **Low** (1-2) |
| Unlikely (2) | Minor (2) | **Low** (3-4) |
| Possible (3) | Moderate (3) | **Medium** (5-9) |
| Likely (4) | Major (4) | **High** (10-12) |
| Almost Certain (5) | Catastrophic (5) | **Critical** (13-25) |

### 4.2 Risk Assessment by Threat

| Threat ID | Threat | Likelihood (1-5) | Impact (1-5) | Risk Score | Risk Level | Rationale |
|-----------|--------|-------------------|--------------|------------|------------|-----------|
| T1.1 | Credential Stuffing | 3 | 4 | **12** | **High** | Common attack; Supabase has rate limiting but no breach notification system |
| T1.2 | Brute Force | 2 | 4 | **8** | **Medium** | Rate limited (30/5min) but no account lockout or CAPTCHA |
| T1.3 | JWT Token Theft | 3 | 5 | **15** | **Critical** | Tokens stored client-side; device compromise grants full access |
| T1.4 | Session Hijacking | 2 | 4 | **8** | **Medium** | Refresh token rotation enabled; reuse interval = 10s |
| T1.5 | Role Escalation | 1 | 5 | **5** | **Medium** | Roles stored server-side in profiles table; RLS enforces access |
| T1.6 | Missing MFA | 3 | 4 | **12** | **High** | No MFA configured; all accounts single-factor only |
| T1.7 | Weak Password Policy | 3 | 3 | **9** | **Medium** | Min 6 chars, no complexity requirement; easily guessable |
| T2.1 | IDOR | 2 | 4 | **8** | **Medium** | RLS policies enforce ownership; Supabase auto-filters queries |
| T2.2 | RLS Bypass | 2 | 5 | **10** | **High** | RLS is comprehensive but complex; policy gaps possible |
| T2.3 | Cross-Seller Data Access | 2 | 4 | **8** | **Medium** | Fixed in migration 20260712; verification needed on live DB |
| T2.4 | Admin Panel Unauthorized | 2 | 5 | **10** | **High** | Client-side role check only; no server-side admin verification |
| T2.5 | Storage Bucket Unauthorized | 1 | 5 | **5** | **Medium** | Private bucket with owner + admin RLS; well-configured |
| T2.6 | Message Read Unauthorized | 2 | 3 | **6** | **Medium** | Conversation participant RLS enforced; conversation_id validation |
| T3.1 | PII Leakage via Profiles | 4 | 3 | **12** | **High** | Public SELECT exposes emails; no column-level filtering |
| T3.2 | API Key Exposure | 4 | 2 | **8** | **Medium** | Anon key is designed to be public; low risk by design |
| T3.3 | Git History Credentials | 3 | 2 | **6** | **Medium** | Credentials in git history; anon key rotation recommended |
| T3.4 | Verification Document Exposure | 1 | 5 | **5** | **Medium** | Private bucket; owner + admin RLS enforced |
| T3.5 | Foot Measurement Data Leak | 2 | 4 | **8** | **Medium** | Self-only RLS; biometric sensitivity requires extra care |
| T3.6 | Payment Reference Exposure | 2 | 3 | **6** | **Medium** | Customer + seller + admin RLS; no public access |
| T4.1 | SQL Injection | 1 | 5 | **5** | **Medium** | Supabase uses parameterized queries; PostgreSQL-level protection |
| T4.2 | XSS | 2 | 3 | **6** | **Medium** | Vue.js auto-escapes; Flutter WebView较少使用 |
| T4.4 | Edge Function Injection | 3 | 4 | **12** | **High** | No JWT verification on push functions; no input validation |
| T4.5 | File Upload Malware | 2 | 3 | **6** | **Medium** | Storage has file type restrictions; no server-side scanning |
| T5.1 | Payment Tampering | 1 | 5 | **5** | **Medium** | Order amounts calculated server-side; Supabase constraints |
| T5.4 | Webhook Forgery | 2 | 5 | **10** | **High** | PayMongo webhook has signature verification; verify on live |
| T6.1 | DDoS | 2 | 4 | **8** | **Medium** | Supabase has built-in DDoS protection; free tier limits help |
| T6.2 | Edge Function Abuse | 3 | 3 | **9** | **Medium** | No rate limiting on functions; abuse could drain quota |
| T6.5 | Free Tier Limits | 4 | 3 | **12** | **High** | 500MB storage, 50K monthly active users; production risk |
| T7.1 | Device Theft | 3 | 3 | **9** | **Medium** | Biometric auth optional; local storage encryption varies |
| T7.3 | MITM | 1 | 4 | **4** | **Low** | HTTPS enforced; Supabase uses TLS; certificate pinning absent |
| T7.5 | Reverse Engineering | 3 | 3 | **9** | **Medium** | APK easily decompiled; code obfuscation not configured |
| T8.1 | Supabase Outage | 2 | 5 | **10** | **High** | Single point of failure; no fallback database |
| T9.1 | GDPR/DPA Violation | 3 | 4 | **12** | **High** | Philippine Data Privacy Act applies; no consent mechanism |
| T10.1 | No Audit Logging | 4 | 3 | **12** | **High** | No application-level audit trail; only Supabase auth logs |

### 4.3 Risk Heat Map

```
                    IMPACT
         1      2      3      4      5
    ┌──────┬──────┬──────┬──────┬──────┐
  5 │      │      │      │      │      │
    ├──────┼──────┼──────┼──────┼──────┤
  4 │      │      │ T6.5 │ T3.1 │      │
L   ├──────┼──────┼──────┼──────┼──────┤
I 3 │      │ T3.2 │ T1.7 │ T1.1 │ T1.3 │
K   ├──────┼──────┼──────┼──────┼──────┤
E 2 │      │      │ T2.6 │ T2.1 │ T5.4 │
L   ├──────┼──────┼──────┼──────┼──────┤
I 1 │      │      │      │      │ T5.1 │
H   └──────┴──────┴──────┴──────┴──────┘
O
O     Low (1-4)    Medium (5-9)    High (10-12)    Critical (13-25)
D
```

---

## 5. Recommended Safeguards

### 5.1 Authentication & Access Control

| Priority | Safeguard | Addresses Threats | Implementation Effort | Status |
|----------|-----------|-------------------|----------------------|--------|
| **P0** | Enable Multi-Factor Authentication (TOTP) for admin accounts | T1.6 | Low (Supabase config) | ❌ Not implemented |
| **P0** | Enforce minimum 8-character passwords with complexity requirements | T1.7 | Low (Supabase config) | ❌ Current: 6 chars, no complexity |
| **P0** | Add server-side admin role verification in admin portal | T2.4 | Medium | ❌ Current: client-side only |
| **P1** | Implement account lockout after 5 failed login attempts | T1.2 | Medium (Edge Function) | ❌ Not implemented |
| **P1** | Add CAPTCHA to login/signup forms | T1.1, T1.2 | Medium | ❌ Not implemented |
| **P2** | Enable MFA for seller accounts with payment access | T1.6 | Low (Supabase config) | ❌ Not implemented |
| **P2** | Add session timeout (auto-logout after 24h inactivity) | T1.4 | Low (Supabase config) | ❌ Not implemented |

### 5.2 Data Protection & Privacy

| Priority | Safeguard | Addresses Threats | Implementation Effort | Status |
|----------|-----------|-------------------|----------------------|--------|
| **P0** | Create a `public_profiles` view excluding email; restrict `profiles` SELECT to non-sensitive columns | T3.1 | Medium (SQL view + RLS) | ❌ Current: public SELECT exposes all |
| **P0** | Implement data deletion endpoint (GDPR/DPA right to erasure) | T9.2 | High | ❌ No deletion mechanism |
| **P0** | Add privacy consent mechanism at signup | T9.1 | Medium (UI + DB) | ❌ No consent collection |
| **P1** | Encrypt sensitive fields at rest (payment references, foot measurements) | T3.5, T3.6 | High (application-level) | ❌ Not implemented |
| **P1** | Implement data retention policy (auto-delete inactive accounts after 2 years) | T9.2 | Medium (scheduled job) | ❌ Not implemented |
| **P2** | Add age verification at signup (minimum 13 years) | T9.5 | Low (UI validation) | ⚠️ Constant defined, not enforced |
| **P2** | Document data processing activities for Philippine DPA compliance | T9.1 | Medium (documentation) | ❌ Not documented |

### 5.3 Input Validation & Injection Prevention

| Priority | Safeguard | Addresses Threats | Implementation Effort | Status |
|----------|-----------|-------------------|----------------------|--------|
| **P0** | Add JWT verification to `send-message-push` and `send-notification-push` Edge Functions | T4.4 | Low | ❌ Missing auth validation |
| **P0** | Add input validation and sanitization to all Edge Functions | T4.1, T4.4 | Medium | ⚠️ Partial validation |
| **P0** | Add payload size limits (10KB max) to Edge Functions | T6.2 | Low | ❌ No size limits |
| **P1** | Implement rate limiting on Edge Functions (per user, per minute) | T6.2 | Medium | ❌ No rate limiting |
| **P1** | Add file type validation + size limits on all uploads | T4.5 | Medium | ⚠️ Storage config has limits |
| **P2** | Implement Content Security Policy headers in admin portal | T4.2 | Low | ❌ Not configured |

### 5.4 Payment Security

| Priority | Safeguard | Addresses Threats | Implementation Effort | Status |
|----------|-----------|-------------------|----------------------|--------|
| **P0** | Verify PayMongo webhook signature on every incoming call | T5.4 | Low | ⚠️ Code exists; verify live |
| **P0** | Implement idempotency keys for payment intents | T5.2 | Medium | ❌ Not implemented |
| **P1** | Add server-side order amount validation before payment processing | T5.1 | Medium | ⚠️ Partial (DB constraints) |
| **P1** | Log all payment state transitions for audit trail | T10.1 | Medium | ❌ No payment audit log |
| **P2** | Implement payment reconciliation (match orders to payments daily) | T5.1, T5.5 | High | ❌ Not implemented |

### 5.5 Infrastructure & Availability

| Priority | Safeguard | Addresses Threats | Implementation Effort | Status |
|----------|-----------|-------------------|----------------------|--------|
| **P0** | Upgrade Supabase to paid plan (enables daily backups, higher limits) | T6.5, T8.1 | Cost: $25/mo | ❌ Currently free tier |
| **P0** | Verify database backups are enabled and test restore procedure | T10.3 | Low (manual verification) | ⚠️ Pending verification |
| **P1** | Implement graceful degradation (offline mode for core features) | T8.1 | High | ⚠️ Partial offline support |
| **P1** | Set up monitoring/alerting (Sentry for errors, UptimeRobot for availability) | T10.1, T10.3 | Low-Medium | ❌ Not implemented |
| **P2** | Document and test disaster recovery procedure | T10.3 | Medium | ❌ Not documented |

### 5.6 Mobile App Security

| Priority | Safeguard | Addresses Threats | Implementation Effort | Status |
|----------|-----------|-------------------|----------------------|--------|
| **P1** | Enable code obfuscation (`--obfuscate` flag in release builds) | T7.5 | Low (build config) | ❌ Not configured |
| **P1** | Implement certificate pinning for Supabase API calls | T7.3 | Medium | ❌ Not implemented |
| **P1** | Detect rooted/jailbroken devices and warn/block | T7.2 | Medium (package) | ❌ Not implemented |
| **P2** | Implement secure screen capture prevention for sensitive screens | T7.4 | Medium | ❌ Not implemented |
| **P2** | Clear sensitive data from memory after use | T7.1 | High | ❌ Not implemented |

### 5.7 Monitoring & Incident Response

| Priority | Safeguard | Addresses Threats | Implementation Effort | Status |
|----------|-----------|-------------------|----------------------|--------|
| **P0** | Implement application-level audit logging (who, what, when) | T10.1 | Medium | ❌ Only Supabase auth logs |
| **P0** | Create incident response plan document | T10.2 | Low (documentation) | ❌ Not documented |
| **P1** | Set up automated security scanning (Dependabot, Snyk) | T10.5 | Low | ❌ Not configured |
| **P1** | Implement security event alerting (failed logins, role changes) | T1.5, T10.1 | Medium | ❌ Not implemented |
| **P2** | Schedule quarterly security reviews | T10.4 | Low (process) | ❌ Not scheduled |

### 5.8 Git & Credential Management

| Priority | Safeguard | Addresses Threats | Implementation Effort | Status |
|----------|-----------|-------------------|----------------------|--------|
| **P0** | Rotate Supabase anon key (exposed in git history) | T3.3 | Low (Supabase dashboard) | ❌ Not rotated |
| **P0** | Move all secrets to environment variables (dart_defines.json) | T3.2, T3.3 | Medium | ⚠️ Partial (some in constants) |
| **P1** | Use BFG to clean credentials from git history | T3.3 | Medium (one-time) | ❌ Not done |
| **P1** | Add pre-commit hooks to detect secret commits | T3.3 | Low | ❌ Not implemented |
| **P2** | Implement secrets rotation schedule (quarterly) | T3.3 | Low (process) | ❌ Not implemented |

---

## 6. Implementation Roadmap

### Phase 1: Critical (Week 1-2)
- [ ] Enable MFA for admin accounts
- [ ] Enforce stronger password requirements
- [ ] Add JWT verification to Edge Functions
- [ ] Verify and test database backups
- [ ] Rotate exposed Supabase anon key
- [ ] Add admin portal server-side role check
- [ ] Restrict profiles SELECT to exclude emails

### Phase 2: High Priority (Week 3-4)
- [ ] Implement audit logging
- [ ] Add rate limiting to Edge Functions
- [ ] Implement data deletion endpoint
- [ ] Add privacy consent mechanism
- [ ] Enable code obfuscation
- [ ] Set up error monitoring (Sentry)
- [ ] Create incident response plan

### Phase 3: Medium Priority (Month 2)
- [ ] Implement certificate pinning
- [ ] Add account lockout mechanism
- [ ] Implement idempotency keys for payments
- [ ] Add payment reconciliation
- [ ] Enable automated dependency scanning
- [ ] Document data processing activities

### Phase 4: Low Priority (Month 3+)
- [ ] Implement certificate pinning
- [ ] Add rooted device detection
- [ ] Implement secure screen capture prevention
- [ ] Schedule quarterly security reviews
- [ ] Conduct penetration testing
- [ ] Document disaster recovery procedures

---

*SoleVision Security Analysis — Prepared for Capstone Documentation*
