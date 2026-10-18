# 📖 Glossary

> Project-specific terms, in one place. If a code comment uses a word that only makes sense here, it belongs below. **#project/solevision**

---

| Term | Meaning |
|------|---------|
| LIVE / COAST / LOST | `DetectionDots.holdState` verdicts: current measurement / held fix while the foot is still seen / gone. Shared by dots and detection-placed shoe. |
| Streak acceptance | `FootSnapshot` captures only after 5 consecutive samples agree within 8° yaw and 10 mm length — also catches heel/toe label flips. |
| TEMP-DIAG | Temporary on-device diagnostic logging (e.g. `dots-probe`). Never ships; the release checklist greps for it. |
| Ubershader abort (F16) | Process abort from a Filament material/mesh mismatch — the reason indicators are overlay views, not geometry. |
| Defer-until-paid | Online GCash holds no stock; the webhook materializes `order_items` only after verified payment. |
| Step-up | New-device email-code challenge; MFA accounts skip it. Enforced by RLS policies, shipped OFF. |
| One-pending cap | Partial unique `customer_id WHERE status='pending'` on `payment_intents` — one unfinished GCash checkout per customer (409 otherwise). |
| Dual sync | `product_variants` ↔ `inventory` kept in agreement from opposite directions depending on the writer. |
| Model B | GCash fee surcharged to the customer as its own disclosed line item. |
| Attempt #6 | The hosted-checkout PayMongo flow (current); #5 is the dormant QR+proof flow kept for legacy orders. |
| Foot-profile source | `ar_scan` > `manual` > `skipped`/NULL — decides whether the home reminder banner shows. |
