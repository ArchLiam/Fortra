import React from "react";

// Fortra RCA Quote-to-Order — E2E Test Executive Summary
// Org FortraUAT · Pricing procedure V14 · Workday/MuleSoft integration excluded by design.
const RESULTS = [
  {
    "id": "NB-PERP",
    "domain": "New-business pricing",
    "title": "Perpetual/License net pricing \u2014 List x (1-partner) x (1-disc)",
    "status": "pass",
    "severity": "none",
    "known": false,
    "ticket": "SC-3359",
    "actual": "All Perpetual lines tested match the formula exactly. A live Force reprice (configurationPref Skip) of Draft quote 00780964 produced and held NetUnitPrice 301.75 (List 355 x 0.85). Baseline quote 00781106 held net=list=3675 with no phantom discount. Read-only committed lines confirm the partner+disc"
  },
  {
    "id": "NB-MAINT",
    "domain": "New-business pricing",
    "title": "Maintenance derived pricing + auto-add first-year maintenance (SC-3346)",
    "status": "fail",
    "severity": "high",
    "known": true,
    "ticket": "SC-3372, SC-3346, SC-3403",
    "actual": "On Draft quote 00307854 (GS-GSE-RNM-* New Maintenance) and Draft quote 00407375 (GS-GSE-RRM-* Renewal Maintenance), a Force reprice via the Place Sales Transaction harness returned isSuccess:true / CalculationStatus=CompletedWithPricing, and the contributing perpetual lines priced correctly (e.g. GS"
  },
  {
    "id": "NB-SVC",
    "domain": "New-business pricing: Services pricing",
    "title": "Services-only USD new-business quote prices at catalog (no partner/regional adjustment) - PASS",
    "status": "pass",
    "severity": "none",
    "known": false,
    "ticket": "SC-3384",
    "actual": "After Force-reprice with configurationPref Skip (isSuccess:true), both Services lines committed exactly the expected values: NetUnitPrice=15000=ListPrice, NetTotalPrice=TotalLineAmount=30000, Regional_NetUnit_Price__c and PrehookRSNetUnitPrice__c both null (no regional adjustment, correct for US). H"
  },
  {
    "id": "NB-HW",
    "domain": "New-business pricing: Hardware pricing",
    "title": "Hardware attribute pricing (Powertech pGroup/userTier/systemType): engine wired and formula correct, but inactive P5 picklist breaks reprice, no Draft+priced HW quote exists to prove non-1.0 multiplier, and audit fields never persist",
    "status": "partial",
    "severity": "medium",
    "known": false,
    "ticket": "",
    "actual": "The discovery digest's premise ('Hardware = N/A, no Family=Hardware Product2') is literally true but misses the real mechanism: hardware pricing IS implemented and live as HardwareAttributePricingPrehook v3.0 (Marc DeBrey, Jan 2026), wired into the active V14 procedure. (1) ENGINE WIRED + FIRES: rep"
  },
  {
    "id": "NB-TIER",
    "domain": "New-business pricing",
    "title": "Tiered / attribute-volume pricing (SC-3390): tier resolves first-click, but committed net is $0",
    "status": "fail",
    "severity": "high",
    "known": true,
    "ticket": "SC-3384, SC-3390",
    "actual": "SC-3390 first-click tier resolution WORKS (volume hydrated and tier matched on the first reprice pass, confirmed twice). BUT the committed net is $0 on all three lines: the prehook correctly wrote Base_Price__c + Attribute_Price_Mode__c to context (CLSACH 1957.20/'Total Price'; CLSAAS 2180/'Unit Pri"
  },
  {
    "id": "NB-BUNDLE",
    "domain": "New-business pricing",
    "title": "Bundle / product configuration rule pricing",
    "status": "partial",
    "severity": "high",
    "known": true,
    "ticket": "SC-3384",
    "actual": "USD bundle 00307075 PASSES exactly: reprice isSuccess=true, ListPrice 5000, NetUnitPrice 5000, NetTotalPrice 50000, Subtotal=TotalPrice=GrandTotal=ALE=50000, Discount=0, CalculationStatus=CompletedWithPricing, 1 line preserved. CAD bundle 00437346: (a) reprice was BLOCKED by Quote VR Quote_BillToPla"
  },
  {
    "id": "RN-LIC",
    "domain": "Renewal pricing",
    "title": "Renewal license COLA uplift",
    "status": "pass",
    "severity": "none",
    "known": false,
    "ticket": "SC-3404",
    "actual": "Reprice via Place Sales Transaction (configurationPref Skip) returned isSuccess:true, CalculationStatus=CompletedWithPricing, 2 lines preserved. PIA-PIA-RRM-PIAM committed: COLACalculatedPrice__c=60.64 (exact match to formula, re-derived on reprice => COLA prehook ran), COLA%=7.85, NetUnitPrice=54.5"
  },
  {
    "id": "RN-MAINT",
    "domain": "Renewal pricing",
    "title": "Renewal maintenance COLA net commits 0 / 54.58 / 60.64 instead of expected 67.38 (SC-3404)",
    "status": "fail",
    "severity": "high",
    "known": true,
    "ticket": "SC-3404",
    "actual": "All four SC-3404 renewal-maintenance lines commit NetUnitPrice != 67.38. After a fresh sanctioned Force reprice (configurationPref Skip, isSuccess:true) of canary quote 00781109, its maintenance line STILL commits NetUnitPrice=60.64 (NetTotalPrice=60.64) while COLACalculatedPrice__c=67.38 \u2014 the corr"
  },
  {
    "id": "RN-SUB",
    "domain": "Renewal pricing",
    "title": "Renewal subscription pricing \u2014 catalog net + partner subscription margin applied correctly and stably on reprice",
    "status": "pass",
    "severity": "none",
    "known": false,
    "ticket": "SC-3404",
    "actual": "All three Draft renewal quotes repriced isSuccess:true via the sanctioned Place Sales Transaction harness (configurationPref Skip) and settled CompletedWithPricing; every subscription line matched the expected formula exactly. (1) 00781053 (PARTNER renewal, Billing_Partner__c=AB Test Partner Account"
  },
  {
    "id": "AMEND",
    "domain": "Renewal pricing",
    "title": "Amendment quote pricing",
    "status": "pass",
    "severity": "none",
    "known": false,
    "ticket": "SC-3372",
    "actual": "Repriced Draft Amendment quote 00307854 (0Q0WC0000028GmQ0AU, 20 lines, USD, Quote_Type__c=Amendment) via the Skip harness -> isSuccess:true, salesTransactionId returned, errorResponse empty. Reprice was idempotent and non-destructive: line count 20 -> 20, identical prices to pre-reprice baseline. Pe"
  },
  {
    "id": "MOD-PART12",
    "domain": "Pricing modifiers",
    "title": "Partner discount 12% model (renewal-maintenance lines)",
    "status": "fail",
    "severity": "high",
    "known": true,
    "ticket": "SC-3404, SC-3346, SC-3403",
    "actual": "The 12% partner discount is never multiplied into the committed net. Live PartnerNetPricePosthook.buildRenewalMaintenanceColaUpdate sets NetUnitPrice = colaNet (COLA-only, line 859) and stamps PartnerDiscountPercent only as a passive metadata attribute (lines 868-872) - it does not reduce net. Worse"
  },
  {
    "id": "MOD-PART15",
    "domain": "Pricing modifiers",
    "title": "Partner discount 15% model",
    "status": "pass",
    "severity": "none",
    "known": false,
    "ticket": "SC-3359",
    "actual": "After a Force reprice via the Place Sales Transaction Skip harness (isSuccess:true, errorResponse:[]), Draft USD quote 00780964 (0Q0WC000003735t0AA) line L1 PIA-PIA-NRPS-PIAP (Perpetual) committed: ListPrice 355, NetUnitPrice 301.75, NetTotalPrice 301.75, TotalLineAmount 301.75, PartnerDiscountPerce"
  },
  {
    "id": "MOD-QDISC",
    "domain": "Pricing modifiers",
    "title": "Quote-level discount (% and amount; equal and proportionate distribution)",
    "status": "partial",
    "severity": "medium",
    "known": false,
    "ticket": "",
    "actual": "The header discount is captured on the Quote but is never applied or distributed by the active V14 pricing procedure. After a sanctioned Force reprice (configurationPref Skip), every line stays at full list (NetUnitPrice == ListPrice), TotalAdjustmentAmount = 0, header Discount = 0, Total_Discount_A"
  },
  {
    "id": "MOD-LDISC",
    "domain": "Pricing modifiers",
    "title": "Line-level (partner) + discretionary discount on Quote lines",
    "status": "fail",
    "severity": "high",
    "known": true,
    "ticket": "SC-3359",
    "actual": "Discretionary-only is CORRECT (00781070: Secure Collaboration list25000 x 0.80 = net 20000 on both Subscription lines). Combined partner+discretionary is NON-DETERMINISTIC and DEFECTIVE: two identical-product quotes on the SAME partner account (AB Test Partner Account, Guaranteed Margin model Sub18/"
  },
  {
    "id": "MOD-CUR-AUD",
    "domain": "Pricing modifiers",
    "title": "Multi-currency AUD (rate 1.52) net price not scaled by conversion rate",
    "status": "fail",
    "severity": "high",
    "known": true,
    "ticket": "SC-3384",
    "actual": "ListPrice correctly sourced the AUD-currency PricebookEntry (142880) but the net channel committed the bare USD value: UnitPrice=NetUnitPrice=NetTotalPrice=TotalLineAmount=94000 (NOT x1.52). Header Subtotal=TotalPrice=GrandTotal=ALE__c=94000. The AUD net price is understated by 48,880 AUD (34.2%); t"
  },
  {
    "id": "MOD-CUR-EUR",
    "domain": "Pricing modifiers",
    "title": "Multi-currency EUR (rate 0.92) configured/attribute pricing uses USD values",
    "status": "fail",
    "severity": "high",
    "known": true,
    "ticket": "SC-3384",
    "actual": "Catalog LIST prices ARE correctly EUR-converted in the PricebookEntry/ListPrice field (AAMP 2898=3150x0.92, CLSAAS 2005.6=2180x0.92, BESEPB 758.08=824x0.92, VMA 460=500x0.92), but every PRICED channel carries the raw USD value (currency-blind): BESEPB NetUnitPrice=824 (USD value, EXCEEDS EUR list 75"
  },
  {
    "id": "MOD-CUR-USDONLY",
    "domain": "Pricing modifiers",
    "title": "Non-USD configured product uses USD values (SC-3384) + JPY 1.0-rate corruption",
    "status": "fail",
    "severity": "high",
    "known": true,
    "ticket": "SC-3384",
    "actual": "AAMP (Perpetual, ABA-driven, 0 tier-storage rows) on EUR quote 00780956 committed UnitPrice=3150 (USD list, NOT the EUR catalog 2898) and NetUnitPrice=1575 (USD ABA value, currency-blind). Reprice via Place Sales Transaction (Skip) re-committed the identical USD-derived values, proving live engine b"
  },
  {
    "id": "MOD-REGION",
    "domain": "Pricing modifiers",
    "title": "Regional services pricing (Italy 0.64 multiplier, CEILING/5)",
    "status": "fail",
    "severity": "high",
    "known": false,
    "ticket": "SC-3393",
    "actual": "The prehook fires and computes the regional price correctly and writes it to context successfully (updateContextAttributes returns isSuccess=true), but the V14 pricing procedure does NOT reconcile that context output back onto the persisted QuoteLineItem. On a fresh Force reprice of AU quote 0078110"
  },
  {
    "id": "TOT-CONSIST",
    "domain": "Totals & rollups",
    "title": "NetUnitPrice/NetTotal/Subtotal/GrandTotal consistency on a multi-line quote",
    "status": "partial",
    "severity": "medium",
    "known": true,
    "ticket": "SC-3345",
    "actual": "All core money relationships hold EXACTLY on both repriced quotes (16-line USD 00340940 and 3-line discounted USD 00781070), AND per-line NetUnitPrice*Quantity = NetTotalPrice, AND the standard Discount% and category rollups reconcile. The ONE failing relationship is Total_Discount_Amount__c: on dis"
  },
  {
    "id": "TOT-ALE",
    "domain": "Totals & rollups",
    "title": "ALE formula + Services category aggregate + stale-aggregate (SC-3345) validation on Draft quotes 00781106 and 00437471",
    "status": "pass",
    "severity": "none",
    "known": false,
    "ticket": "SC-3345",
    "actual": "Quote A (00781106) after sanctioned Force/Skip reprice (isSuccess:true, 2 lines preserved, same Ids/prices): Subtotal=18675, TotalPrice=18675, GrandTotal=18675, ALE__c=18675, Annualized_License_Equivalent_Base__c=18675, Total_Contract_Value_TCV__c=18675, Discount=0, Total_Services__c=15000, Total_So"
  },
  {
    "id": "QO-CONVERT",
    "domain": "Quote-to-Order",
    "title": "Convert Draft quote to Order (non-activating) + field mapping (Bill/Ship, dates, Source_List_Price)",
    "status": "pass",
    "severity": "none",
    "known": false,
    "ticket": "SC-3384",
    "actual": "All conversion mechanics validated against existing converted Draft orders (a fresh headless convert is blocked within guardrails: screen flow requires Quote.Status='Accepted' which is do-not-touch, and the flag path needs RLM-blocked Quote DML). Header field mapping is CORRECT on order 00095394 vs "
  },
  {
    "id": "QO-PRICEPARITY",
    "domain": "Quote-to-Order",
    "title": "Order pricing parity vs source quote (net carries correctly)",
    "status": "fail",
    "severity": "high",
    "known": true,
    "ticket": "SC-3359",
    "actual": "PARTIAL PARITY. Clean baseline order 00095477 (single Subscription line, ES-CEP-RSL-ACTIDB) is in perfect parity: Quote Net 94000 == Order Net 94000, Quote totals 94000 == Order TotalAmount 94000. BUT order 00095394 (Perpetual + derived Maintenance) BREAKS parity on the Perpetual line: quote QLI 'Vn"
  },
  {
    "id": "QO-DECOMP",
    "domain": "Quote-to-Order",
    "title": "Order line decomposition / maintenance split \u2014 Source_List_Price carry-through and parent\u2192derived-maintenance linkage",
    "status": "pass",
    "severity": "none",
    "known": false,
    "ticket": "SC-3346, SC-3347, SC-3210, SC-3404",
    "actual": "All decomposition invariants hold on the live committed Draft orders. Maintenance split (Order 00095394, CompletedWithPricing): license FIM-FML-NRPS-VEMEVP List 34750 / Unit 29537.5 / Net 25106.875; derived line FIM-FIM-RNM-VEMENM 'VnE Manager Ev-NewMaintenance' carries Source_List_Price__c=34750 (="
  },
  {
    "id": "VAL-REQ",
    "domain": "Validation",
    "title": "Required-fields-for-submission completeness (SC-3338) \u2014 OrderSubmissionValidator enforces the 25 active Order_Submit_Validation__mdt rules",
    "status": "pass",
    "severity": "none",
    "known": false,
    "ticket": "SC-3338",
    "actual": "All three Draft orders validated exactly as the rule config predicts. (1) 00095493 (Accenture Song, fully populated): hasErrors=false, errorCount=0 -> PASS. (2) 00095497 (AB Test Account): hasErrors=true, errorCount=2 -> exactly 'Account Phone' + 'Account D&B DUNS'; field-state query confirmed those"
  },
  {
    "id": "VAL-SUBMIT",
    "domain": "Validation",
    "title": "Order submission required-field validation (SC-3291) \u2014 OrderSubmissionValidator + Order_Submit_Validation__mdt + Fortra_Order_Submission_Check flow v13",
    "status": "pass",
    "severity": "none",
    "known": false,
    "ticket": "SC-3291",
    "actual": "EXACT MATCH. Ran OrderSubmissionValidator.validate via read-only anonymous Apex against both orders (no DML, no platform event). Order 00095481 (Order Complete): hasErrors=false, errorCount=0. Order 00095497 (Draft): hasErrors=true, errorCount=2 \u2014 \"Account Phone is required...\" and \"Account D&B DUNS"
  },
  {
    "id": "CFG-AUTOMAINT",
    "domain": "Configuration",
    "title": "Auto-add first-year maintenance config rule fires on add",
    "status": "pass",
    "severity": "low",
    "known": false,
    "ticket": "SC-3372",
    "actual": "PASS on the auto-add assertion. 99 active \"Year 1 Maintenance Sku added to ... Perpetual\" rules exist, all with actionType=AutoAdd; 98/99 correctly gated on QuoteTypeText__c='New'; all 95 unique target maintenance products resolve to active Product2 records. Proven end-to-end: New quote 00780934 -> "
  },
  {
    "id": "DOC-PDF",
    "domain": "DocGen",
    "title": "Quote PDF generation: pricing + line descriptions content (SC-3335/3349)",
    "status": "pass",
    "severity": "none",
    "known": false,
    "ticket": "SC-3335, SC-3349",
    "actual": "PASS. Pipeline fully active and correctly wired; live transform maps Amount<-net, Subtotal<-list, GrandTotal<-net; descriptions render verbatim with correct glyphs; committed pricing internally consistent. The one apparent Amount=list value in a downloaded PDF is a stale-doc artifact (that PDF was g"
  }
];

const HEALTH = {
  verdict: "CONDITIONAL",
  color: "#b8860b",
  message:
    "Core happy-path pricing, quote-to-order conversion, order decomposition, submission validation and DocGen all PASS. " +
    "Failures concentrate in KNOWN open defects (multi-currency SC-3384, renewal-maintenance SC-3404, partner-net SC-3359, derived-PBE SC-3372, totals SC-3345). " +
    "One new un-ticketed regression (MOD-REGION: regional price computed but not committed by V14). Integration excluded by design.",
};

const STC = { pass:"#1a7f37", fail:"#cf222e", partial:"#9a6700", blocked:"#57606a", skipped:"#57606a", "out-of-scope":"#57606a" };
const STBG = { pass:"#dafbe1", fail:"#ffebe9", partial:"#fff8c5", blocked:"#eaeef2", skipped:"#eaeef2", "out-of-scope":"#eaeef2" };
const SEVC = { critical:"#cf222e", high:"#bc4c00", medium:"#9a6700", low:"#57606a", none:"#1a7f37" };

function Pill({ status, mini }) {
  return (
    <span style={{ display:"inline-block", padding: mini?"1px 7px":"2px 9px", borderRadius:20,
      fontSize: mini?10:11, fontWeight:700, color:STC[status], background:STBG[status] }}>
      {String(status).toUpperCase()}
    </span>
  );
}

export default function ExecutiveSummary() {
  const total = RESULTS.length;
  const count = (s) => RESULTS.filter((r) => r.status === s).length;
  const nPass = count("pass"), nFail = count("fail"), nPartial = count("partial");
  const nKnown = RESULTS.filter((r) => r.known).length;
  const nReg = RESULTS.filter((r) => r.status === "fail" && !r.known).length;
  const domains = [...new Set(RESULTS.map((r) => r.domain))];
  const crit = RESULTS.filter((r) => ["critical","high"].includes(r.severity) && ["fail","partial"].includes(r.status));
  const regs = RESULTS.filter((r) => r.status === "fail" && !r.known);
  const known = RESULTS.filter((r) => r.known);

  const card = { background:"#fff", border:"1px solid #d0d7de", borderRadius:10, padding:16 };
  const kpi = { ...card, textAlign:"center", padding:14 };

  return (
    <div style={{ fontFamily:"-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial,sans-serif",
      maxWidth:1100, margin:"0 auto", padding:"28px 20px 60px", color:"#1f2328", background:"#f6f8fa" }}>
      <h1 style={{ margin:"0 0 4px", fontSize:24 }}>Fortra RCA — Quote-to-Order E2E Test · Executive Summary</h1>
      <div style={{ color:"#57606a", fontSize:14 }}>
        Org <b>FortraUAT</b> · Pricing procedure <b>V14</b> · {total} scenarios · Workday/MuleSoft integration <b>excluded by design</b>
      </div>

      <div style={{ margin:"18px 0", padding:"14px 18px", borderRadius:10, borderLeft:`6px solid ${HEALTH.color}`, ...card }}>
        <div style={{ fontWeight:700, color:HEALTH.color, fontSize:15, letterSpacing:.5 }}>OVERALL HEALTH: {HEALTH.verdict}</div>
        <div>{HEALTH.message}</div>
      </div>

      <div style={{ display:"grid", gridTemplateColumns:"repeat(6,1fr)", gap:12, margin:"18px 0" }}>
        {[["Scenarios",total,"#1f2328"],["Pass",nPass,"#1a7f37"],["Fail",nFail,"#cf222e"],
          ["Partial",nPartial,"#9a6700"],["Known-issue",nKnown,"#0969da"],["New regression",nReg,"#cf222e"]]
          .map(([l,n,c]) => (
          <div key={l} style={kpi}>
            <div style={{ fontSize:28, fontWeight:700, color:c }}>{n}</div>
            <div style={{ fontSize:11, textTransform:"uppercase", letterSpacing:.5, color:"#57606a", marginTop:4 }}>{l}</div>
          </div>
        ))}
      </div>

      <table style={{ width:"100%", borderCollapse:"collapse", background:"#fff", border:"1px solid #d0d7de", borderRadius:10, overflow:"hidden", fontSize:13 }}>
        <thead><tr>{["ID","Scenario","Status","Severity","Known-issue / ticket"].map((h) => (
          <th key={h} style={{ textAlign:"left", padding:"10px 12px", background:"#f6f8fa", borderBottom:"1px solid #d0d7de",
            fontSize:11, textTransform:"uppercase", letterSpacing:.4, color:"#57606a" }}>{h}</th>))}</tr></thead>
        <tbody>
          {domains.map((d) => (
            <React.Fragment key={d}>
              <tr><td colSpan={5} style={{ background:"#eef2ff", fontWeight:700, fontSize:12, textTransform:"uppercase",
                letterSpacing:.5, color:"#3538cd", padding:"8px 12px" }}>{d}</td></tr>
              {RESULTS.filter((r) => r.domain === d).map((r) => (
                <tr key={r.id}>
                  <td style={{ padding:"9px 12px", borderBottom:"1px solid #eaeef2", fontFamily:"ui-monospace,Menlo,monospace", fontWeight:600, whiteSpace:"nowrap" }}>{r.id}</td>
                  <td style={{ padding:"9px 12px", borderBottom:"1px solid #eaeef2", maxWidth:480 }}>{r.title}</td>
                  <td style={{ padding:"9px 12px", borderBottom:"1px solid #eaeef2" }}><Pill status={r.status} /></td>
                  <td style={{ padding:"9px 12px", borderBottom:"1px solid #eaeef2", fontWeight:700, fontSize:11, color:SEVC[r.severity] }}>{String(r.severity).toUpperCase()}</td>
                  <td style={{ padding:"9px 12px", borderBottom:"1px solid #eaeef2", fontSize:11 }}>
                    {r.known && r.ticket ? <span style={{ fontFamily:"ui-monospace,monospace", color:"#0969da" }}>{r.ticket}</span>
                      : r.status === "fail" ? <span style={{ color:"#cf222e", fontWeight:700 }}>REGRESSION</span> : ""}
                  </td>
                </tr>
              ))}
            </React.Fragment>
          ))}
        </tbody>
      </table>

      <div style={{ display:"grid", gridTemplateColumns:"1fr 1fr", gap:16, marginTop:22 }}>
        <div style={{ ...card, border:"2px solid #cf222e" }}>
          <h3 style={{ margin:"0 0 10px", fontSize:14 }}>🔴 New regression (un-ticketed)</h3>
          <ul style={{ margin:0, paddingLeft:18 }}>
            {regs.length ? regs.map((r) => (
              <li key={r.id} style={{ marginBottom:8, fontSize:13 }}><b>{r.id}</b> — {r.title}
                <div style={{ color:"#57606a", fontSize:11.5, marginTop:3 }}>{r.actual}</div></li>
            )) : <li>None.</li>}
          </ul>
        </div>
        <div style={card}>
          <h3 style={{ margin:"0 0 10px", fontSize:14 }}>⚠️ Critical / high-severity findings</h3>
          <ul style={{ margin:0, paddingLeft:18 }}>
            {crit.map((r) => (
              <li key={r.id} style={{ marginBottom:8, fontSize:13 }}>
                <b>{r.id}</b> — {r.title} <Pill status={r.status} mini /> {r.known && r.ticket ? "· "+r.ticket : "· NEW REGRESSION"}
              </li>
            ))}
          </ul>
        </div>
      </div>

      <div style={{ ...card, marginTop:16 }}>
        <h3 style={{ margin:"0 0 10px", fontSize:14 }}>📋 Known issues confirmed still open</h3>
        <ul style={{ margin:0, paddingLeft:18 }}>
          {known.map((r) => (
            <li key={r.id} style={{ marginBottom:6, fontSize:13 }}><b>{r.ticket || "?"}</b> — {r.title} <Pill status={r.status} mini /></li>
          ))}
        </ul>
      </div>

      <div style={{ marginTop:26, color:"#57606a", fontSize:12 }}>
        <b>Coverage &amp; guardrails:</b> Quote DML is RLM-blocked (all reprices via managed Place Sales Transaction, configurationPref=Skip).
        No deletes, no order activation, no platform events — Workday/MuleSoft integration out of scope. Accepted/Ordered/In-Review quotes read-only.
        See E2E_DETAILED_REPORT.md for full evidence.
      </div>
    </div>
  );
}
