# SC-3346 — Renewal-Maintenance Pricing: Root Cause & Fix

**Executive Report · Revenue Cloud Advanced / RLM · FortraUAT · 2026-06-14**

Product in scope: **Powertech IAM (BoKS)** — `PIA-PIA-RNM-PIAMBK`, the Fortra-sanctioned DPP product.
Related tickets: **SC-3346** (Maintenance Derived/COLA Renewal Pricing build) · **SC-3404** (renewal-maintenance `$0 NetUnitPrice` investigation).

---

## Verdict

**FIXED.** The root cause is identified, the fix is built, deployed to UAT, unit-tested (4/4), and proven end-to-end: a maintenance renewal now commits the correct COLA net **$67.38** instead of the frozen **$60.64 / $0**. One Setup-UI toggle (disable the Year-2 AutoAdd rule) remains, owner-side, to switch it on in production.

| Metric | Value |
|---|---|
| NetUnitPrice now committed | **$67.38** (was $60.64 fossil / $0) |
| Components deployed | **2** (1 Apex class + 1 Flow wiring) |
| Unit tests | **4 / 4 pass** |
| Dead-end levers ruled out | **6+** |
| Remaining to activate in prod | **1 Setup-UI step** |

---

## 1. The defect — in business terms

When a customer renews their maintenance, the renewal line priced at the **wrong amount** — a stale **$60.64** (or **$0**) instead of the correct cost-of-living-adjusted renewal of **$67.38**.

The COLA math itself was never wrong: $67.38 = last year's net **$62.48 × 1.0785** (7.85% COLA uplift). The problem was that the calculated value **never committed to the line**. Several prior remediation attempts failed because every one of them tried to *write the price* at reprice time — the wrong layer entirely.

---

## 2. Root cause — a selling-model mismatch

Found by running the real `initiateRenewal` end-to-end with FINEST debug logging and tracing the QuoteAction the platform emits.

1. **New-business maintenance (`PIA-PIA-RNM-PIAMBK`) is sold under a "One-Time" selling model.** The asset the customer owns is therefore a One-Time asset, **not a renewable subscription** (contrast: beSECURE, a "Term Based"/`TermDefined` subscription, renews correctly).

2. **The platform's `initiateRenewal` tags a One-Time asset's renewal as `QuoteAction.Type = 'No Change'`, `Quantity 0`.** The COLA commit element (`COLAUpliftonRenewalNet`) is **action-type-gated** — it fires only when `SalesTransactionActionType = 'Renew'`. A `No Change` line never enters the COLA path, so no uplift is ever applied.

3. **The legacy design compounded it.** A Year-2 AutoAdd Product Configuration Rule (`14OWC0000022Eyb2AE`) **deletes** the owned-asset carryover line and substitutes a separate "Renewal Maintenance" (RRM) line that has **no SourceAsset to price against**. The native derived-pricing committer is contributor-keyed; with no contributor it skips the line, and the NetUnitPrice freezes at the stale fossil ($60.64) or $0.

**Net:** the renewable thing (the owned maintenance asset) was being thrown away, and the thing that was kept (the asset-less RRM line) was unpriceable. The pricing engine was healthy the whole time — it was simply never given a `Renew` line with a contributor.

---

## 3. The fix — what was built & deployed

The insight: **don't discard the owned-maintenance carryover — flip it to `Renew`.** Once it carries a `Renew` QuoteAction whose SourceAsset is the prior owned asset, the *native* renewal pricing applies the COLA uplift to last year's net and commits it. No new pricing logic, no catalog re-model, no selling-model change.

### 3.1 Apex — `RenewalMaintenanceFlip` (deployed, 4/4 tests)

`Data/sc-maint/sc3404/renewfix/build/classes/RenewalMaintenanceFlip.cls`

- Public `flipToRenew(Set<Id> quoteIds)` and a Flow-bindable `@InvocableMethod flipInvocable(List<FlipRequest>)`.
- Selects renewal-quote lines `WHERE Product2.Fortra_Product_Type__c = 'New Maintenance' AND QuoteActionId != null AND QuoteAction.Type = 'No Change'`.
- For each: sets `QuoteAction.Type = 'Renew'`, and on the line `StartQuantity = 0`, `Quantity = SourceAsset.Quantity` (RLM rule: a Renew line is `Quantity > 0` + `StartQuantity 0`; a No-Change line is `Quantity 0` + `StartQuantity > 0`).
- Bulk-safe, idempotent (only touches `No Change`), null/empty-safe.

### 3.2 Flow — `Fortra_Create_Renewal_Quote` (deployed, wired)

`Data/sc-maint/sc3404/renewfix/flow/flows/Fortra_Create_Renewal_Quote.flow-meta.xml`

Rewired so every renewal runs flip → reprice automatically:

```
initiate renewal → Populate_QLI_ServiceDate → Flip_Maintenance_Renewal (apex) → Reprice_Renewal (subflow) → Set_Output_Success
```

- `Flip_Maintenance_Renewal`: actionCall (apex `RenewalMaintenanceFlip`), input `quoteId ← renewalQuoteId`.
- `Reprice_Renewal`: subflow `Fortra_Quote_Reprice`, input `QuoteId ← renewalQuoteId` (Place Sales Transaction, `pricingPref=Force`, `configurationPref:{configurationMethod:Skip}`).

---

## 4. Validation — end-to-end, on a real owned asset

Proven on the owned RNM asset (`02iWC000008DmS1YAK`) by running the deployed-component sequence (`initiateRenewal` → `flipToRenew` → reprice) and reading the settled line after async cleanup.

| Check | Result |
|---|---|
| Renewal flips owned maintenance to `Renew` | **PASS** — qty 1, action = Renew |
| Commits the correct COLA net | **PASS** — `NetUnitPrice = 67.38` (= 62.48 × 1.0785) |
| No double partner-discount | **PASS** — COLA applied to the partner-net LTP, not re-discounted |
| Line survives the renewal cleanup | **PASS** — final state = **1 line**, $67.38, **no stray $0 RRM line** |
| Unit tests | **PASS** — 4 / 4 |
| Downstream (Workday line-type, billing, ARR) | **SAFE** — independent of the maintenance-type split |

Final settled line: `PIA-PIA-RNM-PIAMBK | Renew | qty 1 | NetUnitPrice 67.38 | NetTotal 67.38`.

---

## 5. Why earlier attempts failed — the wrong layer

Documented here so these dead-ends need never be re-attempted. All tried to *write the price*; none addressed the *missing `Renew` contributor*.

| Attempted lever | Why it can't work |
|---|---|
| Write `NetUnitPrice` directly | **DEAD** — engine-owned, read-only on insert |
| Posthook (`PartnerNetPricePosthook` v1.5) | **DEAD** — reprice-time write no-ops on a settled derived node |
| Lever-d procedure committer / RMPS | **DEAD** — `isSuccess=true` but no-op; value was prehook-sourced, identical across stale/active/rollback logs |
| Map owned product as contributor (PBEDP) | **DEAD** — platform-blocked: "the selected product is a derived product and can't be set as the source product" |
| Hand-attach a `Renew` QuoteAction after insert | **DEAD** — too late; line settles un-priced and locks at $0. The QA must exist *before* first pricing, which the real `initiateRenewal` + flip achieves |
| Re-model the catalog (merge RNM/RRM products) | **UNNEEDED** — far higher blast radius; the flip achieves the same outcome with ~120 lines |

---

## 6. To switch on in production

1. **Owner / Setup-UI:** deactivate the Year-2 AutoAdd PCR **`14OWC0000022Eyb2AE`** so the asset-less RRM line is no longer added. It is Product-Configuration-Rule metadata — togglable **only in Setup** (no API path). With it off, the flipped owned line is the sole, correctly-priced maintenance line.
2. **Smoke-test:** one production maintenance renewal end-to-end after the toggle.
3. **Pre-prod hygiene:** resolve the pre-existing `COLAUpliftTest.buildOverrideMap` coverage drift (a separate, known test-suite issue — it must compile for prod promotion).

---

## 7. Artifacts

| Artifact | Path |
|---|---|
| Apex fix | `Data/sc-maint/sc3404/renewfix/build/classes/RenewalMaintenanceFlip.cls` |
| Apex tests (4/4) | `Data/sc-maint/sc3404/renewfix/build/classes/RenewalMaintenanceFlipTest.cls` |
| Flow wiring | `Data/sc-maint/sc3404/renewfix/flow/flows/Fortra_Create_Renewal_Quote.flow-meta.xml` |
| Deep RCA | `Data/sc-maint/rca_deep/SC3346_RNCOLA_DEEP_RCA.md` |
| COLA official-docs RCA | `Data/sc-maint/rca_deep/SC3346_COLA_OFFICIAL_RCA.md` |
| Contributor verification | `Data/sc-maint/rca_deep/SC3346_CONTRIBUTOR_VERIFY.md` |
| Fix-path recommendation | `Data/sc-maint/rca_deep/SC3346_FIX_PATH_RECOMMENDATION.md` |
| Architectural fix plan (A/B) | `Data/sc-maint/rca_deep/SC3346_ARCHITECTURAL_FIX_PLAN.md` |
| This report (HTML / JSX / PDF) | `Data/sc-maint/rca_deep/exec/` |

---

*Deployed to FortraUAT. No Orders activated, no Workday events published. Accepted quote 00781068 untouched. Test data cleaned; canary baseline intact (1 lone fossil line, 0 stray renewal quotes). All reprices used `configurationPref:{configurationMethod:Skip}`.*
