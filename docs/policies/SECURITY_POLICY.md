# SoleVision Information Security Policy

## Purpose
This policy establishes mandatory security rules to protect SoleVision's information assets — including customer data, seller data, financial records, authentication credentials, and proprietary business logic — from unauthorized access, disclosure, modification, destruction, and disruption. It ensures compliance with data protection principles and maintains trust in the platform for artisans, customers, and administrators.

## Scope
This policy applies to:
- **All personnel**: Developers, contractors, administrators, and third-party vendors with access to SoleVision systems
- **All environments**: Production, staging, development, and local development machines
- **All systems**: Flutter mobile app, React admin portal, Supabase backend (PostgreSQL, Auth, Storage), GitHub repositories, CI/CD pipelines
- **All data**: Personally identifiable information (PII), payment data, order records, inventory data, authentication tokens, API keys

## Policy Statements

### 1. Authentication & Access Control
- **Multi-factor authentication (MFA)** is required for all administrative access to Supabase Dashboard, GitHub, and CI/CD systems.
- **Role-based access control (RBAC)** enforced via Supabase RLS policies — all database access governed by `role` (customer/seller/admin) and ownership (`auth.uid()` checks).
- **Service accounts** use least-privilege Supabase anon keys; service-role keys are prohibited in client-side code.
- **Session management**: JWT tokens auto-refreshed by Supabase; forced sign-out on role change or security events.

### 2. Data Protection
- **Encryption in transit**: All API communication via HTTPS/TLS 1.2+ (Supabase enforces).
- **Encryption at rest**: Supabase-managed (PostgreSQL TDE, Storage encryption).
- **Secrets management**: No credentials in source code. Supabase URL/anon key in `app_constants.dart` (legacy — must migrate to env vars). Admin portal uses `.env` with `VITE_` prefix.
- **PII minimization**: Collect only required data (name, email, phone, address). No government IDs, full card numbers, or biometric templates stored.
- **Biometric credentials**: Stored exclusively in `FlutterSecureStorage` (encrypted keystore/Keychain); never transmitted to backend.

### 3. Database Security
- **Row Level Security (RLS) enabled on ALL tables** — no exceptions. Policies reviewed quarterly.
- **Triggers with `SECURITY DEFINER`** for any function that performs WRITE operations (e.g., inventory decrement triggers).
- **FK delete rules immutable**: `SET NULL` on order/sales history tables to preserve audit trails; `CASCADE` on dependent data only.
- **No direct SQL in production**: All schema changes via versioned Supabase migrations.

### 4. Secure Development Practices
- **Code review required** for all changes to `main` branch — security checklist includes RLS verification, trigger safety, input validation.
- **Dependency scanning**: `flutter pub outdated` and `npm audit` run in CI; critical vulnerabilities blocked from merge.
- **Input validation**: All user inputs validated client-side (UI) and server-side (RLS + Postgres constraints). No raw SQL interpolation.
- **Error handling**: Generic user-facing messages; detailed errors logged server-side only (no stack traces in UI).

### 5. Incident Response & Monitoring
- **Security incidents** (unauthorized access, data exposure, credential compromise) reported immediately to project lead.
- **Audit logging**: Supabase Auth logs, Postgres `pgaudit` (if enabled), GitHub audit log reviewed monthly.
- **Breach notification**: Affected users notified within 72 hours per privacy best practices; regulatory reporting if applicable.
- **Backup & recovery**: Daily Supabase backups; point-in-time recovery tested quarterly.

## Responsibilities

| Role | Responsibilities |
|------|------------------|
| **Project Lead / Security Owner** | Policy enforcement, incident coordination, quarterly policy review, vendor risk assessment |
| **Developers** | Follow secure coding practices, run dependency scans, no secrets in commits, validate RLS on new tables |
| **DevOps / CI Maintainers** | Secure pipeline secrets, enforce branch protection, automate security checks, manage deployment keys |
| **Database Admin (Supabase)** | RLS policy maintenance, trigger security (`SECURITY DEFINER`), backup verification, access reviews |
| **All Personnel** | Report security concerns immediately, use MFA, lock devices, no credential sharing, complete security training |

## Enforcement

Violations of this policy may result in:

- **Immediate access revocation** (Supabase, GitHub, CI/CD, devices)
- **Code revert** and mandatory security remediation before re-merge
- **Disciplinary action** per organizational policy (contractor termination, employee review)
- **Legal consequences** for willful negligence causing data breaches or regulatory violations
- **Mandatory re-training** and supervised period for repeat offenses

---

**Effective Date:** September 9, 2026  
**Next Review:** December 9, 2026  
**Owner:** Project Lead  
**Classification:** Internal — Confidential