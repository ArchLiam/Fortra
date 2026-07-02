# SC-3506 / SC-3522 Peer Review — Evidence Bundle (captured live from FortraUAT, 2026-07-01)

Org: **FortraUAT** (00DWC000006eUFF2A2), native Revenue Cloud Advanced / RLM. All queries read-only.

## 0. Ticket under review

- **Parent (work being reviewed):** SC-3506 — "RCA Investigation Task: Validate Asset State Period Behavior for Amendments and Renewals." Assignee Marc Debrey, reporter Dawn Krauss, Priority Medium, Status To Do.
- **This ticket (the peer review):** SC-3522 — "Peer Review" (subtask of SC-3506), In Progress, assigned to Liam.
- **Stated motivation (verbatim from SC-3506):** "As per the 6/29 Demo, please confirm the expected Asset State Period creation behavior for amendment and renewal processing… Validation of expected Asset State Period generation has been requested because **license key processing depends on the latest state period attributes**. Alice indicated Asset State Periods are generated when changes take effect, but team requested confirmation of expected behavior across amendment and renewal scenarios."
- **Acceptance Criteria (SC-3506):**
  1. Document expected Asset State Period behavior for: **Amendments, Renewals, Cancellations**.
  2. Verify current implementation matches expected RCA behavior.
  3. Identify any gaps requiring fixes.

> NOTE: Marc Debrey's actual investigation write-up is NOT present in the repo and there is no Jira MCP connection. This peer review is therefore an **independent ground-truth reconstruction** of (a) the expected behavior per official Salesforce RLM docs and (b) the observed behavior in FortraUAT — which is exactly what a reviewer needs to check Marc's findings against.

## 1. Object model (from `sf sobject describe`, FortraUAT)

### AssetStatePeriod — "the state of an asset over a period of time"
Key fields: `AssetStatePeriodNumber` (Name), `AssetId`, `StartDate` (datetime), `EndDate` (datetime), `Quantity`, `Amount` (currency), `Mrr` (currency), `UnitPrice`, `UnitPriceUplift` (%), `Discount` (%), `DiscountAmount`, `SegmentType` (picklist), `SegmentName`, `SegmentIdentifier`, `RampIdentifier`, `BillingFrequency`, `LegalEntityId`, `PriceRevisionPolicyId`, `Legacy_Id__c`.
- `SegmentType` picklist: **Yearly, Custom, FreeTrial, Prorated**
- `BillingFrequency` picklist: Monthly, Quarterly, Semi-Annual, Annual

### AssetAction — "a change made to a lifecycle-managed asset" (fields not editable)
- `Type` picklist: **Generate, Change, Cancel, Convert**
- `CategoryEnum` picklist: **Initial Sale, Upsells, Downsells, Cross-Sells, Cancellations, Transfers, Terms And Conditions Changes, Renewals, Upgrades, Downgrades, Swaps, Other**
- `Subtype` picklist: StartDateAdjustment, TransferFrom, TransferTo, Rollback, **FieldAmendment**, SwapIn, SwapOut, UpgradeFrom, UpgradeTo, DowngradeFrom, DowngradeTo
- Delta fields: `QuantityChange`, `MrrChange`, `Amount`, `SubtotalChange`, plus running totals `TotalRenewalsAmount`, `TotalUpsellsAmount`, `TotalCancellationsAmount`, `TotalQuantity`, `TotalMrr`, etc. Custom: `Order_Line_ARR__c`, `Legacy_Id__c`.

> **This resolves the "UNCONFIRMED picklist literals" flagged in the SC-3419 research.** Official docs called these "Category = Initial Sale / Renewals / Amendments / Cancellations"; the live org uses `CategoryEnum` and splits "Amendments" into the concrete values **Upsells / Downsells / Cross-Sells / Upgrades / Downgrades / Swaps / Terms And Conditions Changes**. `Type` adds **Convert** (quote→order conversion) and **Cancel** beyond Generate/Change.

## 2. Population distribution (`GROUP BY`, FortraUAT)

- `AssetStatePeriod` total rows: **430,642**
- `AssetAction` total rows: **430,646**
- AssetAction by Type / CategoryEnum:
  | Type | CategoryEnum | Count |
  |---|---|---|
  | Generate | Initial Sale | 430,630 |
  | Change | Upsells | 10 |
  | Change | Renewals | 5 |
  | Cancel | Cancellations | 1 |
- AssetStatePeriod by SegmentType: **Yearly = 429,721**, **null = 921**

> **Interpretation:** the ~430k Generate/Initial-Sale + Yearly rows are the **bulk data migration** (install base). Only **16 records** were produced by the *live RLM lifecycle* in this org (10 Upsells, 5 Renewals, 1 Cancellation). Those 16 are the only empirical evidence of amend/renew/cancel behavior — the entire validation rests on them, so the sample is thin and any conclusion should say so. The lifecycle-generated state periods have `SegmentType = null` (the 921 null rows), whereas migrated periods are `Yearly` — a data-consistency observation worth noting.

## 3. The 16 lifecycle AssetActions (Type != Generate)

| AssetAction | Type / Category / Subtype | Asset | Date | Δqty | Δmrr | TotalQty |
|---|---|---|---|---|---|---|
| AA-000000083 | Change/Renewals | 06tCOTYA2 Structural Sanitization | 2026-03-03 | 0 | +1.54 | 1 |
| AA-000001671 | Change/Upsells | 07DSnFYAW 24x7 Monitoring | 2026-04-01 | +1 | +1250 | 2 |
| AA-000001653 | Change/Upsells | 07DXlKYAW Automate Professional | 2026-03-31 | +1 | +200 | 2 |
| AA-000543544 | Change/Renewals | 08ARwnYAG Abstract | 2026-06-11 | 0 | +0.30 | 1 |
| AA-000543545 | Change/Renewals | 08ARwoYAG beSECURE | 2026-06-11 | 0 | 0 | 1 |
| AA-000543546 | Cancel/Cancellations | 08ARwoYAG beSECURE | 2026-06-11 | −1 | 0 | 0 |
| AA-000543565 | Change/Upsells/**FieldAmendment** | 08DFvvYAG BoKS NewMaintenance | 2026-06-15 | 0 | 0 | 1 |
| AA-000543549 | Change/Renewals | 08FcLaYAK beSECURE | 2026-06-11 | 0 | **−557.94** | 1 |
| AA-000543567 | Change/Renewals | 08LXfZYAW SECURE Email Gateway | 2026-06-15 | 0 | **−162.5** | 100 |
| AA-000543569 | Change/Upsells | 08LXfZYAW SECURE Email Gateway | 2026-06-15 | +175 | 0 | 275 |
| AA-000543603 | Change/Upsells | 08MuWnYAK Data Redaction | 2026-06-16 | +300 | 0 | 550 |
| AA-000543604 | Change/Upsells | 08MuWoYAK Structural Sanitization | 2026-06-16 | +300 | 0 | 550 |
| AA-000543606 | Change/Upsells | 08MuWpYAK OCR Feature | 2026-06-16 | +300 | 0 | 550 |
| AA-000543605 | Change/Upsells | 08MuWqYAK SECURE Exchange Gateway | 2026-06-16 | +300 | 0 | 550 |
| AA-000543857 | Change/Upsells | 08deyfYAA Cobalt Strike | 2026-06-29 | +2 | +983 | 3 |
| AA-000543858 | Change/Upsells | 08deygYAA beSECURE | 2026-06-29 | +2 | +34 | 3 |

## 4. AssetStatePeriod rows for the lifecycle assets (ordered by CreatedDate)

**RENEWALS — new forward-dated period created, starts day after prior EndDate:**
- 06tCOTYA2 (Renewal): ASP-077 `2026-02-26→2027-02-25` qty1 mrr30.75 → ASP-083 `2027-02-26→2039-02-25` qty1 mrr32.29. ✅ new period, day-after start, MRR uplifted (COLA). ⚠️ new EndDate = **2039** (12-year span — anomaly, likely term/date-derivation bug, cf. SC-3297 billing-date memory).
- 08ARwnYAG (Renewal): ASP-403 `2026-06-05→2027-06-04` mrr3.83 → ASP-544 `2027-06-05→2028-06-04` mrr4.13. ✅ clean renewal, uplifted.
- 08FcLaYAK (Renewal): ASP-543 `2026-06-11→2027-06-10` mrr557.94 → ASP-548 `2027-06-11→2028-06-10` **mrr 0**. ⚠️ new period created but **zero-priced** (matches known COLA/renewal zero-price defects SC-3350/SC-3346).
- 08LXfZYAW (Renewal + Upsell): ASP-561 `2026-07-01→2026-07-31` q100 mrr162.5 → ASP-566 `2027-07-01→2028-06-30` q275 **mrr0** → ASP-568 `2026-08-01→2027-06-30` q275 mrr162.5. Multiple overlapping periods from stacked renew+upsell; ordering not strictly chronological.

**AMENDMENTS (Upsells) — prior period EndDate truncated to amendment date, new period from next day with new qty:**
- 07DSnFYAW (Upsell q1→2): ASP-1645 `2026-03-31→2026-04-01` q1 → ASP-1671 `2026-04-02→2027-03-30` q2. ✅ classic period-split at effective date.
- 08DFvvYAG (Upsell/FieldAmendment): ASP-481 `2026-06-05→2026-06-14` q1 → ASP-564 `2026-06-15→null` q1. ✅ split; ⚠️ new period **EndDate = null** (open-ended).
- 08MuWnYAK (Upsell q250→550): ASP-598 `2026-04-01→2026-06-15` q250 → ASP-602 `2026-06-16→2027-03-31` q550. ✅ split, new qty.

**CANCELLATION — NO new AssetStatePeriod:**
- 08ARwoYAG: sequence = Generate(06-05) → Renewal(06-11 16:58, mrr0) → Cancel(06-11 17:09, Δqty−1). Result: **only ONE state period** ASP-404 `2026-06-05→2026-06-10` q1 mrr0. Asset now Status=Installed, CurrentQuantity=0, CurrentMrr=0, Lifecycle `2026-06-05→2026-06-10`.
  - ✅ Cancellation created **no** new AssetStatePeriod (matches documented model).
  - ⚠️ The Renewal action AA-000543545 (totQty 1) left **no** renewal state period either — the immediately-following cancel appears to have removed/rolled back the just-created future renewal period. Edge case: renew-then-cancel leaves the asset with only the (now-closed) original period. Worth flagging as the one case where "renewal creates a period" is NOT observable.

## 5. License-key dependency (the ticket's stated motivation)

- "License key processing" in Fortra = the **LKG (License Key Generation) framework** — ~141 `Lkg*` Apex classes (LkgProcessor orchestrator; Mapper/RequestBuilder/RequestController/RecordCreator pipeline per product "silo"; persists `License_Key__c` + Attachment; HTTP callout to `callout:keygen_api`). Ref: `Org Data/01a_Apex_LKG_Framework.md`.
- LKG is described as "**independent of the Revenue Cloud / RCA pricing stack**" — it is driven from an LWC/Aura UI payload (account, contacts, **expiration**, keyType, attributes) and, for some products, from hardware-asset requests. It does not appear to query `AssetStatePeriod` directly (grep of `LkgRecordCreator*` shows only `StartDate` referenced 3×).
- Therefore the dependency is **business-process level**: when an amendment/renewal/cancellation takes effect, the *new/latest state period* defines the correct **expiration date** and **entitlement quantity** that the license key must reflect. If state periods are generated wrong (e.g. the 2039 end-date anomaly, the mrr=0 renewals, or a missing renewal period), the license-key inputs would be wrong. This is why SC-3506 wants the ASP behavior confirmed before relying on it for key processing.

## 6. Cross-references in repo (prior research that corroborates the expected model)

- `Jira/Task/sc3419 .../evidence/W1_rlm_asset_lifecycle.md` and `OFFICIAL_RCA_REFERENCES.md` — official RLM asset-lifecycle model: OrderItem→AssetActionSource→AssetAction→Asset, time-sliced by AssetStatePeriod; renewal adds a new state period, **cancellation does not**; createOrUpdateAssetFromOrder (async) matches by Account+Product.
- `Jira/Task/sc3441 .../07_DEEP_RESEARCH_NATIVE_CANCELLATION.md` — cancellation lifecycle; `PriceRevisionPolicy` is a renewal price-uplift mechanism **on AssetStatePeriod** (confirms the `PriceRevisionPolicyId` field's purpose); `Asset.PricingSource=LastTransaction` scope = amend/renew.
- `scripts/apex/setupSC3502Lineage.apex` — builds a renewable Contract+Asset for end-to-end renewal testing (SC-3502).
- `scripts/apex/f04_initiateRenewal.apex` (currently open) — headless renewal generation via `Fortra_Create_Renewal_Quote` flow, for exercising the renewal path.
- Memory: SC-3297 (billing From/To date derivation), SC-3350/SC-3346 (COLA renewal zero-price) — relevant to the anomalies observed above.
