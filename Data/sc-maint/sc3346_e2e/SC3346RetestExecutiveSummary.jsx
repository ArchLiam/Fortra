import React from "react";

// SC-3346 Maintenance (Derived) Pricing — E2E Re-Test Executive Summary (post-fix, sorted by status)
// Prod-only items: NONE. All failures UAT-fixable or owner-gated. Build is UAT-only (prod promotion pending).
const RESULTS = [
 {
  "id": "MAINT-ONLY",
  "domain": "Edge cases",
  "title": "Maintenance-only renewal quote (no contributor) -> MissingContributor handling + commit",
  "status": "fail",
  "severity": "critical",
  "fix": "owner-gated",
  "actual": "RE-TESTED LIVE on V14 (re-verified active: ExpressionSetVersion 9QMWC00000023eX4AQ, IsActive=true). Part (a) MissingContributor handling = PASS/graceful: ValidationResult=MissingContributor persists (169 occurrences) but CalculationStatus=CompletedWithPricing and the Place Sales Transaction (Force +"
 },
 {
  "id": "M5-PBEDP",
  "domain": "Peer-review findings",
  "title": "M-5: missing derived-RRM PriceBookEntryDerivedPrice config rows (95% gap; SC-3372)",
  "status": "fail",
  "severity": "high",
  "fix": "uat-fixable",
  "actual": "PARTIALLY remediated this session but still a systemic open defect. Live FortraUAT (2026-06-14): PBEDP config rows = 201 (was 176, +25); distinct IsDerived PBEs covered = 199 (was 174, +25); uncovered gap = 3254 of 3453 (was 3279) = 94.2% still uncovered (was 95.0%). Total IsDerived PBEs unchanged a"
 },
 {
  "id": "MULTI-ASSET",
  "domain": "Edge cases",
  "title": "Multi-asset renewal (license + maintenance both renewed)",
  "status": "fail",
  "severity": "high",
  "fix": "owner-gated",
  "actual": "Split outcome UNCHANGED on live V14 after a fresh Force reprice. License/subscription leg renews CORRECTLY: beSECURE NetUnitPrice=4442.35 (= 5417.50 x 0.82). Renewal-maintenance leg is WRONG: the correct COLA net 60.64 is computed into COLACalculatedPrice__c but committed NetUnitPrice=54.58 (= 60.64"
 },
 {
  "id": "NB-DERIVED-TIER",
  "domain": "Derived (new-business) pricing",
  "title": "Maintenance tier/rate lookup (Maintenance_Rate / type) resolves correct % \u2014 only 3 of 7 ti",
  "status": "fail",
  "severity": "high",
  "fix": "owner-gated",
  "actual": "DEFECT PERSISTS on current live state (V14 active, ExpressionSet 9QLWC0000015cDl4AI). The tier 'lookup' is NOT a Maintenance_Rate__mdt lookup at all \u2014 the rates are hard-coded inline in the active V14 DerivedPricingFormula IF-chain, and only 3 of 7 tiers are handled. Active V14 DerivedPricingFormula"
 },
 {
  "id": "PBEDP-COVERAGE",
  "domain": "Config & data integrity",
  "title": "Derived-PBE PriceBookEntryDerivedPrice config completeness (post 25-FIM backfill)",
  "status": "fail",
  "severity": "high",
  "fix": "uat-fixable",
  "actual": "Improved but still failing. This session's 25-FIM backfill is REAL, clean, and non-regressive, but the systemic catalog-wide gap remains open at 94.2%. Live re-measure (active proc V14, ESV 9QMWC00000023eX4AQ): PriceBookEntryDerivedPrice rows = 201 (was 176, +25, all 25 new rows marked Legacy_Rule_I"
 },
 {
  "id": "RN-COLA-COMMIT",
  "domain": "Renewal COLA pricing",
  "title": "Renewal maintenance committed NetUnitPrice does not equal expected COLA net (SC-3404)",
  "status": "fail",
  "severity": "high",
  "fix": "owner-gated",
  "actual": "PARTIALLY IMPROVED BUT STILL FAILS on the canary. Live state (V14 active, ExpressionSetVersion 9QMWC00000023eX4AQ re-confirmed) after a fresh Force reprice (configurationMethod Skip, isSuccess:true): the canary 00781109 / 0QLWC000003e2Sn4AI committed UnitPrice=67.38 (correct, improved from prior 0) "
 },
 {
  "id": "RN-PARTNER-DD",
  "domain": "Renewal COLA pricing",
  "title": "Partner discount double-applied on renewal maintenance (COLA net x 0.90 = 60.64 instead of",
  "status": "fail",
  "severity": "high",
  "fix": "owner-gated",
  "actual": "DEFECT STILL OPEN but the picture CHANGED (partial improvement + mechanism re-characterized). The committed net diverges from COLA net on 3 of 4 corpus lines, all of which are structurally-excluded derived nodes (QuoteAction=null): canary 0QLWC000003e2Sn4AI (q00781109) commits NetUnitPrice=60.64 = 6"
 },
 {
  "id": "TEST-SUITE",
  "domain": "Quality",
  "title": "Maintenance-build test suite runs green",
  "status": "fail",
  "severity": "high",
  "fix": "uat-fixable",
  "actual": "Suite does NOT run green. 11 of 12 build test classes pass green at 100% SOLO coverage, but COLAUpliftTest FAILS TO COMPILE against current live Apex: \"line 1813, column 70: Method does not exist or incorrect signature: void buildOverrideMap(List<SObject>) from the type COLAUpliftPrehook\" (0 methods"
 },
 {
  "id": "ZERO-LIST-PBE",
  "domain": "Config & data integrity",
  "title": "Derived maintenance PBEs with $0 list price yield $0 maintenance line (SC-3372 secondary)",
  "status": "fail",
  "severity": "high",
  "fix": "uat-fixable",
  "actual": "STILL FAILING, but partially improved by this session's PBEDP backfill. Live FortraUAT: all 3,453 IsDerived PBEs remain zero-list (UnitPrice=0=3453, UnitPrice>0=0 -- 100%, unchanged). PriceBookEntryDerivedPrice coverage improved from 176 rows / 174 distinct PBEs to 201 rows / 199 distinct PBEs (+25,"
 },
 {
  "id": "B5-DECISIONTABLE",
  "domain": "Peer-review findings",
  "title": "B-5: AssetActionSource decision table RefreshStatus",
  "status": "fail",
  "severity": "medium",
  "fix": "owner-gated",
  "actual": "B-5 RE-CONFIRMED FAILED on live FortraUAT, and the prior run never executed it (rate-limited), so this is the first real verdict. DecisionTable 0lDa50000007BJhEAM RefreshStatus=Failed, Status=Active, Type=MediumVolume, ExecutionType=HBASE, UsageType=PricingDiscovery, SourceObject=AssetActionSource, "
 },
 {
  "id": "M7-COVERAGE",
  "domain": "Peer-review findings",
  "title": "M-7: per-class SOLO coverage of the build classes (>=75%)",
  "status": "fail",
  "severity": "medium",
  "fix": "uat-fixable",
  "actual": "Executed live SOLO this run against V14-active org (V14 confirmed: ExpressionSetDefinitionVersion 9QBWC0000000nIT4AY, VersionNumber 14, Status Active). 10 of 12 build classes PASS >=75% SOLO, but 2 FAIL, so the M-7 \">=75% per-class\" bar is NOT met. PASS: QuoteRenewalTypeHandler 100% (5/5), RenewalQu"
 },
 {
  "id": "DATA-FIELD-POP",
  "domain": "Config & data integrity",
  "title": "Base_Price/Source_List_Price/COLA field population across maintenance lines (B-4 carry-for",
  "status": "partial",
  "severity": "medium",
  "fix": "uat-fixable",
  "actual": "FIRST real execution (prior verdict was NOT-EXECUTED / rate-limited). On the SC-3346 cohort where the stamp flow actually ran, field population is CORRECT AND ARITHMETICALLY EXACT, but there are three genuine population GAPS off that cohort, so PARTIAL.\n\nWORKING (build cohort): All 6 renewal-maint Q"
 },
 {
  "id": "DECOMP-SPLIT",
  "domain": "Order decomposition",
  "title": "Maintenance order line decomposition (parent license -> derived maintenance child via Orig",
  "status": "partial",
  "severity": "medium",
  "fix": "owner-gated",
  "actual": "CONFIRMED LIVE (unchanged from prior verdict): the Original_Order_Item__c FK-split decomposition model in the scenario premise DOES NOT EXIST in the SC-3346 build. (1) Live counts identical to prior run: 40 OrderItems carry Original_Order_Item__c, and python parent-vs-child Product2Id compare = 40/4"
 },
 {
  "id": "FIELD-PACKAGING",
  "domain": "Config & data integrity",
  "title": "SC-3346 custom fields exist + picklist values (force-app/prod gap)",
  "status": "partial",
  "severity": "medium",
  "fix": "uat-fixable",
  "actual": "SPLIT RESULT. (1) FIELD + PICKLIST EXISTENCE IN LIVE UAT = PASS. All core SC-3346 custom fields exist live with the exact types from build-understanding section 2.4, verified via FieldDefinition (Tooling) + REST describe: QLI Base_Price__c=Number(16,2), Source_List_Price__c=Currency(16,2), COLACalcu"
 },
 {
  "id": "M1-SDD",
  "domain": "Peer-review findings",
  "title": "M-1: prehooks present + write net (SDD reconciliation)",
  "status": "partial",
  "severity": "medium",
  "fix": "owner-gated",
  "actual": "CONFIRMED present + writing net, but the SDD .docx is still unreconciled (owner-gated doc edit not applied). Both processors are live and were both EDITED TODAY (2026-06-14) by Liam Jeong: COLAUpliftPrehook (01pWC000001wNGbYAM, ApiVersion 65, LengthWithoutComments 43,272 \u2014 matches the Nir/UAT lineag"
 },
 {
  "id": "RN-COLA-RATES",
  "domain": "Renewal COLA pricing",
  "title": "COLA uplift rate by solution category vs spec (grain exceptions)",
  "status": "partial",
  "severity": "medium",
  "fix": "owner-gated",
  "actual": "PARTIAL \u2014 IMPROVED on data-quality this session, but the two SOLUTION-grain rate exceptions remain wrong (owner-gated). (1) CATEGORY-GRAIN RATES: live COLA_Uplift_Rules__mdt now has 21 records (down from the prior 22), all Active=true, all effective-dates null; all 21 category rates match the spec c"
 },
 {
  "id": "MDT-RECORDS",
  "domain": "Config & data integrity",
  "title": "Maintenance_Rate / COLA_Uplift_Rules / Maintenance_Type_Defn (MTD) CMDT records present & ",
  "status": "partial",
  "severity": "low",
  "fix": "uat-fixable",
  "actual": "Re-tested live on FortraUAT 2026-06-14 against V14 (sole active ExpressionSetVersion VersionNumber=14, ExpressionSet 9QLWC0000015cDl4AI). Core CMDT data is PRESENT, CORRECT, and consumed correctly end-to-end. (1) Maintenance_Rate__mdt = 7 rows, all values EXACT vs D4 (Basic 0.15, Professional 0.20, "
 },
 {
  "id": "SDD-CONFORMANCE",
  "domain": "Quality",
  "title": "Build conforms to SC-3346 user story (single-year; derived formula)",
  "status": "partial",
  "severity": "low",
  "fix": "uat-fixable",
  "actual": "CONFORMS on the structural pillars, with two minor residual divergences (=> PARTIAL/low). Fresh live retrieve of the active V14 block (lines 69795-75345, status Active, label Rev Mgmt Default Pricing V14) on 2026-06-14: (1) SINGLE-YEAR scope CONFORMS \u2014 zero Outyear/Final_Year/MyCAP references anywhe"
 },
 {
  "id": "M2-DEADCODE",
  "domain": "Peer-review findings",
  "title": "M-2 DerivedPricingNewBusiness dead-code (MTD/MDT)",
  "status": "pass",
  "severity": "low",
  "fix": "already-fixed",
  "actual": "IMPROVED / RESOLVED since the prior verdict. Live fresh retrieve (2026-06-14, api v67) of ExpressionSetDefinition Rev_Mgmt_Default_Pricing_Procedure confirms V14 (_V140, versionNumber 14) is still the SOLE Active version (lines 69793-75347; V1-V13 all Inactive). In the active V14 block the M-2 dead-"
 },
 {
  "id": "B3-PARTNER",
  "domain": "Peer-review findings",
  "title": "B-3: partner 15%-vs-12% bulk overload (PartnerPricingService map-miss)",
  "status": "pass",
  "severity": "none",
  "fix": "already-fixed",
  "actual": "PASS - B-3 is resolved in the live FortraUAT class (PartnerPricingService 01pWC000001wAzPYAU, LastModified 2026-06-12 Nir Kailash, 335 ln). The defect is closed by two cooperating mechanisms: (1) loadProductTypesForLines (L108-138) bulk-loads the Product2.Fortra_Product_Type__c fallback for every li"
 },
 {
  "id": "B4-NULLGUARD",
  "domain": "Peer-review findings",
  "title": "B-4: renewal formula ISNULL guards + null carry-forward",
  "status": "pass",
  "severity": "none",
  "fix": "already-fixed",
  "actual": "RE-CONFIRMED RESOLVED at the formula/engine layer on live FortraUAT (2026-06-14), with stronger live evidence than the prior run. Fresh metadata retrieve (api v67) of Rev_Mgmt_Default_Pricing_Procedure shows V14 (versionNumber 14, label 'Rev Mgmt Default Pricing V14', file lines 69795-75347) is the "
 },
 {
  "id": "CFG-AUTOADD",
  "domain": "Auto-add first-year maintenance",
  "title": "Auto-add first-year maintenance fires on perpetual add",
  "status": "pass",
  "severity": "none",
  "fix": "na",
  "actual": "PASS. Auto-add is implemented as an Active ProductConfigurationRule (RuleType=Configurator, ProcessScope=Transaction), NOT a ProductRelatedComponent bundle (0 PRC rows under the perpetual parent). The BoKS Year-1 rule 14OWC0000022ULp2AM 'Year 1 Maintenance Sku added to Powertech Identity_Access Mana"
 },
 {
  "id": "DECOMP-BASE",
  "domain": "Order decomposition",
  "title": "B-6 maintenance OrderItem carries maintenance base not license base",
  "status": "pass",
  "severity": "none",
  "fix": "na",
  "actual": "PASS on current live state. Procedure V14 active. Zero license-base leak: count of maintenance OrderItems with Base_Price__c equal 355 is 0. All 16 live maintenance OrderItems with positive Base carry the maintenance base, none have Base equal SLP. Two chains proven: PIAMBK OI 802WC00000OcIChYAN ord"
 },
 {
  "id": "NB-DERIVED-FORMULA",
  "domain": "Derived (new-business) pricing",
  "title": "Which new-business formula computes the derived net (Source_List_Price x tier live vs Base",
  "status": "pass",
  "severity": "none",
  "fix": "already-fixed",
  "actual": "PASS (improved from prior PARTIAL). Two confirmations on CURRENT live state. (1) FORMULA CHOICE: the live new-business derived net is tier x Source_List_Price__c. The active V14 DerivedPricingFormula (fresh retrieve line 71642, ListContainer9 seq2, resultIncluded=false, output=NetUnitPrice) reads: I"
 },
 {
  "id": "NB-DERIVED-NET",
  "domain": "Derived (new-business) pricing",
  "title": "First-year maintenance derived NetUnitPrice value is correct (tier x Source_List_Price)",
  "status": "pass",
  "severity": "none",
  "fix": "na",
  "actual": "PASS, re-confirmed live against the V14-active procedure. On Draft quote 00781057 / 0Q0WC0000037rFZ0AY all 9 active-quantity derived New-Maintenance lines (PIA-PIA-RNM-PIAMBK) commit NetUnitPrice=71 with Source_List_Price__c=355, ListPrice=0, UnitPrice=0, MTD attribute='Standard' (rate 0.20). Result"
 },
 {
  "id": "PROC-V14",
  "domain": "Config & data integrity",
  "title": "V14 active + derived/maintenance procedure elements present & correct",
  "status": "pass",
  "severity": "none",
  "fix": "na",
  "actual": "CONFIRMED LIVE on 2026-06-14 against the current state (fresh ExpressionSetDefinition retrieve, api 67). (1) ExpressionSetVersion query: VersionNumber=14 (Id 9QMWC00000023eX4AQ) IsActive=true is the SOLE active version of ExpressionSet 9QLWC0000015cDl4AI; all 13 prior versions (V1..V13) IsActive=fal"
 },
 {
  "id": "RN-COLA-MATH",
  "domain": "Renewal COLA pricing",
  "title": "Renewal maintenance COLA net computed in-flight = (Base - priorPartner - priorDisc) x (1 +",
  "status": "pass",
  "severity": "none",
  "fix": "na",
  "actual": "PASS, confirmed on current live state. The in-flight COLA-net computation reproduces the stamped COLACalculatedPrice__c EXACTLY on all 4 renewal-maintenance canary lines, and a fresh live Force reprice of Draft canary 00781109 re-fired the computation with a FINEST log that decomposes the formula st"
 },
 {
  "id": "SLP-CARRY",
  "domain": "Stamp / data flow",
  "title": "Source_List_Price carry-forward Quote->Order (M-4 QuoteToOrderFieldMapper)",
  "status": "pass",
  "severity": "none",
  "fix": "already-fixed",
  "actual": "PASS, RE-CONFIRMED and STRENGTHENED vs the prior verdict. M-4 remains RESOLVED on live FortraUAT. (1) The live deployed QuoteToOrderFieldMapper (Id 01pWC000002IuvRYAS, body 9760 chars, LengthWithoutComments 8408, ApiVersion 62, LastModified 2026-06-12T20:21:26Z - UNCHANGED since the prior verdict) s"
 },
 {
  "id": "STAMP-FLOW",
  "domain": "Stamp / data flow",
  "title": "Stamp_Maintenance_Pricing_Inputs correctly stamps Base_Price / COLACalculatedPrice / prior",
  "status": "pass",
  "severity": "none",
  "fix": "na",
  "actual": "PASS re-confirmed on current live FortraUAT (procedure V14 / ESV 9QMWC00000023eX4AQ active; Stamp_Maintenance_Pricing_Inputs V13 + Stamp_Source_List_Price V8 both Active). All stamp fields are arithmetically exact and re-fire correctly on a fresh non-destructive Force reprice (configurationMethod Sk"
 },
 {
  "id": "RN-MULTIYEAR",
  "domain": "Renewal COLA pricing",
  "title": "Additional-year / out-year / MyCAP renewal COLA pricing is inert at the commit layer and o",
  "status": "out-of-scope",
  "severity": "none",
  "fix": "out-of-scope",
  "actual": "RE-TEST CONFIRMS INERT + OUT-OF-SCOPE. (1) The LIVE pricing procedure (freshly retrieved this session via metadata; max versionNumber=14, matching the directive's V14) has ZERO references to outyear / mycap / final_year / additional_year / COLA_Outyear (grep counts all 0), while COLA_Uplift_Percent "
 }
];
const HEALTH={verdict:"CONDITIONAL NO-GO",color:"#bc4c00",message:"Structural pillars sound; renewal-maintenance still commits wrong/zero on structurally-excluded derived lines (RN-COLA-COMMIT), V14 tier formula covers only 3 of 7 tiers (NB-DERIVED-TIER -> $0), 94.2% of derived PBEs lack config (M-5), and an overnight prehook refactor broke COLAUpliftTest (TEST-SUITE). No prod-only items; the build is UAT-only pending prod promotion."};
const STC={pass:"#1a7f37",fail:"#cf222e",partial:"#9a6700","out-of-scope":"#57606a"};
const STBG={pass:"#dafbe1",fail:"#ffebe9",partial:"#fff8c5","out-of-scope":"#eaeef2"};
const SEVC={critical:"#cf222e",high:"#bc4c00",medium:"#9a6700",low:"#57606a",none:"#1a7f37"};
const FIXC={"already-fixed":"#1a7f37","uat-fixable":"#0969da","owner-gated":"#8250df","prod-only":"#cf222e","out-of-scope":"#57606a",na:"#8c959f"};
const FIXLBL={"already-fixed":"FIXED \u2713","uat-fixable":"UAT-FIXABLE","owner-gated":"OWNER-GATED","prod-only":"PROD-ONLY","out-of-scope":"OUT-OF-SCOPE",na:"\u2014"};
const ST={fail:0,partial:1,pass:2,"out-of-scope":3}, SEV={critical:0,high:1,medium:2,low:3,none:4};
function Pill({status,label,mini}){return <span style={{display:"inline-block",padding:mini?"1px 6px":"2px 8px",borderRadius:20,fontSize:mini?9.5:10.5,fontWeight:700,color:STC[status],background:STBG[status]}}>{(label||status).toUpperCase()}</span>;}
export default function SC3346RetestExecutiveSummary(){
  const rows=[...RESULTS].sort((a,b)=>(ST[a.status]-ST[b.status])||(SEV[a.severity]-SEV[b.severity])||a.id.localeCompare(b.id));
  const n=s=>rows.filter(r=>r.status===s).length, f=x=>rows.filter(r=>r.fix===x).length;
  const fails=rows.filter(r=>r.status==="fail");
  const card={background:"#fff",border:"1px solid #d0d7de",borderRadius:10,padding:16,marginTop:18};
  return (<div style={{fontFamily:"-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif",maxWidth:1120,margin:"0 auto",padding:"28px 20px 60px",color:"#1f2328",background:"#f6f8fa"}}>
    <h1 style={{margin:"0 0 4px",fontSize:23}}>SC-3346 Maintenance (Derived) Pricing — E2E Re-Test Executive Summary</h1>
    <div style={{color:"#57606a",fontSize:13.5}}>Org <b>FortraUAT</b> · Procedure <b>V14</b> · Peer review <b>SC-3403</b> · post-fix re-test · integration <b>excluded</b> · sorted by status</div>
    <div style={{margin:"18px 0",padding:"14px 18px",borderRadius:10,borderLeft:`6px solid ${HEALTH.color}`,...card,marginTop:18}}>
      <div style={{fontWeight:800,color:HEALTH.color,fontSize:16,letterSpacing:.5}}>BUILD-READINESS: {HEALTH.verdict}</div><div>{HEALTH.message}</div></div>
    <div style={{display:"grid",gridTemplateColumns:"repeat(7,1fr)",gap:10,margin:"18px 0"}}>
      {[["Scenarios",rows.length,"#1f2328"],["Pass",n("pass"),"#1a7f37"],["Fail",n("fail"),"#cf222e"],["Partial",n("partial"),"#9a6700"],["Fixed \u2713",f("already-fixed"),"#1a7f37"],["Owner-gated",f("owner-gated"),"#8250df"],["Prod-only",f("prod-only"),"#cf222e"]].map(([l,v,c])=>(
        <div key={l} style={{background:"#fff",border:"1px solid #d0d7de",borderRadius:10,padding:12,textAlign:"center"}}><div style={{fontSize:24,fontWeight:700,color:c}}>{v}</div><div style={{fontSize:10,textTransform:"uppercase",letterSpacing:.4,color:"#57606a",marginTop:3}}>{l}</div></div>))}</div>
    <table style={{width:"100%",borderCollapse:"collapse",background:"#fff",border:"1px solid #d0d7de",borderRadius:10,overflow:"hidden",fontSize:12.5}}>
      <thead><tr>{["ID","Scenario","Status","Sev","Fixability"].map(h=>(<th key={h} style={{textAlign:"left",padding:"9px 11px",background:"#f6f8fa",borderBottom:"1px solid #d0d7de",fontSize:10.5,textTransform:"uppercase",letterSpacing:.4,color:"#57606a"}}>{h}</th>))}</tr></thead>
      <tbody>{rows.map(r=>(<tr key={r.id}>
        <td style={{padding:"8px 11px",borderBottom:"1px solid #eaeef2",fontFamily:"ui-monospace,Menlo,monospace",fontWeight:600,whiteSpace:"nowrap"}}>{r.id}</td>
        <td style={{padding:"8px 11px",borderBottom:"1px solid #eaeef2",maxWidth:430}}>{r.title}<div style={{color:"#8c959f",fontSize:10.5,marginTop:2}}>{r.domain}</div></td>
        <td style={{padding:"8px 11px",borderBottom:"1px solid #eaeef2"}}><Pill status={r.status}/></td>
        <td style={{padding:"8px 11px",borderBottom:"1px solid #eaeef2",fontWeight:700,fontSize:10.5,color:SEVC[r.severity]}}>{String(r.severity).toUpperCase()}</td>
        <td style={{padding:"8px 11px",borderBottom:"1px solid #eaeef2",fontWeight:700,fontSize:10.5,color:FIXC[r.fix]}}>{FIXLBL[r.fix]}</td></tr>))}</tbody></table>
    <div style={{...card,border:"2px solid #cf222e"}}><h3 style={{margin:"0 0 10px",fontSize:14}}>❌ Failures (by severity)</h3><ul style={{margin:0,paddingLeft:18}}>
      {fails.map(r=>(<li key={r.id} style={{marginBottom:9,fontSize:12.5}}><b>{r.id}</b> — {r.title} <Pill status="fail" label={r.severity} mini/> <span style={{color:FIXC[r.fix],fontWeight:700,fontSize:10.5}}>{FIXLBL[r.fix]}</span><div style={{color:"#57606a",fontSize:11,marginTop:3}}>{r.actual}</div></li>))}</ul></div>
    <div style={{marginTop:18,color:"#57606a",fontSize:11.5}}><b>Prod-only:</b> NONE — all failures UAT-fixable or owner-gated. Build is UAT-only (prod promotion pending). <b>Overnight:</b> posthook rework commits 67.38 on Renew-actioned lines; prehook refactor broke COLAUpliftTest.</div>
  </div>);
}
