# DF6-blast-radius — SC-3346 RN-COLA-COMMIT blast radius (READ-ONLY, FortraUAT)

Org: liam.jeong.c@fortra.com.uat (FortraUAT). Date 2026-06-14.

## Defect population org-wide (the ONLY affected population)
SOQL: FPT='Renewal Maintenance' AND COLACalculatedPrice__c>0, GROUP BY ProductCode
-> ONLY product = PIA-PIA-RRM-PIAM (BoKS RRM, 01tWC00000DD1buYAD) = 7 lines. No other family has any COLA-bearing renewal-maint QLI.

The 7 COLA-bearing BoKS RRM lines:
| Line | Quote#/Status | QA? | Net | COLA | verdict |
|---|---|---|---|---|---|
| 0QLWC000003dEW24AM | 00781084 Draft | Renew | 67.38 | 67.38 | CORRECT (1/7) |
| 0QLWC000003e2Sn4AI | 00781109 Draft (canary) | no | 60.64 | 67.38 | WRONG x0.90 |
| 0QLWC000003dAaT4AU | 00781068 **Accepted** | no | 60.64 | 67.38 | WRONG x0.90 (Source_List_Price=null) |
| 0QLWC000003cy334AA | 0Q0WC0000037muD0AQ Draft | no | 54.58 | 60.64 | WRONG (COLA itself already x0.90, then x0.90 again) |
| 0QLWC000003eMph4AE | 0Q0WC0000039AMb0AM Draft "Copy" | no | 54.58 | 60.64 | WRONG (propagated through Quote CLONE) |
| 0QLWC000003cN584AE | 0Q0WC0000037AKH0A2 Draft | no | 0 | 67.38 | WRONG $0 (SLP=355,Base=71 SEEDED) |
| 0QLWC000003ck6X4AQ | 0Q0WC0000037XvB0AU Draft | no | 0 | 67.38 | WRONG $0 (SLP=355,Base=71 SEEDED) |

6 of 7 WRONG. The 1 correct line is the only one with QuoteAction Type='Renew' (7ocWC00000u7yf8YAA) — corroborates H3.

## Downstream propagation (the critical blast-radius result)
The Accepted quote 00781068 (0Q0WC0000037yTx0AI, GrandTotal=60.64) has FLOWED ALL THE WAY DOWN:
- Order 00095475 (801WC00000kaGBpYAM), Status=**Activated**, TotalAmount=60.64, Activated 2026-06-11, WorkdayReferenceID__c=**COM003** (=> went to Workday).
- OrderItem on it: PIA-PIA-RRM-PIAM Net=60.64 COLA=67.38 (WRONG persisted on an activated order).
- Asset 02iWC000008GKPaYAO, Status=Installed, **Price=60.64**, Acct "Nir DPP Test 2 2026-06-11 08:28".
Only 1 RRM OrderItem exists org-wide and it is the wrong one. Only 1 RRM Asset exists and it carries the wrong price.

## NOT in scope (legacy)
117 of 124 RRM QuoteLineItems are on Won quotes, ALL created in one bulk load window 2026-05-04 19:42-20:13Z, ALL NetUnitPrice=null, COLA=null, Source_List_Price/Base_Price=null, mostly Qty>1 (e.g. 21457, 92). These predate the COLA build and never ran the COLA seed/posthook — outside the defect family.

## H4 multi-asset $0 anchor (0Q0WC000003735t0AA) clarification
That quote's $0 line is PIA-PIA-RNM-PIAMBK (**New** Maintenance, FPT='New Maintenance', SLP=null, COLA=null) — a DIFFERENT SKU/flow, not a renewal-COLA RRM line. So the H4 "unseeded base" $0 is a New-Maint case. The two $0 lines in MY defect population (cN584/ck6X4) are RRM with SLP=355/Base=71 SEEDED and COLA=67.38 -> their $0 is a no-commit/no-op, NOT an unseeded-base bail.

## Remediation scale
Fix MUST remediate existing records, not only new ones:
- 6 wrong Draft/Accepted lines (re-priceable on Draft; 00781068 is Accepted+protected and already Activated+Workday+Asset).
- 1 Activated Order 00095475 + its OrderItem (60.64) + 1 Installed Asset (60.64) — these are committed downstream artifacts; a code/config fix alone will not retro-correct an activated order/installed asset/Workday record; needs a deliberate data remediation (order reprice/re-send or manual correction), owner-gated.
