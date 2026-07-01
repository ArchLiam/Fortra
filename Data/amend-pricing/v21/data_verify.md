# V21 Live Data Verify — Amend NetUnitPrice=0 defect (read-only)
Date: 2026-06-29. Org: FortraUAT. Active proc V21 (ESV 9QMWC00000025LN4AY) activated ~18:57.

## 1. Subject amend line (CONFIRMED)
Quote 0Q0WC000003FNXF0A4 (CAD, Amend), QLI 0QLWC000003kXyX4AU "Advanced Authentication Modes" Qty2, QLI LastModifiedDate 2026-06-29T19:43:05Z (POST-V21):
- ListPrice=4252.5
- UnitPrice=5906.29725  (GROSS carried OK — = asset NetUnitPrice seed)
- TotalLineAmount=11812.5945 (=Unit*2 OK)
- Subtotal=11812.5945 (OK)
- NetUnitPrice=0  (WRONG)
- NetTotalPrice=0 (WRONG)
- TotalPrice=0    (WRONG)
=> Confirms the report exactly: V21 restores GROSS carry, NET collapses to 0.

## 2. Other amend quotes
Only the subject was repriced AFTER V21 (18:57). The others touched today were repriced UNDER V20/older:
| Quote | Currency | QLI LastMod | Product | UnitPrice | NetUnitPrice | Pattern |
|---|---|---|---|---|---|---|
| 0Q0WC000003FNXF0A4 | CAD | 19:43:05 (POST-V21) | Advanced Authentication Modes | 5906.29725 | 0 | V21: gross carried, net=0 |
| 0Q0WC000003FR4c0AG | USD | 19:33:19 | Cobalt Strike | 0 | 0 | full-zero (pre-V21 reprice) |
| 0Q0WC000003FR4c0AG | USD | 19:33:19 | beSECURE - Cloud-Based | 0 | 0 | full-zero |
| 0Q0WC000003FPXR0A4 | USD | 17:54:35 | 5250 Integrator | 0 | 0 | full-zero (V20, pre-18:57) |
| 0Q0WC000003F55h0AC | USD | 04:27:41 | 5250 Integrator | 0 | 0 | full-zero (V20/older) |
NOTE on 0Q0WC000003FR4c0AG: Quote header LastModifiedDate=19:33 but its QLIs show full-zero (UnitPrice=0), i.e. they were NOT re-priced under V21 — consistent with the old V20 full-collapse. Only the subject QLI reflects V21.
=> Scope: exactly ONE amend line has been repriced under V21 (the subject). It shows the new "gross carried / net=0" signature. All other amends still show the OLD full-zero (UnitPrice=0 too) because they were last priced under V20/older. Cannot yet assert "universal" from multiple V21 datapoints — but the single V21 amend line matches the predicted pattern precisely, and ALL amends are net=0.

## 3. Derived/maintenance amend line under V21
NONE exists yet. The only V21-repriced amend (subject) is a single NON-derived line (AA Modes). No derived/maintenance amend line has been repriced since 18:57, so the DerivedPricingNetUnitPriceValueReset effect cannot be directly observed on an amend line today. (Would need a reprice of an amend quote containing a -NewMaintenance/derived line. Suggest repricing 0Q0WC000003FR4c0AG or a maint-bearing amend to capture this — requires human ack.)

## 4. New Sale & Renewal under V21 (BASELINE — UNAFFECTED)
New Sale (OriginalActionType=null) 0Q0WC000003FRiv0AG, QLIs repriced 19:29 (POST-V21):
| Product | Qty | List | Unit | Net | NetTotal | Total |
|---|---|---|---|---|---|---|
| beSECURE - Cloud-Based | 1 | 0 | 0 | 6695.3 | 6695.3 | 6695.3 |
| Powertech IAM (BoKS) | 1 | 355 | 355 | 355 | 355 | 355 |
| Powertech IAM (BoKS)-NewMaintenance (DERIVED) | 1 | 0 | 71 | 60.35 | 60.35 | 60.35 |
=> NetUnitPrice populated (=List for BoKS line; derived maint line nets 60.35). UNAFFECTED.

Renewal (OriginalActionType=Renew) 0Q0WC000003FRuD0AW, QLIs repriced 19:45 (POST-V21):
| Product | Qty | List | Unit | Net | NetTotal | Total |
|---|---|---|---|---|---|---|
| beSECURE - Cloud-Based | 1 | 0 | 7110.4086 | 5830.54 | 5830.54 | 5830.54 |
| Powertech IAM (BoKS) | 0 | 355 | 0 | 0 | 0 | 0 (Qty=0, expected) |
| Powertech IAM (BoKS)-NewMaintenance (DERIVED) | 1 | 0 | null | null | 0 | 0 |
=> beSECURE renewal line nets 5830.54 (OK). The BoKS line is Qty=0 ($0 expected). The derived NewMaintenance renewal line is null/0 — worth a separate look but distinct from the amend defect (Renewal-gated steps differ). Renewal NetUnitPrice IS populated on the priced (Qty>0) line.

## CONCLUSION
- Subject amend defect reproduced exactly under V21: gross fields carry the asset net seed (5906.29725) into UnitPrice/TotalLineAmount/Subtotal, but NetUnitPrice/NetTotalPrice/TotalPrice = 0.
- New Sale + Renewal price correctly under V21 (NetUnitPrice non-zero), incl. a derived NewMaintenance line on New Sale (60.35) — defect is isolated to Amend/LastTransaction lines.
- "Universal across amends" is INFERRED (all amends net=0; only one repriced under V21 so far). To make it empirical and to test the DerivedPricingNetUnitPriceValueReset effect on a derived amend line, a controlled reprice of additional amend quotes (incl. one with a maint/derived line) is needed — requires human ack.
