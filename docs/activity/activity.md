# CAPSTONE-BASED THREAT MODELING ACTIVITY "SOLEVISION: AN AR-POWERED FOOTWEAR MARKETPLACE"

**Submitted to:**
MR. RUMSIE DEGUITOS

**Submitted by:**
SOLEVISION DEVELOPMENT TEAM

---

## System Description

**SOLEVISION: An AR-Powered Footwear Marketplace** is a cross-platform mobile application and web admin portal developed to connect local artisan shoemakers directly with customers, featuring augmented reality (AR) foot measurement to help buyers find the perfect fit before ordering. The system integrates AI-assisted foot scanning, real-time messaging, and digital payment processing to modernize the local footwear industry while maintaining secure and centralized records management.

### Who will use the system?

The system is intended for **customers** (end users who browse, purchase, and review artisan footwear), **sellers** (local artisan shoemakers and store owners who list products, manage inventory, and fulfill orders), and **administrators** (platform operators who oversee seller applications, manage users, and monitor transactions). These users will utilize the system according to their respective roles and responsibilities in the footwear marketplace ecosystem.

### What are its major functions?

The system provides functions for **AR foot measurement** (guided wall-calibration scan using ML Kit), **product browsing and search** (masonry catalog with categories and tags), **shopping and checkout** (cart management, address book, GCash payment), **order management** (status tracking, cancellation, purchase history), **real-time messaging** (buyer-seller chat with push notifications), **seller dashboard** (product CRUD, POS with barcode scanner, sales analytics, store management), **seller verification** (multi-tier identity and business document verification), **admin portal** (user management, seller approval, product oversight, analytics), and **in-app updates** (self-hosted APK distribution).

### What devices, applications, databases, networks, or external services does it use?

SOLEVISION operates using **Android and iOS smartphones** (Flutter cross-platform), **web browsers** (admin portal built with Vue.js and Vite), and **Supabase cloud infrastructure** (PostgreSQL database, authentication, file storage, edge functions, and realtime subscriptions). The system uses **Firebase Cloud Messaging** for push notifications, **Google ML Kit** for on-device AR foot measurement (pose detection, selfie segmentation), **MapTiler** for map tiles and geocoding, **GCash/PayMongo** for digital payment processing, and **GitHub Releases** for self-hosted APK distribution. It operates over **HTTPS/REST** APIs and **WebSocket** connections for real-time features.

### What types of information does it collect, process, store, or transmit?

The system collects and processes **user identity information** (email, password, name, phone, profile photo, role), **personal profile data** (gender, birthday, bio, delivery addresses), **AR foot measurement data** (foot length, width, arch height), **product catalog data** (names, descriptions, prices, images, stock levels), **transaction records** (orders, payments, cancellations), **communication data** (real-time chat messages), and **verification documents** (government-issued IDs, selfies, business registration papers). Since these records contain sensitive personal, biometric, and financial information, the system incorporates **authentication, role-based access control (RLS), audit trails, encrypted storage, and secure database protection**.

---

## CAPSTONE SYSTEM DIAGRAM

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        CAPSTONE SYSTEM DIAGRAM                         │
└─────────────────────────────────────────────────────────────────────────┘

                    ┌──────────────────────────────────┐
                    │       AUTHORIZED PERSONNEL        │
                    │  ┌───────────┐ ┌──────────────┐  │
                    │  │ Customers │ │ Sellers      │  │
                    │  │ (End User)│ │ (Artisan     │  │
                    │  │           │ │  Shoemakers) │  │
                    │  └─────┬─────┘ └──────┬───────┘  │
                    │  ┌─────┴─────┐ ┌──────┴───────┐  │
                    │  │ Admin     │ │ System       │  │
                    │  │ Staff     │ │ Admin        │  │
                    │  └─────┬─────┘ └──────┬───────┘  │
                    └────────┼──────────────┼──────────┘
                             │              │
              ┌──────────────┴──────────────┴──────────────┐
              │           SOLEVISION MOBILE APP             │
              │  ┌─────────────────────────────────────┐   │
              │  │  Login & Authentication              │   │
              │  │  AR Foot Measurement & Scanning      │   │
              │  │  Product Browsing & Search           │   │
              │  │  Shopping Cart & Checkout            │   │
              │  │  Order Management & Tracking         │   │
              │  │  Real-Time Messaging & Chat          │   │
              │  │  Seller Dashboard & POS              │   │
              │  │  User Profile & Settings             │   │
              │  └─────────────────────────────────────┘   │
              └──────────────────┬──────────────────────────┘
                                 │
              ┌──────────────────┴──────────────────────────┐
              │           ADMIN PORTAL (Web)                 │
              │  ┌─────────────────────────────────────┐   │
              │  │  User Management                     │   │
              │  │  Seller Application Review           │   │
              │  │  Product Catalog Oversight            │   │
              │  │  Order & Transaction Monitoring       │   │
              │  │  Analytics Dashboard                  │   │
              │  └─────────────────────────────────────┘   │
              └──────────────────┬──────────────────────────┘
                                 │
              ┌──────────────────┴──────────────────────────┐
              │           SUPABASE BACKEND                   │
              │  ┌─────────────┐  ┌──────────────────┐     │
              │  │ PostgreSQL  │  │ Supabase Auth     │     │
              │  │ Database    │  │ (JWT + RLS)       │     │
              │  └──────┬──────┘  └────────┬─────────┘     │
              │  ┌──────┴──────┐  ┌────────┴─────────┐     │
              │  │ Realtime    │  │ Edge Functions    │     │
              │  │ (WebSocket) │  │ (Push/Payments)   │     │
              │  └──────┬──────┘  └────────┬─────────┘     │
              │  ┌──────┴──────┐  ┌────────┴─────────┐     │
              │  │ File        │  │ Storage Bucket    │     │
              │  │ Storage     │  │ (Private/Public)  │     │
              │  └──────┬──────┘  └────────┬─────────┘     │
              └─────────┼──────────────────┼────────────────┘
                        │                  │
              ┌─────────┴──────────────────┴────────────────┐
              │           EXTERNAL SERVICES                   │
              │  ┌──────────┐ ┌──────────┐ ┌────────────┐  │
              │  │ Firebase │ │ MapTiler │ │ GCash/     │  │
              │  │ FCM      │ │ (Maps)   │ │ PayMongo   │  │
              │  └──────────┘ └──────────┘ └────────────┘  │
              │  ┌──────────┐ ┌──────────┐ ┌────────────┐  │
              │  │ Google   │ │ GitHub   │ │ Unsplash   │  │
              │  │ ML Kit   │ │ Releases │ │ (Images)   │  │
              │  └──────────┘ └──────────┘ └────────────┘  │
              └─────────────────────────────────────────────┘

SUPPORTING INFRASTRUCTURE:
• Supabase Cloud Hosting (Database, Auth, Storage, Edge Functions)
• Firebase Cloud Infrastructure (Push Notifications)
• HTTPS/REST API Communication
• WebSocket Realtime Connections
• User Mobile Devices (Android/iOS)
• Desktop Computers / Web Browsers (Admin Portal)
• Internet Connection
• Backup Storage (Supabase Managed + GitHub)
```

---

## ASSET / DEPENDENCY MAP

| ASSET | DEPENDENCY | PURPOSE / RELATIONSHIP |
|-------|------------|------------------------|
| **User Accounts & Credentials** | Supabase Auth, Database | Controls who can access the system and what they can do. Stores email, password (hashed), role assignments. |
| **Customer Profiles (PII)** | Database, RLS Policies | Stores personal information (name, phone, gender, birthday, bio) with role-based access control. |
| **Delivery Addresses** | Database, RLS Policies | Stores customer shipping addresses with location coordinates for order delivery. |
| **AR Foot Measurements** | Database, ML Kit, Camera | Stores foot length, width, arch height data captured via on-device AR scanning. |
| **Product Catalog** | Database, Storage, RLS | Stores product names, descriptions, prices, images, stock levels, and categories. |
| **Order & Transaction Records** | Database, GCash/PayMongo, RLS | Stores purchase records, payment status, order lifecycle, and cancellation data. |
| **Seller Store Profiles** | Database, Storage, RLS | Stores store names, logos, descriptions, locations, schedules, and brand customization. |
| **Real-Time Chat Messages** | Database, Realtime WebSocket | Stores buyer-seller conversation threads with real-time delivery. |
| **Verification Documents (IDs)** | Storage (Private Bucket), RLS | Stores government-issued ID photos, selfies, and business registration documents. |
| **Audit Logs** | Database, Supabase Auth | Records user activities, authentication events, and system changes for accountability. |
| **Backup Data** | Supabase Managed Backups, GitHub | Provides recovery capability in case of data loss or system failure. |
| **Push Notification Tokens** | Firebase FCM, Database | Links user devices for targeted push notification delivery. |
| **SOLEVISION Mobile App** | Flutter, Supabase SDK, ML Kit | Provides the main customer and seller interface with all marketplace functions. |
| **Admin Portal (Web)** | Vue.js, Vite, Supabase JS | Provides the administrator interface for user management and platform oversight. |
| **Supabase Backend** | PostgreSQL, Edge Functions, Auth | Hosts the database, authentication, storage, and serverless compute. |
| **Firebase Cloud Messaging** | Google Cloud Infrastructure | Delivers push notifications to customer and seller mobile devices. |
| **GCash/PayMongo** | Payment Gateway API | Processes digital wallet payments for customer orders. |
| **MapTiler** | Map Tile Service | Provides map tiles for store location display and AR calibration. |
| **Google ML Kit** | On-Device ML Processing | Performs pose detection, selfie segmentation for AR foot measurement. |
| **GitHub Releases** | GitHub Cloud | Distributes APK binaries for in-app update mechanism. |

---

## THREAT LIST

| THREAT | AFFECTED ASSET | RISK LEVEL |
|--------|----------------|------------|
| **Unauthorized Access** — Unauthorized users gaining access to customer, seller, or admin accounts | User Accounts, Customer PII, Orders, Verification Docs | **High** |
| **Credential Theft / Weak Passwords** — Stolen or weak passwords allowing account compromise | User Accounts, All Data | **High** |
| **Missing Multi-Factor Authentication** — No MFA enabled for any user role | All Accounts | **High** |
| **Excessive User Privileges** — Users with more permissions than needed for their role | Database, All Records | **High** |
| **RLS Policy Bypass / IDOR** — Exploiting Row Level Security gaps to access unauthorized data | All RLS-Protected Tables | **High** |
| **SQL Injection / Input Validation** — Malicious input manipulating database queries | Database, All Tables | **High** |
| **Insider Misuse** — Authorized personnel intentionally or accidentally misusing access | Customer PII, Orders, Messages | **High** |
| **Cross-Seller Data Access** — Seller A accessing Seller B's products or orders | Products, Orders, Sales Data | **High** |
| **Edge Function Abuse** — Unauthenticated access to push notification/payment functions | Push Notifications, Payments | **High** |
| **Payment Tampering** — Modifying order amounts during checkout | Order Totals, Payment Records | **Medium–High** |
| **Webhook Forgery** — Fake PayMongo webhook calls confirming unpaid orders | Payment Status, Orders | **High** |
| **PII Leakage via Public Profiles** — Profile SELECT exposing email addresses to all users | Customer Emails, Phone Numbers | **High** |
| **Verification Document Exposure** — Private ID documents becoming publicly accessible | Government IDs, Selfies | **Critical** |
| **Git History Credential Exposure** — Hardcoded Supabase keys in version control | API Keys, System Access | **Medium–High** |
| **Malware / Ransomware** — Malware compromising the Supabase cloud or user devices | All Data, System Availability | **High** |
| **Network Interception (MITM)** — Intercepting HTTPS traffic on compromised networks | API Communications, Tokens | **Medium–High** |
| **Supabase Cloud Outage** — Provider infrastructure failure making system unavailable | All Services, System Availability | **High** |
| **Firebase Cloud Messaging Compromise** — FCM credentials leaked | Push Notification Delivery | **Medium–High** |
| **Device Theft** — Physical access to unlocked device exposing app data | Local Storage, Sessions | **Medium–High** |
| **Accidental Data Deletion** — Users accidentally deleting orders, addresses, or products | Orders, Addresses, Products | **Medium–High** |
| **Incorrect AI-Generated Foot Measurements** — AR scan producing inaccurate foot data | Foot Measurements, Size Recommendations | **Medium–High** |
| **Incorrect User Input** — Incomplete or incorrect data entry in forms | All User-Submitted Data | **Medium–High** |
| **Database Failure** — Centralized database becoming unavailable | All Records, System Availability | **High** |
| **Hardware Failure** — User device or server hardware malfunction | System Availability | **Medium–High** |
| **Power Interruption** — Power failure affecting service availability | System Availability | **Medium–High** |
| **Backup Failure** — Loss of backup data preventing recovery | All Data, Recovery Capability | **Critical** |
| **Printer / Report Failure** — Inability to export or print order receipts | Order Receipts, Reports | **Medium** |
| **Free Tier Resource Exhaustion** — Hitting Supabase free tier limits (500MB, 50K MAU) | System Availability, All Data | **High** |
| **Dependency Vulnerabilities** — Known CVEs in Flutter/Dart packages | App Security, All Data | **Medium–High** |
| **No Audit Logging** — Inability to track user actions for forensics | Forensics, Compliance | **High** |
| **GDPR / Philippine DPA Violation** — Processing personal data without proper consent | All PII, Compliance | **High** |
| **Realtime Connection Flooding** — Exhausting WebSocket connections | Messaging, System Availability | **Medium–High** |
| **Storage Exhaustion** — Uploading excessive files filling storage quota | Storage, System Availability | **Medium–High** |

---

## RISK RATIONALE

The major risks identified in the Threat Model are important because **SOLEVISION handles sensitive personal, biometric, financial, and identity verification information** while operating a real-time marketplace that processes payments and stores government-issued identification documents.

### Unauthorized Access
Unauthorized access could expose confidential customer personal information (names, addresses, phone numbers), financial data (payment references, order history), and critically sensitive verification documents (government-issued IDs, selfies). This could compromise user privacy, enable identity theft, and violate the Philippine Data Privacy Act.

### Credential Theft / Weak Passwords
A stolen or compromised account could allow an unauthorized person to access customer records, place fraudulent orders, view private chat messages, or — if the compromised account is a seller — access other sellers' business information and financial data. Admin account compromise could grant full system control.

### Missing Multi-Factor Authentication
Without MFA, all user accounts (including administrators with full system access) are protected only by a password. This significantly increases the risk of account takeover through credential theft, phishing, or brute force attacks.

### Excessive User Privileges
Users with unnecessary permissions may view, modify, or delete records outside their responsibilities. For example, a customer accessing seller financial data, or a seller accessing another seller's product inventory, could lead to data breaches and competitive harm.

### RLS Policy Bypass / IDOR
Row Level Security (RLS) is the primary defense against cross-user data access. Policy gaps or misconfigurations could allow customers to read other customers' orders, sellers to modify competitors' products, or anonymous users to access private data.

### SQL Injection / Input Validation
Weak input validation in search fields, product names, review text, or Edge Function parameters could allow malicious users to manipulate database queries and potentially access, modify, or delete stored information.

### Insider Misuse
Authorized personnel (sellers, admins) could intentionally or accidentally misuse access to confidential customer records, financial data, or verification documents for purposes outside their legitimate business needs.

### Cross-Seller Data Access
The original RLS policies allowed any seller to modify products in any store. Although fixed in migration `20260712`, verification on the live database is required to confirm the fix is applied.

### Edge Function Abuse
The `send-message-push` and `send-notification-push` Edge Functions lack JWT verification, rate limiting, and payload size limits. Anyone with the function URL could spam notifications or abuse the service quota.

### Payment Tampering / Webhook Forgery
Modifying order amounts during checkout or sending fake webhook callbacks could allow unauthorized order confirmations, financial fraud, or order status manipulation.

### PII Leakage via Public Profiles
The `profiles` table has a public SELECT policy (`USING (true)`) that exposes all columns including email addresses to any user, including unauthenticated visitors.

### Verification Document Exposure
Government-issued ID photos, selfies, and business registration documents are stored in a private Supabase Storage bucket. A policy misconfiguration could expose these highly sensitive documents publicly, leading to identity theft.

### Git History Credential Exposure
The Supabase URL and anon key are hardcoded in `lib/constants/app_constants.dart` and committed to git history. While the anon key is designed for client-side use, its presence in version control represents a credential management weakness.

### Malware / Ransomware
Malware could compromise user devices or the Supabase cloud infrastructure, causing data loss, corruption, or system downtime. Ransomware could encrypt database records making them inaccessible.

### Network Interception (MITM)
Although HTTPS is enforced, the absence of certificate pinning means a sophisticated attacker with a compromised Certificate Authority could intercept API communications and steal authentication tokens.

### Supabase Cloud Outage
The entire system depends on Supabase as a single cloud provider. An outage would make all features unavailable — product browsing, ordering, messaging, and payments — with no fallback.

### Device Theft
Physical access to an unlocked device could expose locally stored authentication tokens, cached data, cart contents, and recently viewed products. Biometric authentication is optional, not enforced.

### Accidental Data Deletion
Users could accidentally delete orders, addresses, or products without confirmation controls. There is no soft-delete or trash mechanism for most entities.

### Incorrect AI-Generated Foot Measurements
The AR foot measurement system uses ML Kit on-device processing. Inaccurate measurements could lead to incorrect size recommendations, resulting in ill-fitting footwear, customer dissatisfaction, and returns.

### Database Failure
Because the system relies on a centralized PostgreSQL database hosted on Supabase, database failure could make all records unavailable and interrupt all marketplace operations.

### Backup Failure
Without verified, regularly tested backups, permanent data loss could occur from database corruption, accidental deletion, or provider issues. Supabase's backup status requires manual verification.

### No Audit Logging
The system lacks application-level audit logging. Only Supabase's built-in auth logs exist. This makes it impossible to track who modified products, approved sellers, or accessed sensitive data.

### GDPR / Philippine DPA Violation
The system processes personal data of Philippine citizens without documented privacy consent mechanisms, data retention policies, or right-to-erasure procedures, potentially violating the Philippine Data Privacy Act of 2012.

---

## THREAT MODEL

| ASSET | THREAT ACTOR | VECTOR | VULNERABILITY | RISK RATIONALE | SAFEGUARD |
|-------|--------------|--------|---------------|----------------|-----------|
| **Customer Profiles (PII)** | Unauthorized user / Insider | Stolen credentials or unauthorized access | Weak access controls, public profile SELECT | Confidential personal information (email, phone, address) may be exposed, enabling identity theft | Role-Based Access Control (RLS), strong authentication, restrict public profile columns |
| **User Accounts** | External attacker | Brute-force or credential theft | Weak passwords, no MFA, no account lockout | A compromised account can allow unauthorized access to all user data and marketplace functions | Strong password policy, MFA, account lockout, secure session management |
| **SOLEVISION Mobile App** | Cyber attacker | SQL injection / malicious input | Insufficient input validation, Edge Function gaps | Attackers may access, modify, or delete database information through unvalidated inputs | Input validation, parameterized queries, Edge Function JWT verification |
| **Order & Transaction Records** | Insider / Cyber attacker | Unauthorized database access | Excessive privileges, weak RLS enforcement | Unauthorized modification could compromise financial records and order integrity | Least-privilege RLS, database access controls, audit logging |
| **Verification Documents** | Unauthorized user / Insider | Stolen credentials or storage policy error | Private bucket misconfiguration, no access monitoring | Government IDs and selfies could be exposed leading to identity theft | Private storage bucket, owner-only RLS, admin access logging, regular policy audits |
| **AR Foot Measurements** | Insider / Accidental user | Manipulated or incorrect input | Lack of human verification for accuracy | Incorrect foot measurements lead to wrong size recommendations and customer dissatisfaction | Manual fallback entry, measurement confidence scoring, customer confirmation step |
| **Payment Records** | Cyber attacker | Payment tampering / webhook forgery | No idempotency keys, incomplete webhook signature verification | Financial fraud through amount manipulation or fake payment confirmations | Server-side amount validation, webhook signature verification, idempotency keys |
| **Real-Time Messages** | Insider / Cyber attacker | Unauthorized message access | Conversation RLS gaps, missing message encryption | Private buyer-seller conversations could be exposed to unauthorized parties | Conversation participant RLS, message-level access control, content moderation |
| **Supabase Backend** | Malware attacker / Insider | Malware, ransomware, or unauthorized access | Unpatched dependencies, no monitoring | Server compromise may cause system downtime or loss of all marketplace data | Supabase managed security, automated updates, error monitoring (Sentry) |
| **Network Communications** | Network attacker | Network interception or unauthorized connection | No certificate pinning, HTTPS-only | Sensitive data transmitted across the network may be intercepted on compromised networks | HTTPS enforcement, certificate pinning, network security configuration |
| **User Devices** | Malware attacker / Unauthorized user | Malware, phishing, or unauthorized physical access | Optional biometric auth, no root detection | Compromised devices can expose local tokens, cached data, and session information | Biometric auth enforcement, root detection, secure local storage, session timeout |
| **Audit Logs** | Insider / Attacker | Log deletion or manipulation | No application-level audit logging, insufficient log protection | Loss or alteration of logs makes suspicious activities difficult to trace and investigate | Application-level audit logging, protected audit storage, regular log monitoring |
| **Backup Storage** | Malware attacker / Insider | Backup deletion, corruption, or inadequate protection | Unverified backup status, no restoration testing | Without usable backups, system failure or data loss could be permanent | Verified automated backups, multiple backup copies, regular restoration testing |
| **System Availability** | Unauthorized person | Power failure / hardware failure / provider outage | Single cloud provider, no disaster recovery plan | System downtime may prevent all users from accessing the marketplace | Supabase SLA, disaster recovery procedures, offline mode, monitoring/alerting |
| **Report Output / Receipts** | Unauthorized person | Physical access to printed/exported reports | No document access control | Confidential order receipts could be viewed or taken by unauthorized individuals | Secure export, access-controlled downloads, document expiration |
| **Push Notifications** | Malicious user | Edge Function abuse, FCM token theft | No JWT verification on push functions, no rate limiting | Spam notifications or unauthorized access to notification delivery system | JWT verification, rate limiting, payload size limits, token validation |
| **Admin Portal** | Unauthorized user | Unauthorized admin access | Client-side role check only, no server-side admin verification | Non-admin users could gain access to user management and platform controls | Server-side admin role verification, secure admin authentication, audit trail |

---

*SOLEVISION — Empowering local Filipino artisans with modern technology to reach more customers and deliver perfectly-fitted footwear.*

*Generated with Codebuff 🤖*
*Co-Authored-By: Codebuff <noreply@codebuff.com>*
