import React from "react";

// SC-3346 Maintenance (Derived) Pricing — E2E Test Executive Summary (executed scenarios only, sorted by status)
// NOTE: renewal-commit failures are a SC-3346 build defect (unticketed) — NOT "SC-3404"
// (SC-3404 = the SC-3390 tiered-pricing Peer Review, Done/approved).
const RESULTS = [
  {
    "id": "MAINT-ONLY",
    "domain": "Edge cases",
    "title": "Maintenance-only renewal quote (no contributor) -> MissingContributor handling",
    "status": "fail",
    "severity": "critical",
    "known": true,
    "ticket": "SC-3346 renewal-maintenance commit defect (unticketed; NOT SC-3404)",
    "actual": "MissingContributor handling is non-fatal/graceful (transaction completes), BUT the maintenance line does NOT price correctly. Canary Draft quote 00781109 (0Q0WC0000038aXd0AI), single RRM line PIA-PIA-RRM-PIAM (QLI 0QLWC000003e2Sn4AI), ParentQuoteLineItemId + RelatedQuoteLineItemI"
  },
  {
    "id": "RN-COLA-COMMIT",
    "domain": "Renewal COLA pricing",
    "title": "Renewal maintenance committed NetUnitPrice does not equal expected COLA net",
    "status": "fail",
    "severity": "critical",
    "known": true,
    "ticket": "SC-3346 renewal-maintenance commit defect (unticketed; NOT SC-3404)",
    "actual": "On all 4 canary lines NetUnitPrice diverges from the correct COLA net: 00781043 commits 0 (exp 67.38), 00781053 commits 54.58 (exp 60.64), 00781084 commits 60.64 (exp 67.38), 00781109 commits 60.64 / UnitPrice 0 (exp 67.38). The wrong values are either $0 or COLA-net x 0.90 (part"
  },
  {
    "id": "MULTI-ASSET",
    "domain": "Edge cases",
    "title": "Multi-asset renewal (license + maintenance both renewed)",
    "status": "fail",
    "severity": "high",
    "known": true,
    "ticket": "SC-3346 renewal-maintenance commit defect (unticketed; NOT SC-3404)",
    "actual": "Split outcome. License/subscription leg renews CORRECTLY (NetUnitPrice 4442.35, SalesTransactionActionType=Renew, ItemIsDerived=false). Renewal-maintenance leg is WRONG: COLA net 60.64 is correctly computed into COLACalculatedPrice__c but committed NetUnitPrice = 54.58 (= 60.64 x"
  },
  {
    "id": "NB-DERIVED-TIER",
    "domain": "Derived (new-business) pricing",
    "title": "Maintenance tier/rate lookup (Maintenance_Rate / type) resolves correct %",
    "status": "fail",
    "severity": "high",
    "known": false,
    "ticket": "",
    "actual": "Tier resolution is correct for the 3 dominant tiers ONLY (Premier 0.30, Professional 0.20, Standard 0.20) and is NOT a CMDT lookup at all - the rates are hard-coded inline in the V14 DerivedPricingFormula IF-chain. The 4 remaining MTD tiers used on live lines (Basic 182, platinum"
  },
  {
    "id": "PBEDP-COVERAGE",
    "domain": "Config & data integrity",
    "title": "Derived-PBE PriceBookEntryDerivedPrice config completeness (95% gap; M-5 / SC-3372)",
    "status": "fail",
    "severity": "high",
    "known": true,
    "ticket": "SC-3372",
    "actual": "Only 174 of 3,453 derived PBEs are covered by config (176 PBEDP rows, 2 multi-contributor). 3,279 of 3,453 (95.0%) have NO derived-price config; ALL 3,453 are UnitPrice=0 zero-list and ALL are IsActive=true, so the entire 95% gap is live exposure. Gap by type: New Maintenance 1,7"
  },
  {
    "id": "RN-MULTIYEAR",
    "domain": "Renewal COLA pricing",
    "title": "Additional-year / out-year / MyCAP renewal COLA pricing: computed correctly but never committed (renewal-maintenance net wrong on commit)",
    "status": "fail",
    "severity": "high",
    "known": true,
    "ticket": "SC-3346 renewal-maintenance commit defect (unticketed; NOT SC-3404)",
    "actual": "COMPUTATION is WIRED and CORRECT, but the COMMIT is BROKEN. After a live Force reprice (Place Sales Transaction + configurationMethod Skip, isSuccess:true, non-destructive: line count stayed 1) of canary 00781109 / 0Q0WC0000038aXd0AI: the renewal-maintenance line 0QLWC000003e2Sn4"
  },
  {
    "id": "RN-PARTNER-DD",
    "domain": "Renewal COLA pricing",
    "title": "Partner discount double-applied on renewal maintenance (COLA net x 0.90 = 60.64 instead of 67.38)",
    "status": "fail",
    "severity": "high",
    "known": true,
    "ticket": "SC-3346 renewal-maintenance commit defect (unticketed; NOT SC-3404)",
    "actual": "Committed NetUnitPrice = 60.64 = COLA net 67.38 x 0.90 (a flat ~10% partner discount re-applied on top of the already-net COLA price). The partner discount is counted TWICE: once as the Prior_Partner_Discount__c=8.52 subtraction inside the COLA net, and again as the x0.90 layer. "
  },
  {
    "id": "ZERO-LIST-PBE",
    "domain": "Config & data integrity",
    "title": "Derived maintenance PBEs with $0 list price (SC-3372 secondary): zero-list PBE yields $0 maintenance line on reprice",
    "status": "fail",
    "severity": "high",
    "known": true,
    "ticket": "SC-3372",
    "actual": "All 3,453 derived PBEs are zero-list (UnitPrice=0, 100%; UnitPrice>0 returns 0). Only 176 PriceBookEntryDerivedPrice config rows cover 174 distinct PBEs -> 3,279 uncovered (95%); on the real transacting Fortra Price Book, 1,717 uncovered vs 172 covered (91% uncovered). Live non-d"
  },
  {
    "id": "DECOMP-SPLIT",
    "domain": "Order decomposition",
    "title": "Maintenance order line decomposition (parent license to derived maintenance child via Original_Order_Item__c)",
    "status": "partial",
    "severity": "medium",
    "known": false,
    "ticket": "SC-3346",
    "actual": "The Original_Order_Item__c FK-split decomposition model described in the scenario DOES NOT EXIST in the SC-3346 build. (1) All 40 OrderItems with Original_Order_Item__c populated are pure quantity-splits: child Product2Id == parent Product2Id on 40/40 (e.g. 5250 Integrator to 525"
  },
  {
    "id": "MDT-RECORDS",
    "domain": "Config & data integrity",
    "title": "Maintenance_Type_Defn / Maintenance_Rate / COLA rules CMDT records present & correct",
    "status": "partial",
    "severity": "medium",
    "known": false,
    "ticket": "",
    "actual": "Core data is PRESENT and CORRECT and is consumed correctly end-to-end, but two config-integrity blemishes exist in the domain under test. (1) Maintenance_Rate__mdt = 7 rows, all values match D4 EXACTLY: Basic 0.15, Professional 0.20, Standard 0.20, Premium 0.24, Express 0.30, Pre"
  },
  {
    "id": "NB-DERIVED-FORMULA",
    "domain": "Derived (new-business) pricing",
    "title": "Which new-business formula computes the derived net (Source_List_Price x tier live vs Base_Price x tier dead-code)",
    "status": "partial",
    "severity": "medium",
    "known": true,
    "ticket": "SC-3403 (M-2)",
    "actual": "CONFIRMED at the computation level: the live new-business derived net is tier x Source_List_Price__c (DerivedPricingFormula, ListContainer9 seq2, gated by AttributeDefinitionCode='MTD' which EXISTS). Proven empirically on a real stamped line: 0QLWC000003cL1i4AE (EFT 8 Continuum-N"
  },
  {
    "id": "RN-COLA-RATES",
    "domain": "Renewal COLA pricing",
    "title": "COLA uplift rate lookup by solution category (COLA_Uplift_Rules__mdt) vs spec rates",
    "status": "partial",
    "severity": "medium",
    "known": true,
    "ticket": "SC-3350",
    "actual": "Live UAT COLA_Uplift_Rules__mdt has 22 records (not 20), all Active=true, all effective-dates null. The 22 per-category rate values match the spec/discovery table EXACTLY with ZERO drift (diff of live vs expected = no difference; range 0-9.85 matches SDD). Lookup key Solution_Cat"
  },
  {
    "id": "B4-NULLGUARD",
    "domain": "Peer-review findings",
    "title": "B-4: renewal formula ISNULL guards + null carry-forward",
    "status": "pass",
    "severity": "none",
    "known": false,
    "ticket": "SC-3403 (B-4); (separate $0-commit blocker, still open)",
    "actual": "CONFIRMED resolved at the formula/engine layer. Live retrieve of the sole-active V14 (ExpressionSetVersion 9QMWC00000023eX4AQ IsActive=true) shows DerivedPricingRenewals = IF(QuoteTypeText__c='Renewal', IF(COLACalculatedPrice__c>0, COLACalculatedPrice__c, (IF(ISNULL(Base_Price__c"
  },
  {
    "id": "DECOMP-BASE",
    "domain": "Order decomposition",
    "title": "B-6: maintenance OrderItem carries maintenance base (~71) not license base (355)",
    "status": "pass",
    "severity": "none",
    "known": false,
    "ticket": "SC-3403 (B-6)",
    "actual": "All 16 live maintenance OrderItems with Base_Price__c>0 carry the maintenance base. COUNT(maintenance OI WHERE Base_Price__c=355)=0; zero rows have Base_Price__c==Source_List_Price__c. Decomposition chain proven end-to-end at two price points: PIAMBK OI 802WC00000OcIChYAN (order "
  },
  {
    "id": "NB-DERIVED-NET",
    "domain": "Derived (new-business) pricing",
    "title": "First-year maintenance derived NetUnitPrice value is correct",
    "status": "pass",
    "severity": "none",
    "known": false,
    "ticket": "",
    "actual": "All 9 active-quantity derived New-Maintenance lines (PIA-PIA-RNM-PIAMBK) on Draft quote 00781057 hold NetUnitPrice=71 with Source_List_Price__c=355, ListPrice=0, UnitPrice=0. Result is exact (0.20 x 355 = 71.00) and reproducible: confirmed both pre-reprice and after a fresh Place"
  },
  {
    "id": "PROC-V14",
    "domain": "Config & data integrity",
    "title": "V14 active + derived/maintenance procedure elements present & correct",
    "status": "pass",
    "severity": "none",
    "known": false,
    "ticket": "SC-3403",
    "actual": "CONFIRMED LIVE on 2026-06-13. Live retrieve of ExpressionSetDefinition Rev_Mgmt_Default_Pricing_Procedure (api 67) shows V140 / versionNumber 14 is the SOLE Active version; all 13 prior versions (V1..V130) are Inactive (corrects the pre_reactivate snapshot which carried V14 as In"
  },
  {
    "id": "RN-COLA-MATH",
    "domain": "Renewal COLA pricing",
    "title": "Renewal maintenance COLA net computed in-flight = (Base - priorPartner - priorDisc) x (1 + COLA%)",
    "status": "pass",
    "severity": "none",
    "known": false,
    "ticket": "",
    "actual": "PASS. The in-flight COLA net formula reproduces the stamped COLACalculatedPrice__c EXACTLY on all 4 stamped renewal-maintenance lines, and a live Force reprice of canary 00781109 re-fired the computation with a FINEST log explicitly logging the in-flight result 67.38. (1) Static "
  },
  {
    "id": "SLP-CARRY",
    "domain": "Stamp / data flow",
    "title": "Source_List_Price carry-forward Quote->Order (M-4 QuoteToOrderFieldMapper)",
    "status": "pass",
    "severity": "none",
    "known": false,
    "ticket": "",
    "actual": "M-4 is RESOLVED on UAT. The LIVE deployed QuoteToOrderFieldMapper (Id 01pWC000002IuvRYAS, body 9,760 chars, LastModified 2026-06-12T20:21Z) has the Source_List_Price__c mapping ACTIVE/uncommented at two points: the QLI->OI copy loop (if sourceQLI.Source_List_Price__c != null && o"
  },
  {
    "id": "STAMP-FLOW",
    "domain": "Stamp / data flow",
    "title": "Stamp_Maintenance_Pricing_Inputs correctly stamps Base_Price / COLACalculatedPrice / priors / COLA% / product type before-save and re-fires on reprice",
    "status": "pass",
    "severity": "none",
    "known": false,
    "ticket": "",
    "actual": "All stamps verified arithmetically exact and re-fired correctly during a live non-destructive Place-Sales-Transaction reprice (configurationMethod Skip) of Draft quote 00781043 (line count 1->1; LastModifiedDate advanced to 2026-06-14T00:08:23Z). Renewal lines: 00781043 COLACalc="
  }
];

const HEALTH = { verdict: "NO-GO", color: "#cf222e", message:
  "New-business derived-maintenance pricing + plumbing PASS; the renewal COLA path is broken at commit ($0/60.64 vs the computed COLA net) — a SC-3346 build defect (NOT SC-3404). " +
  "Plus one NEW un-ticketed tier defect (3 of 7 tiers hard-coded -> $0 first-year maintenance) and the systemic SC-3372 PBEDP gap (95% unconfigured)." };

const STC = { pass:"#1a7f37", fail:"#cf222e", partial:"#9a6700" };
const STBG = { pass:"#dafbe1", fail:"#ffebe9", partial:"#fff8c5" };
const SEVC = { critical:"#cf222e", high:"#bc4c00", medium:"#9a6700", low:"#57606a", none:"#1a7f37", unknown:"#8c959f" };
const ST_RANK = { fail:0, partial:1, pass:2 };
const SEV_RANK = { critical:0, high:1, medium:2, low:3, none:4, unknown:5 };

function Pill({ status, label, mini }) {
  return (<span style={{ display:"inline-block", padding: mini?"1px 7px":"2px 9px", borderRadius:20,
    fontSize: mini?10:11, fontWeight:700, color:STC[status], background:STBG[status] }}>
    {(label || status).toUpperCase()}</span>);
}

export default function SC3346ExecutiveSummary() {
  const rows = [...RESULTS].sort((a,b) =>
    (ST_RANK[a.status]-ST_RANK[b.status]) || (SEV_RANK[a.severity]-SEV_RANK[b.severity]) || a.id.localeCompare(b.id));
  const n = (s) => rows.filter((r) => r.status === s).length;
  const nNew = rows.filter((r) => r.status === "fail" && !r.known).length;
  const fails = rows.filter((r) => r.status === "fail");
  const card = { background:"#fff", border:"1px solid #d0d7de", borderRadius:10, padding:16, marginTop:18 };

  return (
    <div style={{ fontFamily:"-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial,sans-serif",
      maxWidth:1080, margin:"0 auto", padding:"28px 20px 60px", color:"#1f2328", background:"#f6f8fa" }}>
      <h1 style={{ margin:"0 0 4px", fontSize:23 }}>SC-3346 Maintenance (Derived) Pricing — E2E Test Executive Summary</h1>
      <div style={{ color:"#57606a", fontSize:13.5 }}>
        Org <b>FortraUAT</b> · Procedure <b>V14</b> · Peer review <b>SC-3403</b> · Workday/MuleSoft integration <b>excluded</b> · executed scenarios only · sorted by status</div>

      <div style={{ margin:"18px 0", padding:"14px 18px", borderRadius:10, borderLeft:`6px solid ${HEALTH.color}`, ...card, marginTop:18 }}>
        <div style={{ fontWeight:800, color:HEALTH.color, fontSize:16, letterSpacing:.5 }}>BUILD-READINESS: {HEALTH.verdict}</div>
        <div>{HEALTH.message}</div>
      </div>

      <div style={{ display:"grid", gridTemplateColumns:"repeat(5,1fr)", gap:12, margin:"18px 0" }}>
        {[["Executed",rows.length,"#1f2328"],["Fail",n("fail"),"#cf222e"],["New defect",nNew,"#cf222e"],
          ["Partial",n("partial"),"#9a6700"],["Pass",n("pass"),"#1a7f37"]].map(([l,v,c]) => (
          <div key={l} style={{ background:"#fff", border:"1px solid #d0d7de", borderRadius:10, padding:14, textAlign:"center" }}>
            <div style={{ fontSize:27, fontWeight:700, color:c }}>{v}</div>
            <div style={{ fontSize:10.5, textTransform:"uppercase", letterSpacing:.5, color:"#57606a", marginTop:4 }}>{l}</div>
          </div>))}
      </div>

      <table style={{ width:"100%", borderCollapse:"collapse", background:"#fff", border:"1px solid #d0d7de", borderRadius:10, overflow:"hidden", fontSize:13 }}>
        <thead><tr>{["ID","Scenario","Status","Severity","Attribution"].map((h) => (
          <th key={h} style={{ textAlign:"left", padding:"10px 12px", background:"#f6f8fa", borderBottom:"1px solid #d0d7de",
            fontSize:11, textTransform:"uppercase", letterSpacing:.4, color:"#57606a" }}>{h}</th>))}</tr></thead>
        <tbody>{rows.map((r) => (
          <tr key={r.id}>
            <td style={{ padding:"9px 12px", borderBottom:"1px solid #eaeef2", fontFamily:"ui-monospace,Menlo,monospace", fontWeight:600, whiteSpace:"nowrap" }}>{r.id}</td>
            <td style={{ padding:"9px 12px", borderBottom:"1px solid #eaeef2", maxWidth:470 }}>{r.title}
              <div style={{ color:"#8c959f", fontSize:11, marginTop:2 }}>{r.domain}</div></td>
            <td style={{ padding:"9px 12px", borderBottom:"1px solid #eaeef2" }}><Pill status={r.status} /></td>
            <td style={{ padding:"9px 12px", borderBottom:"1px solid #eaeef2", fontWeight:700, fontSize:11, color:SEVC[r.severity] }}>{String(r.severity).toUpperCase()}</td>
            <td style={{ padding:"9px 12px", borderBottom:"1px solid #eaeef2", fontSize:11 }}>
              {r.status === "fail" ? (r.known ? <span style={{ fontFamily:"ui-monospace,monospace", color:"#0969da" }}>{r.ticket}</span>
                  : <span style={{ color:"#cf222e", fontWeight:700 }}>NEW · no ticket</span>)
                : r.ticket ? <span style={{ fontFamily:"ui-monospace,monospace", color:"#0969da" }}>{r.ticket}</span> : ""}
            </td>
          </tr>))}</tbody>
      </table>

      <div style={{ ...card, border:"2px solid #cf222e" }}>
        <h3 style={{ margin:"0 0 10px", fontSize:14 }}>❌ Failures (sorted by severity)</h3>
        <ul style={{ margin:0, paddingLeft:18 }}>
          {fails.map((r) => (
            <li key={r.id} style={{ marginBottom:9, fontSize:13 }}>
              <b>{r.id}</b> — {r.title} <Pill status="fail" label={r.severity} mini />{" "}
              {r.known ? r.ticket : <b style={{ color:"#cf222e" }}>NEW</b>}
              <div style={{ color:"#57606a", fontSize:11.5, marginTop:3 }}>{r.actual}</div>
            </li>))}
        </ul>
      </div>

      <div style={{ marginTop:18, color:"#57606a", fontSize:12 }}>
        <b>Ticket note:</b> renewal-commit failures are a <b>SC-3346 build defect (unticketed)</b> — NOT "SC-3404"
        (SC-3404 = the SC-3390 tiered-pricing Peer Review, Done/approved). <b>Scope:</b> {rows.length} executed scenarios only
        (11 further scenarios were not executed and are excluded from this view).
      </div>
    </div>
  );
}
