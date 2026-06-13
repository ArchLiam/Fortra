# 08 — M-1 reconciliation: SDD "no Apex pricing prehook" is false-as-built

**Target doc:** `docs/Fortra-Maintenance-Derived-Pricing-Solution-Design.docx` (binary — owner applies the edits below; text extraction lines cited from `*Jira Related Data/sc3347/docs_txt/...txt`).
**Status:** reconciliation prepared 2026-06-12; the `.docx` keystroke edit is the doc owner's (Nir/Marc). No code change — this is M-1's correct resolution (M-1 was always a doc-reconciliation, not a code defect).

## The claim (verbatim, where it's wrong)
- **L22:** "…prices them correctly using Revenue Cloud configuration plus a single declarative Flow — **with no custom Apex pricing prehook** —…"
- **L27:** "**No custom Apex pricing prehook** — delivered with one new field, one Flow, and one pricing-procedure formula change."
- **L160:** "…entirely within Revenue Cloud configuration plus one declarative Flow — **no Apex pricing prehook**. … a prehook cannot set the price (this was verified empirically and the prehook approach was abandoned)."

## The reality (live FortraUAT, 2026-06-12)
Both of these are live `SignalingApexProcessor` implementations that participate in maintenance pricing:
- **`PartnerNetPricePosthook`** — `implements RevSignaling.SignalingApexProcessor`; **writes `NetUnitPrice`/`NetTotalPrice`** (and the renewal-maintenance COLA-net block). It is the lever that commits partner/renewal net on maintenance lines.
- **`COLAUpliftPrehook`** — `implements RevSignaling.SignalingApexProcessor`; **seeds `COLACalculatedPrice__c`**, which the active renewal formula (`DerivedPricingRenewals`) reads **first** (`IF(COLACalculatedPrice__c > 0, COLACalculatedPrice__c, …)`).

Per the SC-3350 RCA, on **non-derived `LastTransaction` renewal lines** the engine owns `NetUnitPrice` via the waterfall and a FormulaBasedPricing write does not commit — the **prehook seed is the only lever that commits net**. So the prehook stack is **load-bearing**, not optional. The principle as stated is unattainable.

## The precise correction (scope the claim — it's true only for new-business)
The claim is accurate **only** for the **new-business derived-maintenance** path (which genuinely uses the stamped-source-field + one formula, no *new* prehook). It is false for the **renewal** and **partner-net** paths, which rely on the pre-existing `SignalingApexProcessor` stack.

Suggested replacements:
- **L22 / L27:** change "with no custom Apex pricing prehook" → **"with no *new* Apex pricing prehook on the new-business maintenance path (the renewal and partner-net paths continue to rely on the existing `COLAUpliftPrehook` / `PartnerNetPricePosthook` signaling processors)."**
- **L160:** keep the (correct) explanation that a prehook cannot set the price on **IsDerived new-business** lines, but **add**: *"Renewal maintenance lines are non-derived `LastTransaction` lines; for those, net is committed via the existing `COLAUpliftPrehook` seed (`COLACalculatedPrice__c`) and `PartnerNetPricePosthook`, per the SC-3350 RCA. The 'no prehook' statement applies to the new-business derived path only."*
- Add a one-line **"Apex components in the pricing path"** subsection listing `COLAUpliftPrehook` and `PartnerNetPricePosthook` (both `SignalingApexProcessor`) so the deploy manifest is built from the live org, not the SDD's component list.

## Why this matters beyond accuracy
The peer review's M-1 concern was that an engineer building the **deploy manifest from the SDD** would omit the prehook stack (since the SDD says there's none) → a prod cutover that ships the procedure/Flow but **not** `COLAUpliftPrehook`/`PartnerNetPricePosthook` → renewal/partner maintenance lines price at $0 in prod (this is also M-6: the prod `COLAUpliftPrehook` is already stale). The reconciliation closes that trap.
