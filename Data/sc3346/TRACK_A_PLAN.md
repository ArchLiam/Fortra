# SC-3346 MAINT-ONLY — Track A Implementation Plan

**Goal:** every renewal-maintenance QLI is **born with a QLI-linked `Renew` QuoteAction**, so `COLAUpliftHandler.handleBeforeInsert` runs (it gates on the inserted QLI carrying a `QuoteActionId` + `QuoteAction.Type='Renew'`) and the engine routes the line to a **writable priced node** → the COLA net commits and survives reprice.

**Proven target shape (the acceptance bar):** `0QLWC000003dEW24AM` (00781084) and the IP360 experiment — `QuoteActionId` populated, `QuoteAction.Type='Renew'`, `COLA_Source__c` set, `NetUnitPrice` = COLA net, holds through Force reprice.

**Owner:** renewal-flow owner (Nir Kailash / SC-3346 build). UAT-only; prod cutover is a separate, currently-NO-GO engagement.

---

## The core problem this plan must solve
The renewal-maintenance line is created QuoteAction-less by **both** prod entry points:
- `Fortra_Create_Renewal_Quote` → `initiateRenewal` on the **prior** assets, then the **Year-2 AutoAdd PCR `14OWC0000022Eyb2AE`** adds the RenewalMaintenance SKU as a configurator line (no QuoteAction).
- `Fortra_Renewal_Quote_Creation` → inserts QLIs straight from ContractLineItems (`QuoteActionId=null`).

And the **first renewal** is structurally hard: the prior maintenance asset is a **Year-1 "New Maintenance" asset under a OneTime-only selling model** (product `01tWC00000DD1bsYAD` has no TermDefined PSMO), so `initiateRenewal` of it yields `No Change`/unlinked — it can't self-substitute into a `Renew` RenewalMaintenance line. (Subsequent Y2→Y3 renewals renew a RenewalMaintenance asset, which *can* be TermDefined.)

---

## Sub-approach decision (resolve in Phase 1)

| Option | Mechanism | Pros | Cons / prerequisites |
|---|---|---|---|
| **A1 — Platform asset-renewal (PROVEN)** | Renewal flow calls `initiateRenewal` on the prior **maintenance** asset with a **term-advancing window** (`renewStartDate` = day after the asset's term end); platform mints the linked `Renew` QuoteAction. | Platform-native; **proven** (IP360 → committed 2097.9, held). No synthetic QuoteAction. | Requires the maintenance asset to be a **renewable-term** asset. Works for Y2+ (RenewalMaintenance). **Fails for Y1** (OneTime NewMaintenance, no term) → needs A3 or A2 for the first renewal. |
| **A2 — Flow born-links the AutoAdd line** | Keep the AutoAdd PCR, but have the renewal flow create a `Renew` QuoteAction (`SourceAsset` = prior maintenance asset) and set the RenewalMaintenance QLI's `QuoteActionId` **at birth** (before the COLA handler's before-insert). | No catalog change; minimal blast radius. | **UNPROVEN** that a *manually-created* QuoteAction routes the line to a priced node the way the platform-minted one does (the experiment used platform `initiateRenewal`). Must validate in Phase 1. RLM Quote/QLI DML lock — the link must be set inside the platform-sanctioned create path, not external DML. |
| **A3 — TermDefined maintenance from Y1 (catalog)** | Model maintenance as a TermDefined annual subscription from Y1 (one renewable maintenance product, or give the Y1 maintenance a TermDefined model + term), so every renewal is a clean platform asset-renewal (A1). | Cleanest long-term; eliminates the AutoAdd-PCR substitution + the OneTime-Y1 gap entirely. | Largest change: catalog/PSMO + PBE config + the auto-add model + retro on existing OneTime assets. PSMO↔PBE delete-order interlock; PCR has no migration tooling; product-config durability. |

**Recommendation:** **A1 for the durable mechanism**, with the Y1-first-renewal gap closed by **A3** (make maintenance TermDefined-renewable from Y1) if the business accepts the catalog remodel, else **A2** as a contained first-renewal bridge (pending its Phase-1 routing proof). Decide after Phase 1.

---

## Phases

**Phase 0 — Pin the prod renewal path (read-only).** Confirm which entry point real renewals use (`Fortra_Create_Renewal_Quote` vs `Fortra_Renewal_Quote_Creation`), and trace one real Y1→Y2 and one Y2→Y3 renewal end-to-end to see exactly where the maintenance line is born and whether/where a QuoteAction could attach. Output: the precise insertion point for the fix.

**Phase 1 — Validation experiments (the decisive harness; reversible, draft quotes only).**
- **E1 (done):** A1 on a renewable-term asset → born-linked `Renew`, net commits + holds. ✓ (IP360 `02iWC000007Y3M1YAK`.)
- **E2:** A2 routing — manually create a `Renew` QuoteAction + a RenewalMaintenance QLI with `QuoteActionId` set at insert (via the sanctioned path), reprice, assert it routes to a **priced node** (net commits, not born-stale). PASS → A2 viable; FAIL → A2 dead, use A3.
- **E3:** A3 prerequisite — a TermDefined-sold maintenance asset (term set at Y1) renews clean via A1 with an advancing window. Confirms the catalog model.
- **E4 (gate):** confirm the chosen mechanism doesn't regress the working path (00781084 still 67.38) or the new-business derived path.

**Phase 2 — Implement the chosen mechanism** in the renewal flow / SC-3346 renewal Apex (e.g. have `Fortra_Create_Renewal_Quote` renew the maintenance asset via `initiateRenewal` with an advancing window for A1, and/or born-link in `RenewalQuoteLineHandler` for A2). Author against the **live** source (`Org Data/_src`); never re-introduce the net-seed or rely on the dead `RenewalAssetQuantityHandler` flip.

**Phase 3 — Test coverage.** The SC-3346 renewal classes are red/low-coverage per peer review. Bring the touched classes (`RenewalQuoteLineHandler`, `QuoteRenewalTypeHandler`, `RenewalMaintenancePricingService`, `COLAUpliftHandler`) to ≥75% with the E1–E4 scenarios as the assertions. (Note: `COLAUpliftTest` was realigned to v1.1 this session — keep it green.)

**Phase 4 — Existing-population remediation (scoped).** ~498,250 RenewalMaintenance QLIs are already QuoteAction-less/born-stale. The fix only corrects NEW renewals. Decide scope: only **open/Draft** renewal quotes need remediation (re-renew or a one-time corrective re-create); closed/historical lines don't. Bulk re-renewal at scale carries governor/throughput risk — batch it.

**Phase 5 — Deploy + regression gate + rollout.** Behind the **FIM-462 native-preserve gate** (don't regress the ~199 native-config-derived lines), validate against E1–E4 + a renewal/new-business/amendment sweep, confirm the live active procedure version, then UAT sign-off. Prod cutover is separate and currently NO-GO (M-3/M-6 + field packaging must land first).

---

## Risks & guardrails
- **Scale/blast radius:** ~513K renewal-maintenance lines, single shared pricing procedure for Quote+Order; mis-routing cascades to Workday line-type + the COLA family.
- **RLM Quote-DML lock:** the QuoteAction link must be set inside the platform-sanctioned create path (initiateRenewal / before-insert handler), not external DML.
- **Catalog durability (A3):** PSMO↔PBE delete-order interlock; PCR has no migration tooling; Gearset/refresh can silently revert PSMO/PBE/PAD flags — re-verify at deploy.
- **Per-call determinant:** Renew-vs-No-Change depends on the renew **window advancing the term** — the implementation must guarantee an advancing window or it silently regresses to `No Change`.
- **Dead-code trap:** `RenewalAssetQuantityHandler`/`RenewalMaintenancePricingService.applyRenewalMaintenanceNetPrices` are unwired; wiring them changes live pricing on every renewal save — full coverage required first.
- **Rollback:** flows/Apex are versioned (no version-delete needed for flows); Phase-1 experiments create only draft quotes (delete to revert); no asset mutation pre-activation.

## Open decisions for the owner (Nir)
1. Is the Y1 OneTime "New Maintenance" / Y2 TermDefined "Renewal Maintenance" split intentional, or can maintenance be TermDefined-renewable from Y1 (A3)?
2. For the first renewal: born-link bridge (A2) vs catalog remodel (A3)?
3. Backfill scope for the 498K existing born-stale lines (open-Draft-only vs broader).

## Acceptance criteria
A real Y1→Y2 and Y2→Y3 renewal (and a maintenance-only renewal) each produce a renewal-maintenance line with `QuoteActionId` linked + `Type=Renew` + `COLA_Source` set + `NetUnitPrice` = COLA net, holding through reprice — with no regression to 00781084, the new-business derived path, or the FIM-462 native lines.
