# SC-3346 NB-DERIVED-TIER — Resolution (2026-06-14, FortraUAT)

## Fix: extend the V14 derived new-business formula to all 7 Maintenance_Rate__mdt tiers

**Defect:** V14 `DerivedPricingFormula` (file L71642) hard-coded only 3 of 7 tiers; everything else → `0 × SLP = $0`.
`Maintenance_Rate__mdt` (7 rows) was referenced 0×.

**Edit (one line, V14 only):**
```
- IF(AttributeValue='Premier',0.30, IF(='Standard',0.20, IF(='Professional',0.20, 0))) * Source_List_Price__c
+ IF(AttributeValue='Premier',0.30, IF(='Standard',0.20, IF(='Professional',0.20,
+   IF(='Basic',0.15, IF(='Premium',0.24, IF(='Express',0.30, IF(='Expert',0.35, 0))))))) * Source_List_Price__c
```
Rates verified against the authoritative CMDT: Premier 0.30 / Standard 0.20 / Professional 0.20 / Basic 0.15 /
Premium 0.24 / Express 0.30 / Expert 0.35. The 3 working tiers are byte-preserved; new branches appended before
the final `0`. Parens balanced (7/7), XML valid, diff = exactly L71642 (the 5 identical formulas in inactive
V8–V13 blocks are intentionally left as-is).

## CORRECTED IMPACT (the report's "207 lines → $0" was misleading)
The formula only prices **derived New Maintenance** lines. Of the 207 "unhandled" MTD rows, most are **non-derived**
and price normally through their own paths — they are NOT zeroed by this formula:
- Basic 182 = 118 Subscription + 56 Perpetual + 2 **New Maintenance** + 1 Renewal Maint + 1 Prof Svc + 1 Software + 3 blank
- Premium 2 = 2 Software (not maintenance)
- Expert 8 = 7 blank + 1 **New Maintenance**
- Express 0 live
The lines actually fixed today: **~2 Basic + 1 Expert derived New Maintenance** (currently $0), plus **all future
new-business maintenance** on Basic/Premium/Express/Expert. Still a real defect (incomplete formula); smaller live blast.

## platinum (owner decision: LEAVE AS-IS + DOCUMENT)
`platinum` (lowercase MTD picklist value) has **zero pricing impact** and was deliberately NOT added to the formula:
- All 15 live `platinum` lines are **Renewal Maintenance** (EFT WSM / EFT SMB WSM products) on Approved quotes.
- Renewals price via **COLA**, which does **not** use the MTD tier at all → the platinum tag never affects their price.
- There are **0 new-business platinum lines**, so the NB formula would never see it.
It is a legacy data-hygiene artifact (no `Maintenance_Rate__mdt` row). Owner (Liam) chose to leave it as-is and
document it; revisit only if `platinum` ever needs to be a first-class tier (would need a CMDT row + formula branch).

## DEPLOYED + VERIFIED 2026-06-14 ✅
User deactivated V14; deployed the 7-tier edit (clean deploy, no cosmetic error). The deploy **re-published V14 active
automatically** (metadata carried `<status>Active</status>`), so no manual reactivation was needed. Verified:
- Live V14 `DerivedPricingFormula` (L71642) now resolves all 7 tiers (Premier .30/Standard .20/Professional .20/
  Basic .15/Premium .24/Express .30/Expert .35); XML valid; diff vs pre-deploy = exactly 1 line.
- **Scale cache synced** — Force reprice of 00781057 returned `isSuccess:true` (no `ScaleCacheServiceException` desync).
- **No regression:** Standard control 00781057 still 71 (0.20×355); Premier control 0QLWC000003cL1i4AE still 3000 (0.30×10000).
- New-tier branches deterministic-by-construction (same IF pattern, CMDT-exact rates); direct Basic/Expert end-to-end
  test is data-limited (no Draft Fortra-book derived minority-tier line with SLP exists today).
- FIM-462 (renewal) **not affected** — this is the new-business formula only; the renewal formula `DerivedPricingRenewals` is untouched.
- **Caveat:** most CURRENT minority-tier lines are on the inactive **Standard Price Book** (non-derived) → that's the
  separate ZERO-LIST-PBE wrong-book item, not this formula; so the live impact today is small (handful of derived
  Fortra-book lines + all future). `platinum` left as-is (0 pricing impact) per owner decision.

## Deploy ritual (same as M-2 removal)
V14 must be inactive to deploy an ExpressionSetDefinition edit. Sequence: user deactivates V14 → deploy the edited
procedure → user reactivates V14 + re-sync. Pristine rollback: `pristine_tier/`. Edited source: `retrieve_tier/`.

## Verification plan (post-reactivation)
1. Positive control: a Standard New-Maint line still prices 71 (0.20×355) — proves structure intact.
2. New branches: a Basic / Expert derived New-Maintenance line now prices `rate × SLP` (not $0).
3. FIM-462 regression: FIM-FIM-RNM-CCMLSE renewal still prices 462 (general post-republish sanity; the NB edit
   doesn't touch the renewal path).
4. No gack / ScaleCache desync on reprice.
