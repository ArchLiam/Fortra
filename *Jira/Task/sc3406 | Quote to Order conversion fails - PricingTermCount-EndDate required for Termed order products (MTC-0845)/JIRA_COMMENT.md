# SC-3406 — Jira comment (high-visibility)

> **Paste tips for Jira Cloud:** markdown (headings, **bold**, tables, > quotes, emoji) auto-formats on paste. For the colored boxes, put your cursor on the quoted line and type `/panel` → pick **Success** (green) for the top banner and **Warning** (yellow) for the AUD section. Tag people with `@`.

---

@Andy Kumar

> ✅ **SC-3406 — RESOLVED in UAT.** The "Order Creation Failed → *PricingTermCount / EndDate is required for Termed order products*" error on **Convert Quote to Order** is **fixed and verified live** on your exact AUD repro quote.

---

### 🔎 Root cause (one line)
The termed quote lines carried **null `PricingTermCount`** (and the Hardware line, null `EndDate`) into the order, and Revenue Cloud blocks activation of a termed line missing those fields. `PricingTermCount` is **platform read-only on the quote** — only the pricing engine writes it — and that derivation regressed in the **11-Jun pricing-procedure change**. *(The convert flow itself had no bug; AUD / the "COLA Renewal" name are incidental — Quote_Type = New.)*

### 🔧 What fixed it
The **`Fortra_OrderItem_Set_Dates` V6** backstop (deployed **15-Jun 19:04 UTC**, *after* your 12-Jun report) auto-stamps `PricingTermCount = 1` + `EndDate` on blank termed order lines during convert — and self-heals older lines on **Reprice All**.

### ✅ Verified by live re-convert (15-Jun)

| Test | Result |
|---|---|
| **Re-convert** repro quote `0Q0WC0000038PHF0A2` → Order **00095514** (AUD) | ✅ **Converted clean — no error.** Both lines stamped: ACTIDB `PTC=1`, **Hardware `PTC=1` / `EndDate` auto-set 13-Jun-2027** |
| Older pre-fix order **00095497** → **Reprice All** | ✅ Term fields **self-healed** (`PTC` null → 1) |

➡️ The `REQUIRED_FIELD_MISSING … Termed order products` error **no longer occurs.**

---

> ⚠️ **Heads-up — a *separate* issue blocks AUD orders from activating (NOT this ticket).**
>
> After the term fields are fixed, AUD orders fail at activation with a **different** error — `Order Submission to Revenue Orchestrator … "Sales Transaction cannot be processed at this time"` (the AUD reprice returns *CompletedWithoutPricing*).
> This is a **persistent, currency-specific** problem: **0 AUD orders have *ever* reached Order Complete**, while **USD completes normally**. → belongs to the **multi-currency pricing** work (**SC-3384**), independent of the term-field fix.

---

### 📌 Disposition
- [x] **SC-3406 term-field defect → FIXED** (verified end-to-end up to activation on the AUD repro)
- [ ] **Link:** *is caused by* **SC-3415** (quote-tier read-only `PricingTermCount` derivation — durable cure) · *fixed by* **SC-3411** V6
- [ ] **Route the AUD activation blocker → SC-3384** (or new ticket) — multi-currency pricing/orchestration, not term fields
- [ ] **Prod rollout pending:** FortraProd has **none** of the backstop flows → prod is still exposed until SC-3411 V6 + V14 ship

### 🔒 Scope
**UAT only.** Order **00095514** left in **Draft** (term fields stamped, priced) — it will activate once the AUD orchestrator/pricing issue (SC-3384) is resolved.

---
*RCA + full evidence in the SC-3406 dossier. Verification: live UAT re-convert, 15-Jun-2026.*
