import React from "react";

/** V21 Fix Verification — re-check of the 13 defects after the 2026-07-01 fixes. Drop-in: <V21FixVerification />. */
const ITEMS = [{"id": "K-01", "cat": "Edge Cases", "pri": "P0", "status": "FIXED", "title": "Cancellation credit", "before": "Reprice aborted (SF-BRE-00004); no credit", "after": "Reprice OK; cancel line net −15000 (negative credit)", "reason": ""}, {"id": "F-12", "cat": "Transaction Type", "pri": "P1", "status": "FIXED", "title": "Amend-remove negative delta", "before": "Reprice aborted at StampBaseFilter", "after": "Reprice OK; net −75000 (credit produced)", "reason": "", "note": "Primary crash fixed. Minor residual: PricingTermCount still null (proration leg, same family as I-03) — the credit is produced but not term-prorated."}, {"id": "G-02", "cat": "Multi-Currency", "pri": "P0", "status": "FIXED", "title": "Configured pricing currency-blindness", "before": "EUR line net = USD 1575 override; 2nd combo = $0", "after": "Both combos net 2708.47 from EUR list; no $0, no raw-USD-in-net", "reason": "", "note": "Core symptoms ($0 + USD-value leaking into net) resolved. Residual to sanity-check with G-01: Source_List_Price still shows 1575 on one combo and the EUR net = list×0.92 — tied to the G-01 display item below."}, {"id": "H-01", "cat": "Discounts", "pri": "P0", "status": "FIXED", "title": "Manual discount compounding", "before": "Net eroded 20000 → 15000 → 10000 on repeated reprices", "after": "Net stable 45000 across reprices (50000 − 5000)", "reason": ""}, {"id": "E-04", "cat": "Deal / Customer", "pri": "P1", "status": "FIXED", "title": "Fortra-Originated partner band", "before": "Net 301.75 = 355×0.85 (channel 15%); Deal_Type ignored", "after": "Net 312.4 = 355×0.88 (Non_Orig 12%); PartnerDiscountPercent=12", "reason": ""}, {"id": "F-09", "cat": "Transaction Type", "pri": "P1", "status": "FIXED", "title": "Non-USD partner double-FX", "before": "Cobalt EUR net 4159.87 (USD×0.92×0.82×0.9346)", "after": "Cobalt EUR net 4521.59 (EUR list×0.82, single FX)", "reason": ""}, {"id": "J-06", "cat": "Derived / Maint", "pri": "P0", "status": "FIXED", "title": "Partner derived-maint band", "before": "Maint net 60.35 = 71×0.85 (license 15% band)", "after": "Maint net 62.48 = 71×0.88 (New-Maint 12% band)", "reason": ""}, {"id": "J-10", "cat": "Derived / Maint", "pri": "P0", "status": "FIXED", "title": "EUR derived-maint $0", "before": "EUR maint net $0 (COLA computed, not committed)", "after": "EUR maint net 3177.64 (committed, non-zero)", "reason": ""}, {"id": "G-01", "cat": "Multi-Currency", "pri": "P0", "status": "RESIDUAL", "title": "Unit-Price display out of sync", "before": "UnitPrice double-applied FX", "after": "UnitPrice 1471.995 ≠ NetUnitPrice 2708.47 — display no longer matches net", "reason": "NOT blocked — a follow-on procedure tweak. Fixing G-02 changed the EUR net, but the \"Currency Conversion – Unit Price Display\" step still sources the old USD-derived base, so the display desynced from the net. Fixable in one more proc pass (source the display from the same base as the net, or set UnitPrice = NetUnitPrice after the net currency steps)."}, {"id": "I-03", "cat": "Proration", "pri": "P1", "status": "RESIDUAL", "title": "Mid-term net not prorated by PTC", "before": "PTC 0.7397 derived; net full 750", "after": "Still net full 750 (not prorated 554.79); PTC 0.7397", "reason": "NOT blocked — the proration fix did not land on the plain list-priced path. The TermDefined proration leg still multiplies net×PTC only on the adjustment path. Fixable in a proc pass (gate the multiply on SellingModelType=TermDefined regardless of whether an adjustment exists) — best done on a fresh UI-built line, not this stale record."}, {"id": "A-07", "cat": "Pricing Source", "pri": "P2", "status": "BLOCKED", "title": "Maintenance-Type attribute gap", "before": "MTD attribute on 186 / 1683 New-Maint products", "after": "277 / 1683 (the ~91 cleanly-backfillable done) — FIM CCM still missing", "reason": "CAN'T SELF-FIX (platform + data-owner). The ~91 viable products were backfilled, but the FIM CCM family (~1,400) cannot receive the Maintenance-Type attribute via data load — its ProductClassificationAttribute is per-classification and non-nillable, and ~935 products have a null BasedOnId. Needs a product-owner decision: add the attribute to those products upstream, OR add a documented Standard-0.20 default to V21 step 39. Not a data-load you can complete."}, {"id": "J-09", "cat": "Derived / Maint", "pri": "P0", "status": "BLOCKED", "title": "Derived line with no PBEDP", "before": "Derived line net null (0 PBEDP rows)", "after": "Still null (backfill not run)", "reason": "CAN'T SELF-FIX (gated on Marc DeBrey). The PBEDP backfill is a data load, but the staged ~476-row CSV was ~47% mis-scoped (221 rows pointed at the INACTIVE Standard Price Book); only ~253 rows are safely actionable and the scope is pending Marc DeBrey's sign-off. Blind-inserting the mis-scoped rows would create bad contributor config — so it waits on his review."}, {"id": "G-08", "cat": "Multi-Currency", "pri": "P2", "status": "BLOCKED", "title": "Org FX rates at 1.0", "before": "ARS/CHF/GBP/ILS/JPY/NZD/SEK = 1.0", "after": "Still 1.0 (all 7)", "reason": "CAN'T SELF-FIX (owner + access). These are org-level currency conversion rates in Setup → Manage Currencies, which require the Manage Currencies permission you don't hold, and are owned by the FX/finance admin (last set by Aaron Broom on 2/13/2026). Escalated via message. Note this affects reporting/DocGen/Workday-invoicing FX only — the pricing procedure is unaffected."}];
const SCOL = { FIXED:"#16794d", RESIDUAL:"#c77700", BLOCKED:"#b3261e" };
const SLAB = { FIXED:"\u2705 FIXED", RESIDUAL:"\u25d1 OPEN (fixable)", BLOCKED:"\u26d4 CAN'T SELF-FIX" };
const ORD = { FIXED:0, RESIDUAL:1, BLOCKED:2 };

export default function V21FixVerification() {
  const nf = ITEMS.filter(i=>i.status==="FIXED").length;
  const nr = ITEMS.filter(i=>i.status==="RESIDUAL").length;
  const nb = ITEMS.filter(i=>i.status==="BLOCKED").length;
  const items = [...ITEMS].sort((a,b)=> (ORD[a.status]-ORD[b.status]) || a.pri.localeCompare(b.pri));
  const S={ page:{fontFamily:"-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif",color:"#1a1f29",background:"#eef1f5",margin:0,lineHeight:1.5},
    wrap:{maxWidth:1080,margin:"0 auto",padding:"0 18px 80px"},
    header:{background:"linear-gradient(120deg,#10243e,#1c3a5e)",color:"#fff",padding:"28px 18px"},
    section:{background:"#fff",borderRadius:12,padding:"22px 24px",margin:"20px 0",boxShadow:"0 1px 3px rgba(16,36,62,.08)"},
    tile:(c)=>({border:"1px solid #e7ecf2",borderTop:`5px solid ${c}`,borderRadius:10,padding:"15px 12px",textAlign:"center"}),
    bx:(k)=>({borderRadius:9,padding:"10px 13px",fontSize:13,background:k==="b"?"#fdf0ee":"#eef7f1",border:k==="b"?"1px solid #f3ccc5":"1px solid #bfe2ce"}) };
  return (
    <div style={S.page}>
      <div style={S.header}><div style={{maxWidth:1080,margin:"0 auto"}}>
        <h1 style={{margin:"0 0 4px",fontSize:27}}>V21 Fix Verification</h1>
        <div style={{color:"#bcd3ec",fontSize:14}}>Rev_Mgmt_Default_Pricing_Procedure V21 (redeployed 2026-07-01 02:25Z) · 13 defects re-checked live</div>
      </div></div>
      <div style={S.wrap}>
        <div style={S.section}>
          <h2 style={{fontSize:19,margin:"0 0 14px",paddingBottom:9,borderBottom:"2px solid #eef1f5"}}>Executive summary</h2>
          <div style={{fontSize:16,background:"#f8fafc",borderLeft:"5px solid #16794d",padding:"13px 17px",borderRadius:8,marginBottom:18}}>
            8 of 13 defects are fixed and verified on live data. 2 are procedure residuals still open but fixable in one more pass. 3 cannot be self-fixed — data/config owned by others (FX admin, Marc DeBrey) or blocked by a platform limit.</div>
          <div style={{display:"grid",gridTemplateColumns:"repeat(4,1fr)",gap:12}}>
            <div style={S.tile("#16794d")}><div style={{fontSize:30,fontWeight:800,color:"#16794d"}}>{nf}</div><div style={{fontSize:12,color:"#5b6675",fontWeight:600,marginTop:5}}>FIXED &amp; verified</div></div>
            <div style={S.tile("#c77700")}><div style={{fontSize:30,fontWeight:800,color:"#c77700"}}>{nr}</div><div style={{fontSize:12,color:"#5b6675",fontWeight:600,marginTop:5}}>OPEN — still fixable</div></div>
            <div style={S.tile("#b3261e")}><div style={{fontSize:30,fontWeight:800,color:"#b3261e"}}>{nb}</div><div style={{fontSize:12,color:"#5b6675",fontWeight:600,marginTop:5}}>CAN'T SELF-FIX</div></div>
            <div style={S.tile("#10243e")}><div style={{fontSize:30,fontWeight:800}}>13</div><div style={{fontSize:12,color:"#5b6675",fontWeight:600,marginTop:5}}>defects checked</div></div>
          </div>
        </div>
        <div style={S.section}>
          <h2 style={{fontSize:19,margin:"0 0 14px",paddingBottom:9,borderBottom:"2px solid #eef1f5"}}>Per-defect — before → after + why fails remain</h2>
          {items.map(it => { const c=SCOL[it.status]; return (
            <div key={it.id} style={{background:"#fff",border:"1px solid #e7ecf2",borderLeft:`7px solid ${c}`,borderRadius:13,padding:"16px 18px",margin:"12px 0"}}>
              <div style={{display:"flex",alignItems:"center",gap:9,flexWrap:"wrap",marginBottom:11}}>
                <span style={{fontSize:14,fontWeight:800,color:"#fff",background:"#10243e",borderRadius:7,padding:"3px 10px"}}>{it.id}</span>
                <span style={{fontSize:11,color:"#5b6675",background:"#eef1f5",borderRadius:6,padding:"3px 9px",fontWeight:600}}>{it.cat}</span>
                <span style={{fontSize:11,color:"#7a8696",fontWeight:700}}>{it.pri}</span>
                <span style={{marginLeft:"auto",fontSize:12,fontWeight:800,color:"#fff",background:c,borderRadius:7,padding:"4px 12px"}}>{SLAB[it.status]}</span>
              </div>
              <div style={{fontSize:15,fontWeight:700,marginBottom:11,color:"#16202e"}}>{it.title}</div>
              <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:12,marginBottom:10}}>
                <div style={S.bx("b")}><div style={{fontSize:10.5,fontWeight:800,textTransform:"uppercase",color:"#b3261e",marginBottom:4}}>Before</div>{it.before}</div>
                <div style={S.bx("a")}><div style={{fontSize:10.5,fontWeight:800,textTransform:"uppercase",color:"#16794d",marginBottom:4}}>After (live 2026-07-01)</div>{it.after}</div>
              </div>
              {it.reason && <div style={{fontSize:13,color:it.status==="BLOCKED"?"#7a1a13":"#5a3a00",background:it.status==="BLOCKED"?"#fdecea":"#fdf6e8",border:it.status==="BLOCKED"?"1px solid #f4c7c1":"1px solid #f0dca8",borderRadius:9,padding:"10px 13px",marginTop:6}}><b>Why it isn't fixed:</b> {it.reason}</div>}
              {it.note && <div style={{fontSize:12.5,color:"#5b6675",marginTop:8,fontStyle:"italic"}}>{it.note}</div>}
            </div>); })}
        </div>
      </div>
    </div>
  );
}
