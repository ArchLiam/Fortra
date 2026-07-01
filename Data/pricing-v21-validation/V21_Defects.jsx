import React, { useState, useMemo } from "react";

/**
 * V21 Pricing-Procedure Validation — Defect Board
 * Self-contained, dependency-free (inline styles). Drop in any React app:
 *   import V21Defects from "./V21_Defects.jsx";  ->  <V21Defects />
 *
 * Source of truth: Data/pricing-v21-validation/V21_VALIDATION_RESULTS.md
 * 23 reportable defects (16 P0 + 7 P1/P2). Validation only — fixes are PROPOSED, not applied.
 */

const ORG = "https://fortra--uat.sandbox.lightning.force.com";

// type: "PROCEDURE" (V21 step / pricing engine) | "ORG-CONFIG" (data/config a real user also hits)
const DEFECTS = [
  // ---------------- P1 / P2 (this run) ----------------
  {
    id: "I-03", pri: "P1", type: "PROCEDURE", cat: "Proration", ticket: "SC-3420 / SC-3411",
    title: "Mid-term TermDefined derives correct PTC but never prorates the net",
    step: "Step 97/123 Proration → no Quantity×Price/Total step multiplies net by PricingTermCount",
    problem: "PTC is derived exactly (270/365 = 0.7397) but the net is charged at the FULL annual amount — NetTotal = list×qty×1.0, not ×PTC. Pre-V21 lines on the same shape stayed prorated, so the net-proration leg was dropped in the V11→V12 rebuild and never restored.",
    fix: "Restore the net-proration leg: a TermDefined-gated step setting NetTotalPrice = NetUnitPrice × Quantity × PricingTermCount before the Total aggregation, guarded identically to the PTC writer so full-term (PTC=1) lines stay inert.",
    record: `${ORG}/lightning/r/QuoteLineItem/0QLWC000002LCwH4AW/view`, recordLabel: "QLI 0QLWC…LCwH (PTC 0.7397, NetTotal 750 vs 554.79)",
  },
  {
    id: "D-09", pri: "P1", type: "PROCEDURE", cat: "Pricing Mode", ticket: "SC-3384",
    title: "EUR Total-Price tier reads the USD tier then FX-converts",
    step: "Steps 17-20 Total Price Mode (currency-blind composite key) → steps 33-36 Currency Conversion",
    problem: "EUR line UnitPrice = 1268.44 = USD tier 1357.2 × 0.9346 EXACTLY (5 dp), not the seeded native EUR tier 1248.62 → +19.82 EUR/unit overcharge. Net channel also FX-compounds across reprices. Same currency-blind root as P0 G-02, second channel.",
    fix: "Add CurrencyIsoCode to the Total-Price tier composite key inside AttributeVolumePricingPrehook (key construction, NOT the SOQL filter); skip FX when source currency == quote currency; make FX idempotent (convert from an immutable USD base each pass).",
    record: `${ORG}/lightning/r/Quote/0Q0WC0000036xy90AA/view`, recordLabel: "Quote 0Q0WC…6xy9 (EUR, QLI …cE8H)",
  },
  {
    id: "K-09", pri: "P1", type: "PROCEDURE", cat: "Edge Cases", ticket: "SC-3345",
    title: "Empty category groups keep stale Total_Services / Total_Subscription",
    step: "Steps 116-118 category groups + 103/104/109 aggregate rollups — no zero-init step",
    problem: "A SUM over an empty filtered group writes nothing, so the total keeps its stale prior value. Controlled reprice: Software reset 666→0 (non-empty) but EMPTY Services/Subscription stayed 555/999. 6 live quotes carry non-zero Total_Services with zero Services lines.",
    fix: "Add an unconditional zero-init for each category total before its aggregate (clone the SC-3345 Fix1 category-reset pattern), or enable the proc header 'Initialize resources with default values'. Mirror for Total_Discount_Amount__c.",
    record: `${ORG}/lightning/r/Quote/0Q0WC000003FbGr0AK/view`, recordLabel: "Quote 0Q0WC…FbGr (svc 555 stale / sw 0 reset)",
  },
  {
    id: "F-12", pri: "P1", type: "PROCEDURE", cat: "Transaction Type", ticket: "SC-3441",
    title: "Partial amend-remove aborts; no prorated negative delta",
    step: "Step 105 Stamp Base Filter (NetUnitPrice>0 not null-safe) + dropped V18 cancel-seed",
    problem: "A clean partial amend-remove (−50000 of 100000, 6/12 months left) Force-reprices to isSuccess=false / SF-Pricing-00006 at StampBaseFilter — NetUnitPrice=null, TotalPrice=0. Neither the prorated −37500 nor a full-credit is produced; amend-removes share the broken SC-3441 cancel path and there is no prorated-amend mechanism.",
    fix: "(A) Re-add the V18 negative-delta seed before StampBaseFilter and/or make the filter null-safe (same as K-01). (B) Route Amend(qty<0) lines through TermDefined proration with their remaining-term window so PTC≈0.5 multiplies the negative net.",
    record: `${ORG}/lightning/r/Quote/0Q0WC000003FapR0AS/view`, recordLabel: "Quote 0Q0WC…FapR (QLI …kkKf)",
  },
  {
    id: "A-07", pri: "P2", type: "ORG-CONFIG", cat: "Pricing Source", ticket: "SC-3346",
    title: "Maintenance family inconsistency — FIM lacks Maintenance Type attribute",
    step: "Step 39 Derived Pricing Formula (missing attr → tier 0) + step 41 Native Pull (100%-copy)",
    problem: "BoKS derives correctly (0.20×355=71) because it carries Maintenance Type Defn=Standard. FIM CCM family has NO Maintenance Type → native 100%-copy (CCMLSE Net=2008 = full license list) or $0. Only ~183 of 3,394 maintenance products carry the attribute.",
    fix: "(1) DATA: backfill the Maintenance Type Defn attribute on the ~3,200 maint products lacking it (FIM CCM especially). (2) DESIGN (optional): replace the bare 'else 0' in step 39 with a documented Standard 0.20 default. Until then DPP is correctly scoped to BoKS only.",
    record: `${ORG}/lightning/r/Quote/0Q0WC000003AqV30AK/view`, recordLabel: "Quote 0Q0WC…AqV3 (FIM CCM lines $0 / 100%)",
  },
  {
    id: "E-04", pri: "P1", type: "ORG-CONFIG", cat: "Deal / Customer", ticket: "—",
    title: "Fortra-Originated partner deals get the CHANNEL band, not Non_Orig_*",
    step: "Apex PartnerPricingPrehook V1 (Deal_Type-blind) feeds PartnerDiscountPercent into V21",
    problem: "Fortra-Originated partner quote stamps PDP=15 (channel column); the SAME partner/product on a Channel-Originated quote also stamps PDP=15 → Deal_Type has zero effect. The Deal_Type→Non_Orig routing lives only in the dormant V2 prehook, and all 30 Partner_Pricing_Model rows have null Non_Orig_* columns.",
    fix: "(1) Wire the Deal_Type-aware PartnerPricingPrehookV2/ServiceV2 into the active plan (or backport the dealType/Non_Orig branch into V1). (2) Populate Non_Orig_* on the 30 PPMs (V2 falls back to 0% on null, so the backfill is required even after wiring).",
    record: `${ORG}/lightning/r/Quote/0Q0WC0000039bwH0AQ/view`, recordLabel: "Quote 0Q0WC…9bwH (Fortra-Orig PDP=15)",
  },
  {
    id: "G-08", pri: "P2", type: "ORG-CONFIG", cat: "Multi-Currency", ticket: "SC-3384",
    title: "Org FX rates corrupted to placeholder 1.0 (reporting/invoicing only)",
    step: "CurrencyType / DatedConversionRate config — pricing proc is decoupled & correct",
    problem: "6 of 11 non-USD currencies sit at 1.0 (ARS/CHF/GBP/ILS/JPY/NZD). DatedConversionRate shows ARS reset 1428.57→1.0 on 2026-02-11; any foreign txn since consolidates at face value. The pricing procedure is unaffected (reads Currency_Conversion_Formula__mdt; proven by G-01 PASS).",
    fix: "Reload CurrencyType.ConversionRate + forward-dated entries from the authoritative ARR table (ARS 666.67, CHF 0.8850, GBP 0.7874, ILS 3.6251, JPY 149.2537, NZD 1.6667); realign AUD/CAD/EUR; find and stop the automation that reset rates on 2026-02-11. No pricing-proc change.",
    record: `${ORG}/lightning/setup/ManageCurrencies/home`, recordLabel: "Setup → Manage Currencies (CurrencyType config)",
  },

  // ---------------- P0 (prior run) ----------------
  {
    id: "D-01", pri: "P0", type: "PROCEDURE", cat: "Pricing Mode", ticket: "SC-3390 / SC-3393",
    title: "Calculated-Mode multiplier ignored → Net = Base",
    step: "Step 14 Attribute Value Pricing – Calculated Mode",
    problem: "Formula reads context param Attribute_Multiplier_Pct__c. OrderItem HAS this field; QuoteLineItem does NOT → param resolves null → Base×null → IF-bridge falls back to Net=Base. Structural QLI/OI parity gap.",
    fix: "Add Attribute_Multiplier_Pct__c to QuoteLineItem + map it in the Quote context, OR change the formula/context to read the existing AttributeMultiplierPct__c on QLI.",
    record: `${ORG}/lightning/r/QuoteLineItem/0QLWC000003khGL4AY/view`, recordLabel: "QLI 0QLWC…khGL (Net=Base, mult null)",
  },
  {
    id: "D-03", pri: "P0", type: "ORG-CONFIG", cat: "Pricing Mode", ticket: "SC-3360",
    title: "Missing AttributeBasedAdjustment row → $0",
    step: "Steps 9-10 Attribute-Based Price / Attribute Discount Entries",
    problem: "No ABA row for {SFTP, OnPrem, Non-Production} → Net=0. Control {RAA, OnPrem, Non-Prod} prices 1575, proving the branch is live — the gap is a missing config row.",
    fix: "Add the ABA config row for {SFTP, OnPrem, Non-Production} (override 1575), or replace the 3-attribute-hash overrides with a single Server-Type adjustment; separately seed Source_List_Price from PBE list on no-match. Config/data only.",
    record: `${ORG}/lightning/r/QuoteLineItem/0QLWC000003khZh4AI/view`, recordLabel: "QLI 0QLWC…khZh (Net=0)",
  },
  {
    id: "E-03", pri: "P0", type: "PROCEDURE", cat: "Deal / Customer", ticket: "SC-3359",
    title: "One-Time/Perpetual partner net zeroed (not applied)",
    step: "Subscription Pricing — One-Time branch",
    problem: "PartnerDiscountPercent=15 resolved but NetUnitPrice=0 and TotalLineAmount=2008 (list). Expected Net=1706.8=2008×0.85. The TermDefined control nets correctly; the One-Time branch zeroes the net.",
    fix: "On the One-Time branch, write the discounted net to NetUnitPrice (mirror the TermDefined branch) instead of re-reading the undiscounted InputUnitPrice; preserve TotalLineAmount=list via a deliberate list seeder.",
    record: `${ORG}/lightning/r/Quote/0Q0WC000003FWCM0A4/view`, recordLabel: "Quote 0Q0WC…FWCM (Net=0, TLA=2008)",
  },
  {
    id: "F-02", pri: "P0", type: "PROCEDURE", cat: "Transaction Type", ticket: "SC-3350 / SC-3346",
    title: "Renewal-maintenance derived net never commits",
    step: "Steps 39-40 Derived Pricing Formula / NetUnitPrice Value Reset (renewal-maint node)",
    problem: "Renew subscription lines carry asset-derived net (PASS), but the BoKS renewal-maint line has Source_List=355 + COLACalc=3666.90 yet NetUnitPrice=null. Only 1/14 renewal RNM lines commits.",
    fix: "Renewal-maint line must carry a Type=Renew QuoteAction bound to the matching contributor asset so the derived committer writes NetUnitPrice — born-net at creation (architectural), not reprice-time.",
    record: `${ORG}/lightning/r/Quote/0Q0WC000003FR6D0AW/view`, recordLabel: "Quote 0Q0WC…FR6D (maint Net=null)",
  },
  {
    id: "F-04", pri: "P0", type: "PROCEDURE", cat: "Transaction Type", ticket: "SC-3354 / SC-3350 / SC-3349",
    title: "Headless renewal generation bypasses V21",
    step: "Flow Fortra_Create_Renewal_Quote V8 — never triggers Reprice-All at generation",
    problem: "Fresh headless renewal: Description=null, NetUnitPrice=0, COLACalc=null. After a manual Force-reprice the SAME lines populate — proving the V21 prehook chain never ran at generation.",
    fix: "Add a Reprice-All (Place pricingPref=Force) step to the renewal flow after initiateRenewal/Update_Quote, OR move COLA NetUnitPrice + line description onto an after-insert trigger/flow.",
    record: `${ORG}/lightning/r/Quote/0Q0WC000003FY2r0AG/view`, recordLabel: "Quote 0Q0WC…FY2r (Desc null, Net 0)",
  },
  {
    id: "F-05", pri: "P0", type: "PROCEDURE", cat: "Transaction Type", ticket: "SC-3354",
    title: "Multi-asset contract COLA collapses to 1 wrapper",
    step: "Steps 26-28 COLA Uplift on Renewal ← AssetContractQueryHelper.buildResults",
    problem: "4 assets on one contract → queryAssetContracts returns 1 wrapper (last asset); 3 missing. Root: Map<Id,Id> keyed by ContractId, so 4 ACR rows sharing one ContractId overwrite each other.",
    fix: "Key the map (and result emission) by AssetId so N assets on one contract yield N COLA wrappers.",
    record: `${ORG}/lightning/r/Contract/800WC00000PCpoMYAT/view`, recordLabel: "Contract 800WC…PCpo (4 assets → 1)",
  },
  {
    id: "F-07", pri: "P0", type: "PROCEDURE", cat: "Transaction Type", ticket: "SC-3346",
    title: "Order Reprice-All not idempotent — partner discount compounds",
    step: "Step 106 Stamp Base_Price from Net + steps 87-88 Partner Discount",
    problem: "Powertech net 301.75 → convert 256.49 → reprice1 218.01 → reprice2 157.52 (×0.85/pass). Step 106 seeds Base_Price FROM the already-discounted net, so each Reprice-All compounds 15%.",
    fix: "Order-context partner-discount base must derive from the pre-partner list/base (stable), not from the discounted NetUnitPrice; recompute partner net from an immutable base each pass (idempotent).",
    record: `${ORG}/lightning/r/Order/801WC00000knHDLYA2/view`, recordLabel: "Order 801WC…knHD (301.75→157.52)",
  },
  {
    id: "G-02", pri: "P0", type: "PROCEDURE", cat: "Multi-Currency", ticket: "SC-3384",
    title: "Configured EUR pricing currency-blind (USD row + FX)",
    step: "Total Price Mode / Attribute-Based Price composite key omits CurrencyIsoCode → steps 33-36 FX",
    problem: "CLSAAS Subtotal=1268.44=USD 1357.2×0.9346, not EUR ATPS native 1248.62 (+19.82 EUR overcharge). Seeded EUR rows are ignored; per-reprice values are non-deterministic.",
    fix: "Add CurrencyIsoCode to the composite key in AttributeVolumePricingPrehook (key construction, not the SOQL — that early-returns and keeps stale values) + add CurrencyIsoCode to the ABA decision table; don't double-FX-convert.",
    record: `${ORG}/lightning/r/Quote/0Q0WC0000036xy90AA/view`, recordLabel: "Quote 0Q0WC…6xy9 (EUR overcharge)",
  },
  {
    id: "G-03", pri: "P0", type: "PROCEDURE", cat: "Multi-Currency", ticket: "SC-3384",
    title: "EUR FX re-applied every reprice (non-idempotent)",
    step: "Steps 33-36 Currency Conversion (multiplies already-converted stored value)",
    problem: "FX re-applied each reprice: Unit 93460 → 81635 (×0.9346^n); ALE_Base 280380 → 262043 → 244906. USD baseline (E-02) stays stable → EUR-specific double-convert. Partner net not stamped.",
    fix: "Convert from an immutable USD list/base each pass (or guard FX to apply only when source ≠ already-converted) for idempotence; stamp partner net for non-UI-seeded lines.",
    record: `${ORG}/lightning/r/Quote/0Q0WC000003FYMD0A4/view`, recordLabel: "Quote 0Q0WC…FYMD (×0.9346^n)",
  },
  {
    id: "J-04", pri: "P0", type: "PROCEDURE", cat: "Derived / Maint", ticket: "SC-3350 / SC-3346",
    title: "Derived COLA renewal net commits only on the QA-bound line",
    step: "Step 26 COLA Uplift Net on Renewal + COLAUpliftPrehook net-seed guard",
    problem: "Only the Renew-QA-bound RRM line commits 67.38. A QA-less line → Net=0; another → frozen fossil 60.64. UnitPrice computed both, but the net never commits. 1/14 commits org-wide.",
    fix: "Attach a Type=Renew QuoteAction + matching RRM contributor asset to every renewal-maint line so ItemPricingSource=LastTransaction materializes and step 26 fires. Born-net at creation.",
    record: `${ORG}/lightning/r/Quote/0Q0WC0000037XvB0AU/view`, recordLabel: "Quote 0Q0WC…7XvB (QA-less Net 0)",
  },
  {
    id: "J-09", pri: "P0", type: "ORG-CONFIG", cat: "Derived / Maint", ticket: "SC-3372 / M5-PBEDP",
    title: "Uncovered IsDerived PBE → silent null net",
    step: "DerivedProductsNativePull — missing PriceBookEntryDerivedPrice row",
    problem: "Maint NetUnitPrice=null, ListPrice=0, silent (isSuccess=true, no error). Maint PBE has 0 PBEDP rows; org-wide ~1889 IsDerived PBEs vs ~201 PBEDP (~89% uncovered).",
    fix: "Backfill PriceBookEntryDerivedPrice for the uncovered PBEs (M5-PBEDP 476-row HICONF crosswalk staged), OR remove the native DerivedProducts element after confirming the MTD formula suffices; surface a clear error instead of silent null.",
    record: `${ORG}/lightning/r/Quote/0Q0WC000003FZ6z0AG/view`, recordLabel: "Quote 0Q0WC…FZ6z (Net null silent)",
  },
  {
    id: "J-10", pri: "P0", type: "PROCEDURE", cat: "Derived / Maint", ticket: "SC-3346",
    title: "EUR + COLA + partner derived-renewal cell → $0",
    step: "Derived Pricing Formula + COLA Uplift Net on Renewal (two paths mutually exclude derived)",
    problem: "Net=0 stable across 3 reprices; COLACalc=3666.90 computed once but never assigned; FX then 0×0.9346=0. Expected ~3427 EUR. The COLA-net step is gated DerivedPricingAttribute=false, excluding derived.",
    fix: "Drop gate 3 (DerivedPricingAttribute=false) on COLA Uplift Net on Renewal so derived lines also get NetUnitPrice=COLACalculatedPrice__c, OR set the Derived Pricing Formula renewal branch to COLACalculatedPrice__c when COLA% IsNotNull.",
    record: `${ORG}/lightning/r/Quote/0Q0WC000003FZN70AO/view`, recordLabel: "Quote 0Q0WC…FZN7 (Net 0)",
  },
  {
    id: "K-01", pri: "P0", type: "PROCEDURE", cat: "Edge Cases", ticket: "SC-3441",
    title: "Fresh cancel line aborts at Stamp Base Filter",
    step: "Stamp Base Filter (NetUnitPrice>0 not null-safe) + dropped V18 cancel-seed",
    problem: "Fresh cancel QLI (CancelNetUnitPrice__c=15000, NetUnitPrice=null) → Force-reprice ABORTS SF-Pricing-00006; TotalPrice stays 0. Only a pre-seeded line passes (filter's >0 already true). The prior 'RESOLVED' verification used a pre-seeded line and is invalid.",
    fix: "Re-add the V18 cancel seed (CancelNetUnitPrice__c IsNotNull AND NetUnitPrice IsNull → NetUnitPrice+InputUnitPrice) BEFORE Stamp Base Filter, and/or make the filter null-safe (NetUnitPrice IsNotNull AND >0, or a Cancel/qty<0 bypass).",
    record: `${ORG}/lightning/r/Quote/0Q0WC000003FZ3l0AG/view`, recordLabel: "Quote 0Q0WC…FZ3l (abort SF-Pricing-00006)",
  },
  {
    id: "K-02", pri: "P0", type: "PROCEDURE", cat: "Edge Cases", ticket: "SC-3346 / SC-3372",
    title: "Missing-contributor derived line silently $0",
    step: "Stamp Contributor Base + Derived Pricing Formula fallback (no surfacing)",
    problem: "Maint-only quote, lone derived line, no license on cart → NetUnitPrice=null, ValidationResult=null, header→$0 silently. Control J-02 (license present) prices 71/124.25 — only difference is contributor presence.",
    fix: "Add a MissingContributor surfacing branch — when a derived line resolves no priced contributor (Base/Pre_Partner/InputUnitPrice all null/0), set ValidationResult=MissingContributor or emit a place-level error instead of committing $0.",
    record: `${ORG}/lightning/r/Quote/0Q0WC000003FZ5N0AW/view`, recordLabel: "Quote 0Q0WC…FZ5N (silent $0)",
  },
  {
    id: "K-03", pri: "P0", type: "PROCEDURE", cat: "Edge Cases", ticket: "SC-3366 / SC-3447",
    title: "Reprice-All Apex CPU blowup on large orders",
    step: "Order before-save flow 'Sync Status' re-fires per RLM place-engine chunk",
    problem: "Mid orders PASS; large (838/847 lines) FAIL with Apex CPU 10,323→14,493 ms (>10,000). 2003-line → RLM cap. Binding limit is CPU, not a V21 SOQL/DML blowup.",
    fix: "Bulk-safe the per-chunk Order before-save flow (fire once per commit + header-scoped fast-exit), OR raise RLM chunk granularity / move reprice to an async batched context for >~600-line orders.",
    record: `${ORG}/lightning/r/Order/801WC00000hKGY0YAO/view`, recordLabel: "Order 00088127 (CPU >10,000ms)",
  },
  {
    id: "K-04", pri: "P0", type: "PROCEDURE", cat: "Edge Cases", ticket: "SC-3347 / SC-3374 / SC-3143",
    title: "Workday extendedAmount maps LIST, not net",
    step: "MuleSoft extendedAmount mapping ← TotalLineAmount (list) vs net contract amount",
    problem: "extendedAmount=3150 (LIST/TLA) vs currentContractAmount=2835 (NET) → Workday rejects 'Contract Amount must equal Contract Line Amount'. 8 live orders fail in 60d; 0 of this error class has ever reached Workday Success.",
    fix: "Mule maps contract-line extendedAmount ← OrderItem.NetTotalPrice (= NetUnitPrice × Qty) instead of TotalLineAmount. Regression-safe (no-op where net==list). Mule-owned.",
    record: `${ORG}/lightning/r/Order/801WC00000kML51YAG/view`, recordLabel: "Order 00095381 (3150 vs 2835)",
  },
];

const TYPE_STYLE = {
  PROCEDURE: { accent: "#6366f1", chipBg: "#eef2ff", chipFg: "#4338ca", label: "PROCEDURE" },
  "ORG-CONFIG": { accent: "#f59e0b", chipBg: "#fffbeb", chipFg: "#b45309", label: "ORG-CONFIG" },
};
const PRI_STYLE = {
  P0: { bg: "#fee2e2", fg: "#b91c1c" },
  P1: { bg: "#ffedd5", fg: "#c2410c" },
  P2: { bg: "#e5e7eb", fg: "#374151" },
};

function Chip({ bg, fg, children, mono }) {
  return (
    <span style={{
      background: bg, color: fg, fontSize: 11, fontWeight: 700, padding: "2px 8px",
      borderRadius: 999, letterSpacing: 0.3, whiteSpace: "nowrap",
      fontFamily: mono ? "ui-monospace, SFMono-Regular, Menlo, monospace" : "inherit",
    }}>{children}</span>
  );
}

function DefectCard({ d }) {
  const t = TYPE_STYLE[d.type];
  const p = PRI_STYLE[d.pri];
  return (
    <div style={{
      borderRadius: 14, background: "#fff", border: "1px solid #e5e7eb",
      borderLeft: `6px solid ${t.accent}`, boxShadow: "0 1px 3px rgba(0,0,0,0.06)",
      padding: "16px 18px", display: "flex", flexDirection: "column", gap: 10,
    }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, flexWrap: "wrap" }}>
        <span style={{
          fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", fontSize: 18,
          fontWeight: 800, color: "#111827", background: "#f3f4f6", padding: "3px 10px", borderRadius: 8,
        }}>{d.id}</span>
        <Chip bg={p.bg} fg={p.fg}>{d.pri}</Chip>
        <Chip bg={t.chipBg} fg={t.chipFg}>{t.label}</Chip>
        <Chip bg="#f1f5f9" fg="#475569">{d.cat}</Chip>
        {d.ticket !== "—" && <Chip bg="#ecfeff" fg="#0e7490" mono>{d.ticket}</Chip>}
      </div>

      <div style={{ fontSize: 16, fontWeight: 700, color: "#111827", lineHeight: 1.3 }}>{d.title}</div>
      <div style={{ fontSize: 12, color: "#6b7280", fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace" }}>
        ⚙ {d.step}
      </div>

      <div>
        <div style={{ fontSize: 11, fontWeight: 800, color: "#b91c1c", letterSpacing: 0.5, marginBottom: 3 }}>PROBLEM</div>
        <div style={{ fontSize: 14, color: "#374151", lineHeight: 1.5 }}>{d.problem}</div>
      </div>

      <div style={{ background: "#f0fdf4", border: "1px solid #bbf7d0", borderRadius: 10, padding: "10px 12px" }}>
        <div style={{ fontSize: 11, fontWeight: 800, color: "#15803d", letterSpacing: 0.5, marginBottom: 3 }}>
          RESOLUTION <span style={{ fontWeight: 600, color: "#6b7280" }}>(proposed — not applied)</span>
        </div>
        <div style={{ fontSize: 14, color: "#14532d", lineHeight: 1.5 }}>{d.fix}</div>
      </div>

      <a href={d.record} target="_blank" rel="noreferrer" style={{
        display: "inline-flex", alignItems: "center", gap: 8, alignSelf: "flex-start",
        marginTop: 2, fontSize: 13, fontWeight: 700, color: "#fff", textDecoration: "none",
        background: t.accent, padding: "8px 14px", borderRadius: 9,
      }}>
        🔗 Open record
        <span style={{ fontWeight: 500, opacity: 0.92 }}>· {d.recordLabel}</span>
      </a>
    </div>
  );
}

export default function V21Defects() {
  const [type, setType] = useState("ALL");
  const [pri, setPri] = useState("ALL");
  const [q, setQ] = useState("");

  const filtered = useMemo(() => {
    return DEFECTS.filter((d) =>
      (type === "ALL" || d.type === type) &&
      (pri === "ALL" || d.pri === pri) &&
      (q === "" || (d.id + d.title + d.cat + d.ticket + d.problem + d.fix).toLowerCase().includes(q.toLowerCase()))
    ).sort((a, b) => a.pri.localeCompare(b.pri) || a.id.localeCompare(b.id));
  }, [type, pri, q]);

  const counts = useMemo(() => ({
    total: DEFECTS.length,
    proc: DEFECTS.filter((d) => d.type === "PROCEDURE").length,
    cfg: DEFECTS.filter((d) => d.type === "ORG-CONFIG").length,
    p0: DEFECTS.filter((d) => d.pri === "P0").length,
    p1p2: DEFECTS.filter((d) => d.pri !== "P0").length,
  }), []);

  const btn = (active) => ({
    padding: "7px 13px", borderRadius: 8, fontSize: 13, fontWeight: 700, cursor: "pointer",
    border: `1px solid ${active ? "#111827" : "#d1d5db"}`,
    background: active ? "#111827" : "#fff", color: active ? "#fff" : "#374151",
  });

  return (
    <div style={{
      maxWidth: 980, margin: "0 auto", padding: "28px 20px 60px",
      fontFamily: "system-ui, -apple-system, Segoe UI, Roboto, sans-serif",
      background: "#f9fafb", color: "#111827",
    }}>
      <header style={{ marginBottom: 18 }}>
        <div style={{ fontSize: 13, fontWeight: 700, color: "#6366f1", letterSpacing: 0.6 }}>
          FORTRA UAT · PRICING PROCEDURE V21 · VALIDATION
        </div>
        <h1 style={{ fontSize: 28, fontWeight: 800, margin: "4px 0 6px" }}>Defect Board — 23 reportable findings</h1>
        <div style={{ fontSize: 14, color: "#6b7280" }}>
          All 104 scenarios validated · <b style={{ color: "#16a34a" }}>64 PASS</b> ·{" "}
          <b style={{ color: "#dc2626" }}>23 FAIL</b> · <b style={{ color: "#6b7280" }}>17 BLOCKED</b>.
          Every FAIL is smoke-tested on real data; fixes are <b>proposed, not applied</b>.
        </div>

        <div style={{ display: "flex", gap: 10, flexWrap: "wrap", marginTop: 14 }}>
          {[
            ["Total defects", counts.total, "#111827"],
            ["Procedure", counts.proc, "#6366f1"],
            ["Org-config", counts.cfg, "#f59e0b"],
            ["P0", counts.p0, "#dc2626"],
            ["P1 / P2", counts.p1p2, "#c2410c"],
          ].map(([label, n, c]) => (
            <div key={label} style={{
              background: "#fff", border: "1px solid #e5e7eb", borderRadius: 12,
              padding: "10px 16px", minWidth: 92, textAlign: "center",
            }}>
              <div style={{ fontSize: 24, fontWeight: 800, color: c }}>{n}</div>
              <div style={{ fontSize: 11, color: "#6b7280", fontWeight: 600 }}>{label}</div>
            </div>
          ))}
        </div>
      </header>

      <div style={{
        position: "sticky", top: 0, zIndex: 5, background: "#f9fafb", paddingTop: 8,
        paddingBottom: 12, display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center",
        borderBottom: "1px solid #e5e7eb", marginBottom: 16,
      }}>
        <div style={{ display: "flex", gap: 6 }}>
          {["ALL", "PROCEDURE", "ORG-CONFIG"].map((v) => (
            <button key={v} style={btn(type === v)} onClick={() => setType(v)}>{v === "ALL" ? "All types" : v}</button>
          ))}
        </div>
        <div style={{ display: "flex", gap: 6 }}>
          {["ALL", "P0", "P1", "P2"].map((v) => (
            <button key={v} style={btn(pri === v)} onClick={() => setPri(v)}>{v === "ALL" ? "All pri" : v}</button>
          ))}
        </div>
        <input
          value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search id / ticket / text…"
          style={{
            flex: "1 1 180px", minWidth: 160, padding: "8px 12px", borderRadius: 8,
            border: "1px solid #d1d5db", fontSize: 13, outline: "none",
          }}
        />
        <span style={{ fontSize: 13, color: "#6b7280", fontWeight: 600 }}>{filtered.length} shown</span>
      </div>

      <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
        {filtered.map((d) => <DefectCard key={d.id} d={d} />)}
        {filtered.length === 0 && (
          <div style={{ textAlign: "center", color: "#9ca3af", padding: 40 }}>No defects match the filter.</div>
        )}
      </div>

      <footer style={{ marginTop: 28, fontSize: 12, color: "#9ca3af", textAlign: "center" }}>
        Source: Data/pricing-v21-validation/V21_VALIDATION_RESULTS.md · Active proc Rev_Mgmt_Default_Pricing_Procedure V21 · Validation only — no deploys/edits.
      </footer>
    </div>
  );
}
