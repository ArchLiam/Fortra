import React from "react";

// SC-3346 Maintenance (Derived) Pricing — E2E Test Executive Summary (functional pricing scope, sorted by status)
const RESULTS = [
 {
  "id": "MAINT-ONLY",
  "domain": "Edge cases",
  "title": "Maintenance-only renewal (no contributor) commit behavior",
  "status": "fail",
  "severity": "high",
  "actual": "RE-TESTED LIVE on V14 (ExpressionSet 9QLWC0000015cDl4AI). Part (a) MissingContributor handling = PASS/graceful: ValidationResult=MissingContributor persists but CalculationStatus=CompletedWithPricing and the Force/Skip Place Sales Transaction returns isSuccess:true, non-destructive (line count 1->1)"
 },
 {
  "id": "MULTI-ASSET",
  "domain": "Edge cases",
  "title": "Multi-asset renewal: license + maintenance both priced",
  "status": "fail",
  "severity": "high",
  "actual": "Split outcome on live V14, confirmed after a fresh Force reprice (configurationMethod=Skip, isSuccess:true) with both QLI LastModifiedDate advancing to 2026-06-14T14:46:24Z (active re-commit, not a stale read). LICENSE/SUBSCRIPTION LEG renews CORRECTLY: beSECURE (0QLWC000003cxzq4AA) UnitPrice=5417.5"
 },
 {
  "id": "NB-DERIVED-TIER",
  "domain": "Derived (new-business) pricing",
  "title": "7-tier derived-maintenance rate fix is NOT live \u2014 V14 formula still hard-codes only 3 of 7 tier",
  "status": "fail",
  "severity": "high",
  "actual": "FAIL \u2014 the 7-tier fix is NOT live; the active V14 procedure is still the 3-tier hard-code, byte-identical to the prior verdict. Active version re-verified live: ExpressionSetVersion 9QMWC00000023eX4AQ VersionNumber=14 IsActive=true is the SOLE active version of ExpressionSet 9QLWC0000015cDl4AI (V1-V"
 },
 {
  "id": "RN-COLA-COMMIT-AUTOADD",
  "domain": "Renewal COLA pricing",
  "title": "Auto-added No-Change renewal-maint line commits 60.64 born-stale vs 67.38 (creation-path defect",
  "status": "fail",
  "severity": "high",
  "actual": "FAIL on current live state (procedure V14 confirmed sole-Active, see evidence). The auto-added / QuoteAction-less canary commits the WRONG net and it is NOT reprice-fixable (creation-path / engine-owned defect, exactly as the current-state facts describe). Canary 00781109 / QLI 0QLWC000003e2Sn4AI (P"
 },
 {
  "id": "RN-PARTNER-DD",
  "domain": "Renewal COLA pricing",
  "title": "Partner discount double-applied on renewal maintenance (COLA net x 0.90 = 60.64 instead of 67.3",
  "status": "fail",
  "severity": "high",
  "actual": "DEFECT PERSISTS on current live state (V14 active, ESV 9QMWC00000023eX4AQ re-confirmed sole-active). After a fresh Force reprice (configurationMethod Skip, isSuccess:true), the canary 0QLWC000003e2Sn4AI (q00781109) commits NetUnitPrice=60.64 = 67.38 x 0.90 (ratio 0.89997) - a partner double-discount"
 },
 {
  "id": "M1-SDD",
  "domain": "Pricing mechanism",
  "title": "Prehook seeds COLACalc + posthook/handler net mechanism functions as designed (M-1)",
  "status": "partial",
  "severity": "high",
  "actual": "PARTIALLY functions as designed on current live V14 (ExpressionSet 9QLWC0000015cDl4AI). HALF 1 (prehook seeds COLACalc) WORKS: the live COLAUpliftPrehook (01pWC000001wNGbYAM, v65, implements RevSignaling.SignalingApexProcessor L21, edited today 14:40:21Z) fires and computes 67.38 via computeStampedM"
 },
 {
  "id": "SDD-CONFORMANCE",
  "domain": "Spec conformance",
  "title": "Build matches SC-3346 user story: single-year; first-year = tier x Source_List; renewal = COLA ",
  "status": "partial",
  "severity": "high",
  "actual": "PARTIAL."
 },
 {
  "id": "AMEND-PRICING",
  "domain": "Renewal pricing",
  "title": "Amendment quote maintenance pricing (QuoteTypeText='Amendment' routes through new-business deri",
  "status": "partial",
  "severity": "medium",
  "actual": "PARTIAL. The amendment-pricing MECHANISM is correct by design, but amendment derived-maintenance lines inherit the unresolved new-business derived defects and do not price on the live amendment quotes. Verified live (V14 active, ESV 9QMWC00000023eX4AQ). Quote_Type__c picklist has a distinct 'Amendme"
 },
 {
  "id": "DECOMP-SPLIT",
  "domain": "Order decomposition",
  "title": "Order line decomposition parent license -> derived maintenance child (Original_Order_Item__c FK",
  "status": "partial",
  "severity": "medium",
  "actual": "CONFIRMED LIVE (V14 active; decomposition class MaintenanceOrderDecompositionService v62 Id 01pWC000002W5rRYAS, LastModified 2026-06-12, unchanged). The Original_Order_Item__c FK-split decomposition model in the scenario premise DOES NOT EXIST in the SC-3346 build, but the decomposition FEATURE work"
 },
 {
  "id": "RN-COLA-RATES",
  "domain": "Renewal COLA pricing",
  "title": "Category COLA uplift rate applied correctly (BoKS 7.85); per-solution grain exceptions still wr",
  "status": "partial",
  "severity": "medium",
  "actual": "PARTIAL on current live state."
 },
 {
  "id": "B3-PARTNER",
  "domain": "Partner pricing",
  "title": "B-3: maintenance partner discount (12% New / 10% Renewal) vs 15% Software selected by correct p",
  "status": "pass",
  "severity": "none",
  "actual": "PASS on current live FortraUAT state (procedure V14 confirmed sole-active: ExpressionSetDefinition retrieve shows versionNumber 14 status=Active, V1-V13 all Inactive). The product-type-correct partner-rate selection works end-to-end, proven by a fresh live reprice (stronger than the prior structural"
 },
 {
  "id": "B4-NULLGUARD",
  "domain": "Renewal formula robustness",
  "title": "B-4: Renewal COLA formula ISNULL-guarded (no null/0 leak)",
  "status": "pass",
  "severity": "none",
  "actual": "RESOLVED and re-confirmed live on FortraUAT (2026-06-14) at both the formula/engine layer and empirically. (1) ACTIVE VERSION: ExpressionSetVersion query shows VersionNumber=14 (9QMWC00000023eX4AQ) IsActive=true is the SOLE active version of ExpressionSet 9QLWC0000015cDl4AI; V1-V13 all IsActive=fals"
 },
 {
  "id": "CFG-AUTOADD",
  "domain": "Auto-add first-year maintenance",
  "title": "Auto-add first-year maintenance fires on perpetual add",
  "status": "pass",
  "severity": "none",
  "actual": "PASS, re-confirmed against current live V14 state. Auto-add is implemented as an Active ProductConfigurationRule (RuleType=Configurator, ProcessScope/RuleSubType=Transaction), NOT a ProductRelatedComponent bundle (0 PRC rows under the perpetual parent 01tWC00000DD1btYAD). The BoKS Year-1 rule 14OWC0"
 },
 {
  "id": "DECOMP-BASE",
  "domain": "Order decomposition",
  "title": "B-6 maintenance OrderItem carries maintenance base (71) not license base (355)",
  "status": "pass",
  "severity": "none",
  "actual": "PASS on current live FortraUAT, re-confirmed. (1) CODE PATH: live MaintenanceOrderDecompositionService 01pWC000002W5rRYAS (ApiVersion 62, LastModified 2026-06-12T20:21:25Z, unchanged since prior verdict) computes maintenanceBase = (sourceBase x tierRate).setScale(2,HALF_UP) at L869, where sourceBase"
 },
 {
  "id": "M2-DEADCODE",
  "domain": "Pricing mechanism",
  "title": "DerivedPricingNewBusiness dead arm removed; no mispricing path (M-2)",
  "status": "pass",
  "severity": "none",
  "actual": "PASS, verified live 2026-06-14. The M-2 dead arm (DerivedPricingNewBusiness, Base_Price__c x tier, MDT gate) is GONE from the active V14 procedure (0 occurrences in the V14 block; all 5 whole-file occurrences are in inactive versions V9-V13). Exactly ONE live new-business tier IF-chain remains: Deri"
 },
 {
  "id": "NB-DERIVED-FORMULA",
  "domain": "Derived (new-business) pricing",
  "title": "Single live new-business derived formula (Source_List x tier); competing Base_Price x tier arm ",
  "status": "pass",
  "severity": "none",
  "actual": "PASS, re-confirmed on current live state (active procedure V14, ExpressionSet 9QLWC0000015cDl4AI). Two independent confirmations. (1) STRUCTURE \u2014 live ExpressionSetDefinition retrieved fresh this run: exactly ONE block is Active (the V14 block lines 69795-75346, fullName ..._V140, label 'Rev Mgmt De"
 },
 {
  "id": "NB-DERIVED-NET",
  "domain": "Derived (new-business) pricing",
  "title": "First-year maintenance derived NetUnitPrice value is correct (tier x Source_List_Price)",
  "status": "pass",
  "severity": "none",
  "actual": "PASS, re-confirmed live against the V14-active procedure (sole active ExpressionSetVersion 9QMWC00000023eX4AQ, VersionNumber=14, of ExpressionSet 9QLWC0000015cDl4AI; versions 1-13 IsActive=false). On Draft New quote 00781057 / 0Q0WC0000037rFZ0AY (Status=Draft, USD, QuoteTypeText__c='New'), all 9 act"
 },
 {
  "id": "NB-DERIVED-PREMIER",
  "domain": "Derived (new-business) pricing",
  "title": "Premier tier (0.30) first-year maintenance prices correctly",
  "status": "pass",
  "severity": "none",
  "actual": "PASS, confirmed on current live state (V14 active). The active V14 DerivedPricingFormula (live retrieve, absolute line 71642, resultIncluded=false, output=NetUnitPrice) reads IF(AttributeValue='Premier',0.30,IF(AttributeValue='Standard',0.20,IF(AttributeValue='Professional',0.20,0)))*Source_List_Pri"
 },
 {
  "id": "PROC-V14",
  "domain": "Pricing engine",
  "title": "V14 active + derived/COLA elements present & correctly wired",
  "status": "pass",
  "severity": "none",
  "actual": "PASS on current live state. (1) ACTIVE VERSION: a fresh ExpressionSetDefinition retrieve of Rev_Mgmt_Default_Pricing_Procedure (75,347 lines) shows exactly one version block with <status>Active</status> (line 69805), and that block is V14: fullName Rev_Mgmt_Default_Pricing_Procedure_Rev_Mgmt_Default"
 },
 {
  "id": "RN-COLA-COMMIT-RENEW",
  "domain": "Renewal COLA pricing",
  "title": "Renewal-maint line BORN with QuoteAction=Renew commits correct 67.38 (00781084)",
  "status": "pass",
  "severity": "none",
  "actual": "PASS, confirmed on current live state with a fresh reprice. Active procedure re-verified V14 (sole active ExpressionSetVersion 9QMWC00000023eX4AQ of ExpressionSet 9QLWC0000015cDl4AI). Quote 00781084 = 0Q0WC00000382MH0AY, Status=Draft, QuoteTypeText__c=Renewal, OriginalActionType=Renew, CurrencyIsoCo"
 },
 {
  "id": "RN-COLA-MATH",
  "domain": "Renewal COLA pricing",
  "title": "Renewal maintenance COLA net computed in-flight = (Base - priorPartner - priorDisc) x (1 + COLA",
  "status": "pass",
  "severity": "none",
  "actual": "PASS on current live state (procedure V14, ExpressionSet 9QLWC0000015cDl4AI; canary 00781109 confirmed Draft/Renewal/USD). The in-flight COLA-net computation reproduces the stamped COLACalculatedPrice__c EXACTLY on all 4 renewal-maintenance canary lines, and a fresh live Force reprice re-fired the c"
 },
 {
  "id": "RN-LIC",
  "domain": "Renewal pricing",
  "title": "Renewal license COLA uplift commits correctly",
  "status": "pass",
  "severity": "none",
  "actual": "PASS on current live state (V14 active, sole Active block fullName ..._Rev_Mgmt_Default_Pricing_V140 in a fresh metadata retrieve; 14 versions total). The renewal license COLA uplift commits correctly and is mechanistically separate from the broken renewal-maintenance commit. Renewal license/subscri"
 },
 {
  "id": "RN-SUB",
  "domain": "Renewal pricing",
  "title": "Renewal subscription (license) leg prices correctly = list x (1 - partner discount)",
  "status": "pass",
  "severity": "none",
  "actual": "PASS on current live state (V14 sole-active ESV 9QMWC00000023eX4AQ re-verified). The renewal SUBSCRIPTION leg prices correctly and is structurally distinct from the broken renewal-MAINTENANCE leg (SC-3404, RN-COLA-COMMIT). Two independent canaries verified by SOQL after fresh non-destructive Force r"
 },
 {
  "id": "SLP-CARRY",
  "domain": "Stamp / data flow",
  "title": "Source_List_Price carry-forward Quote->Order (M-4 QuoteToOrderFieldMapper)",
  "status": "pass",
  "severity": "none",
  "actual": "PASS on current live FortraUAT (procedure V14, ExpressionSet 9QLWC0000015cDl4AI). The field-copy data flow is fully functional and value-agnostic. (1) CODE: the live deployed QuoteToOrderFieldMapper (Id 01pWC000002IuvRYAS, ApiVersion 62, LengthWithoutComments 8408, LastModified 2026-06-12T20:21:26Z "
 },
 {
  "id": "STAMP-FLOW",
  "domain": "Stamp / data flow",
  "title": "Stamp_Maintenance_Pricing_Inputs correctly stamps Base_Price / COLACalculatedPrice / priors / C",
  "status": "pass",
  "severity": "none",
  "actual": "PASS, re-confirmed against current live FortraUAT (procedure V14 / ExpressionSetVersion 9QMWC00000023eX4AQ sole-active; Stamp_Maintenance_Pricing_Inputs V13 + Stamp_Source_List_Price V8 both Active). The stamp flow is the SOLE active version (V13), processType AutoLaunchedFlow, triggerType=RecordBef"
 },
 {
  "id": "RN-MULTIYEAR",
  "domain": "Renewal COLA pricing",
  "title": "Multi-year / out-year / MyCAP renewal COLA pricing is inert at the commit layer and out of scop",
  "status": "out-of-scope",
  "severity": "none",
  "actual": "RE-VERIFIED INERT + OUT-OF-SCOPE on current live state (2026-06-14). No multi-year/out-year COLA price is ever computed into or committed onto any line; the out-year field feeds only a Deal-Desk approval flag. (1) PROCEDURE: freshly retrieved live ExpressionSetDefinition Rev_Mgmt_Default_Pricing_Pro"
 }
];
const HEALTH={verdict:"CONDITIONAL — core paths price correctly; renewal-commit + minority-tier defects remain",color:"#bc4c00",message:"Architecture sound, computation correct throughout. Remaining functional defects: renewal-maintenance commit (correct COLA net not committed on auto-added/QuoteAction-less derived lines -> 0/54.58/60.64; only Renew-born lines commit 67.38; fix = creation-path), NB-DERIVED-TIER (3 of 7 tiers hard-coded -> minority tiers $0), and 2 per-solution COLA rate exceptions (category grain)."};
const STC={pass:"#1a7f37",fail:"#cf222e",partial:"#9a6700","out-of-scope":"#57606a"};
const STBG={pass:"#dafbe1",fail:"#ffebe9",partial:"#fff8c5","out-of-scope":"#eaeef2"};
const SEVC={critical:"#cf222e",high:"#bc4c00",medium:"#9a6700",low:"#57606a",none:"#1a7f37"};
const ST={fail:0,partial:1,pass:2,"out-of-scope":3}, SEV={critical:0,high:1,medium:2,low:3,none:4};
function Pill({status,label,mini}){return <span style={{display:"inline-block",padding:mini?"1px 7px":"2px 9px",borderRadius:20,fontSize:mini?9.5:10.5,fontWeight:700,color:STC[status],background:STBG[status]}}>{(label||status).toUpperCase()}</span>;}
export default function SC3346ExecutiveSummary(){
  const rows=[...RESULTS].sort((a,b)=>(ST[a.status]-ST[b.status])||(SEV[a.severity]-SEV[b.severity])||a.id.localeCompare(b.id));
  const n=s=>rows.filter(r=>r.status===s).length; const fails=rows.filter(r=>r.status==="fail");
  const card={background:"#fff",border:"1px solid #d0d7de",borderRadius:10,padding:16,marginTop:18};
  return (<div style={{fontFamily:"-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif",maxWidth:1080,margin:"0 auto",padding:"28px 20px 60px",color:"#1f2328",background:"#f6f8fa"}}>
    <h1 style={{margin:"0 0 4px",fontSize:23}}>SC-3346 Maintenance (Derived) Pricing — E2E Test Executive Summary</h1>
    <div style={{color:"#57606a",fontSize:13.5}}>Org <b>FortraUAT</b> · Procedure <b>V14</b> · functional pricing &amp; quote-to-order behavior · sorted by status</div>
    <div style={{margin:"18px 0",padding:"14px 18px",borderRadius:10,borderLeft:`6px solid ${HEALTH.color}`,...card,marginTop:18}}>
      <div style={{fontWeight:800,color:HEALTH.color,fontSize:15}}>{HEALTH.verdict}</div><div style={{marginTop:4}}>{HEALTH.message}</div></div>
    <div style={{display:"grid",gridTemplateColumns:"repeat(5,1fr)",gap:12,margin:"18px 0"}}>
      {[["Scenarios",rows.length,"#1f2328"],["Pass",n("pass"),"#1a7f37"],["Fail",n("fail"),"#cf222e"],["Partial",n("partial"),"#9a6700"],["Out-of-scope",n("out-of-scope"),"#57606a"]].map(([l,v,c])=>(
        <div key={l} style={{background:"#fff",border:"1px solid #d0d7de",borderRadius:10,padding:14,textAlign:"center"}}><div style={{fontSize:27,fontWeight:700,color:c}}>{v}</div><div style={{fontSize:10.5,textTransform:"uppercase",letterSpacing:.5,color:"#57606a",marginTop:4}}>{l}</div></div>))}</div>
    <table style={{width:"100%",borderCollapse:"collapse",background:"#fff",border:"1px solid #d0d7de",borderRadius:10,overflow:"hidden",fontSize:12.5}}>
      <thead><tr>{["ID","Scenario","Status","Severity"].map(h=>(<th key={h} style={{textAlign:"left",padding:"9px 12px",background:"#f6f8fa",borderBottom:"1px solid #d0d7de",fontSize:10.5,textTransform:"uppercase",letterSpacing:.4,color:"#57606a"}}>{h}</th>))}</tr></thead>
      <tbody>{rows.map(r=>(<tr key={r.id}>
        <td style={{padding:"8px 12px",borderBottom:"1px solid #eaeef2",fontFamily:"ui-monospace,Menlo,monospace",fontWeight:600,whiteSpace:"nowrap"}}>{r.id}</td>
        <td style={{padding:"8px 12px",borderBottom:"1px solid #eaeef2",maxWidth:520}}>{r.title}<div style={{color:"#8c959f",fontSize:10.5,marginTop:2}}>{r.domain}</div></td>
        <td style={{padding:"8px 12px",borderBottom:"1px solid #eaeef2"}}><Pill status={r.status}/></td>
        <td style={{padding:"8px 12px",borderBottom:"1px solid #eaeef2",fontWeight:700,fontSize:10.5,color:SEVC[r.severity]}}>{String(r.severity).toUpperCase()}</td></tr>))}</tbody></table>
    <div style={{...card,border:"2px solid #cf222e"}}><h3 style={{margin:"0 0 10px",fontSize:14}}>❌ Functional defects (by severity)</h3><ul style={{margin:0,paddingLeft:18}}>
      {fails.map(r=>(<li key={r.id} style={{marginBottom:9,fontSize:12.5}}><b>{r.id}</b> — {r.title} <Pill status="fail" label={r.severity} mini/><div style={{color:"#57606a",fontSize:11,marginTop:3}}>{r.actual}</div></li>))}</ul></div>
    <div style={{marginTop:18,color:"#57606a",fontSize:11.5}}>Computation layer correct throughout; failures are at the renewal commit layer + formula completeness. Fix directions: creation-path born-net for renewal maintenance; complete the V14 tier table.</div>
  </div>);
}
