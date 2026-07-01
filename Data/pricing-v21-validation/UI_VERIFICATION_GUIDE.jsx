import React, { useState, useEffect } from "react";

/**
 * V21 — Manual UI Verification Guide (interactive). Drop into any React app:
 *   import V21UIGuide from "./V21_UI_VERIFICATION_GUIDE.jsx";  ->  <V21UIGuide />
 * Check each defect in the FortraUAT UI, mark Fixed/Still-broken, then "Copy results".
 */

const ITEMS = [{"id": "K-01", "cat": "Edge Cases", "rec": "Quote 0Q0WC000003FoMA0A0 — cancellation, Qty −1", "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FoMA0A0/view", "action": "Reprice the quote", "field": "Reprice result + line Total Price", "pass": "Reprice SUCCEEDS; the −1 line Total Price shows a NEGATIVE credit (net × −1, e.g. −3000)", "fail": "Reprice ERRORS (SF-Pricing-00006 / SF-BRE-00004), or Total Price = 0"}, {"id": "F-12", "cat": "Transaction Type", "rec": "Quote 0Q0WC000003FapR0AS — amend / remove, Qty −50000", "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FapR0AS/view", "action": "Reprice the quote", "field": "Reprice result + line Net / Total", "pass": "Reprice SUCCEEDS and the removed line shows a prorated NEGATIVE delta", "fail": "Reprice ABORTS at StampBaseFilter; Net Unit Price = blank, Total Price = 0"}, {"id": "G-01", "cat": "Multi-Currency", "rec": "QLI 0QLWC000003kmG14AI — EUR line (Quote 0Q0WC000003FcrF0AS)", "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC000003kmG14AI/view", "action": "Reprice, open the line", "field": "Unit Price vs Net Unit Price", "pass": "Unit Price == Net Unit Price (~1471.995 EUR)", "fail": "Unit Price is HIGHER than Net (FX applied twice on the display channel)"}, {"id": "G-02", "cat": "Multi-Currency", "rec": "Quote 0Q0WC000003FcrF0AS — EUR, AAM", "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FcrF0AS/view", "action": "Reprice, open the EUR line(s)", "field": "Net Unit Price / List Price", "pass": "Net derived from the EUR List Price (~2943.99); no line at $0", "fail": "Net = 1471.995 (= USD 1575 × 0.9346 → USD ABA override leaked into the EUR line), or a combo line prices $0"}, {"id": "H-01", "cat": "Discounts", "rec": "Quote 0Q0WC000003Fs1Z0AS — One-Time, list 50000, manual amount disc 5000, Qty 2", "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003Fs1Z0AS/view", "action": "Reprice TWICE (reprice, then reprice again)", "field": "Net Unit Price", "pass": "Net Unit Price stays 45000 on BOTH reprices (50000 − 5000)", "fail": "Net drops below 45000 on the 2nd reprice (40500, then lower) → discount compounds"}, {"id": "I-03", "cat": "Proration", "rec": "QLI 0QLWC000002LCwH4AW — mid-term Term-Defined, ~270/365 of term", "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/QuoteLineItem/0QLWC000002LCwH4AW/view", "action": "Reprice, open the line", "field": "Net Total Price / Total Line Amount", "pass": "Prorated (~554.79 = 250 × 3 × 0.7397)", "fail": "Full annual (750) → fractional PTC derived but net not multiplied by it"}, {"id": "E-04", "cat": "Deal / Customer", "rec": "Quote 0Q0WC0000039bwH0AQ — Deal_Type = Fortra Originated, partner", "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000039bwH0AQ/view", "action": "Reprice, open the BoKS Perpetual line", "field": "Net Unit Price", "pass": "Reflects the Non_Orig (Fortra-Originated) band → different from the channel result", "fail": "Net = 301.75 (= 355 × 0.85, the CHANNEL 15% band) → Deal_Type had no effect"}, {"id": "F-09", "cat": "Transaction Type", "rec": "Quote 0Q0WC000003AaoT0AS — EUR partner", "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003AaoT0AS/view", "action": "Reprice, open the Cobalt Strike EUR line", "field": "Net Unit Price", "pass": "~4521.59 (EUR list × 0.82, single FX)", "fail": "~4159.87 (double FX: USD list × 0.92 × 0.82 × 0.9346) → ~8% too low"}, {"id": "J-06", "cat": "Derived / Maint", "rec": "Quote 0Q0WC000003FdCD0A0 — maint line QLI 0QLWC000003kmeE4AQ", "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FdCD0A0/view", "action": "Reprice, open the maintenance line", "field": "Net Unit Price", "pass": "62.48 (= 71 × 0.88, New-Maintenance 12% band)", "fail": "60.35 (= 71 × 0.85, license Software 15% band carried onto maint)"}, {"id": "J-09", "cat": "Derived / Maint", "rec": "Quote 0Q0WC0000029Agw0AE — QLI 0QLWC000003KEbO4AW (GS-GSE-RNM-EF8)", "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000029Agw0AE/view", "action": "Reprice, open the line", "field": "Net Unit Price", "pass": "A non-null, priced Net Unit Price", "fail": "Net Unit Price = blank / $0 (derived PBE has no PBEDP contributor config)"}, {"id": "J-10", "cat": "Derived / Maint", "rec": "Quote 0Q0WC000003FZN70AO — EUR maint line QLI 0QLWC000003kinW4AQ", "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FZN70AO/view", "action": "Reprice, open the EUR maintenance line", "field": "Net Unit Price", "pass": "Committed, non-zero (COLA-derived net)", "fail": "$0 (COLA value computed but not committed → EUR PBE IsDerived = false)"}, {"id": "A-07", "cat": "Pricing Source", "rec": "FIM CCM New-Maintenance line (vs BoKS control 0Q0WC000003FKRJ0A4)", "url": "https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC000003FKRJ0A4/view", "action": "Reprice a FIM CCM maint line; also check the FIM CCM Product for the 'Maintenance Type Defn' attribute", "field": "Net Unit Price + Product attribute", "pass": "FIM CCM maint prices a non-zero derived tier (like BoKS 0.20 × list)", "fail": "FIM CCM maint = $0 or 100%-of-list (product missing the Maintenance Type Defn attribute)"}, {"id": "G-08", "cat": "Multi-Currency", "rec": "Setup → Company Settings → Manage Currencies (NOT a quote)", "url": "https://fortra--uat.sandbox.my.salesforce.com/lightning/setup/CurrencySettings/home", "action": "Open Manage Currencies", "field": "Conversion Rate for ARS, CHF, GBP, ILS, JPY, NZD", "pass": "Correct rates (ARS 666.6667, CHF 0.885, GBP 0.7874, ILS 3.6251, JPY 149.2537, NZD 1.6667)", "fail": "Any of them = 1.0 (placeholder) → reporting/invoicing FX wrong (pricing proc itself unaffected)"}];

const S = {
  page:{fontFamily:"-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif",color:"#1a1f29",background:"#eef1f5",lineHeight:1.5,margin:0},
  wrap:{maxWidth:1080,margin:"0 auto",padding:"0 18px 90px"},
  header:{background:"linear-gradient(120deg,#10243e,#1c3a5e)",color:"#fff",padding:"26px 18px"},
  howto:{background:"#fff",borderRadius:12,padding:"16px 20px",margin:"20px 0",boxShadow:"0 1px 3px rgba(16,36,62,.08)"},
  bar:{position:"sticky",top:0,zIndex:10,background:"#fff",border:"1px solid #e1e7ef",borderRadius:12,padding:"12px 18px",margin:"16px 0",display:"flex",gap:14,alignItems:"center",flexWrap:"wrap",boxShadow:"0 2px 8px rgba(16,36,62,.10)"},
  pill:(bg)=>({padding:"3px 11px",borderRadius:20,fontSize:12.5,fontWeight:800,color:"#fff",background:bg}),
  openbtn:{marginLeft:"auto",background:"#0b6bcb",color:"#fff",textDecoration:"none",borderRadius:8,padding:"8px 15px",fontSize:13,fontWeight:700,whiteSpace:"nowrap"},
  panel:(kind)=>({borderRadius:10,padding:"11px 14px",fontSize:13.5,background:kind==="p"?"#e7f6ee":"#fdecea",border:kind==="p"?"1px solid #b6e2ca":"1px solid #f4c7c1"}),
};
const cardStyle = (m) => ({background: m==="fixed"?"#f4fbf7":m==="broken"?"#fdf6f5":"#fff", border:"1px solid #e7ecf2", borderLeft:`7px solid ${m==="fixed"?"#16794d":m==="broken"?"#b3261e":"#c9d2de"}`, borderRadius:14, padding:"18px 20px", margin:"14px 0", boxShadow:"0 1px 3px rgba(16,36,62,.07)"});
const mkStyle = (on,kind) => ({border:`2px solid ${on?(kind==="fixed"?"#16794d":kind==="broken"?"#b3261e":"#8a97a8"):"#d4dce6"}`, background:on?(kind==="fixed"?"#16794d":kind==="broken"?"#b3261e":"#8a97a8"):"#fff", color:on?"#fff":"#41506a", borderRadius:9, padding:"8px 16px", fontSize:13, fontWeight:800, cursor:"pointer"});

export default function V21UIGuide() {
  const [marks, setMarks] = useState(() => { try { return JSON.parse(localStorage.getItem("v21ui_marks_v1")||"{}"); } catch { return {}; } });
  const [out, setOut] = useState("");
  useEffect(() => { localStorage.setItem("v21ui_marks_v1", JSON.stringify(marks)); }, [marks]);
  const mark = (id,val) => setMarks(m => ({...m, [id]: m[id]===val ? "" : val }));
  const vals = Object.values(marks);
  const nFixed = vals.filter(v=>v==="fixed").length, nBroken = vals.filter(v=>v==="broken").length, nChecked = nFixed+nBroken;
  const copy = () => {
    const txt = "V21 UI verification results (checked in FortraUAT):\n" + ITEMS.map(it => {
      const m = marks[it.id]; const tag = m==="fixed"?"✅ FIXED (mark PASS)":m==="broken"?"❌ STILL BROKEN":m==="skip"?"— skipped":"(not checked)";
      return `${it.id}: ${tag}`;
    }).join("\n");
    setOut(txt); if (navigator.clipboard) navigator.clipboard.writeText(txt);
  };
  return (
    <div style={S.page}>
      <div style={S.header}><div style={{maxWidth:1080,margin:"0 auto"}}>
        <h1 style={{margin:"0 0 4px",fontSize:26}}>V21 — Manual UI Verification</h1>
        <div style={{color:"#bcd3ec",fontSize:14}}>FortraUAT · Rev_Mgmt_Default_Pricing_Procedure V21 (active, LastModified 22:01Z) · 13 defects to confirm</div>
      </div></div>
      <div style={S.wrap}>
        <div style={S.howto}><h2 style={{fontSize:16,margin:"0 0 8px"}}>How to check each one</h2>
          <ol style={{margin:0,paddingLeft:20,fontSize:13.5,color:"#33415c"}}>
            <li><b>Open</b> the record (blue button on each card).</li>
            <li><b>Reprice</b> — your team's reprice action ("Reprice" / "Reprice All" / "Calculate Prices"; or open the Quote Line Editor, edit trivially, Save).</li>
            <li>Open the <b>Quote Line Item</b>, read the <b>Field to read</b>, compare to the green/red panels.</li>
            <li>Tap <b>✅ Fixed</b> or <b>❌ Still broken</b>; then <b>Copy results</b> and paste back to me.</li>
          </ol></div>
        <div style={S.bar}>
          <span style={{fontSize:14,fontWeight:700}}>Checked <b style={{fontSize:20}}>{nChecked}</b>/13</span>
          <span style={S.pill("#16794d")}>✅ {nFixed} fixed</span>
          <span style={S.pill("#b3261e")}>❌ {nBroken} broken</span>
          <button style={{marginLeft:"auto",...{background:"#eef1f5",color:"#41506a",border:"1px solid #d4dce6",borderRadius:8,padding:"9px 14px",fontSize:12.5,fontWeight:700,cursor:"pointer"}}} onClick={()=>{ if(window.confirm("Clear all marks?")) setMarks({}); }}>Reset</button>
          <button style={{background:"#0b6bcb",color:"#fff",border:"none",borderRadius:8,padding:"9px 16px",fontSize:13,fontWeight:700,cursor:"pointer"}} onClick={copy}>Copy results for Claude</button>
        </div>
        {ITEMS.map((it,i) => { const m = marks[it.id]||""; return (
          <div key={it.id} style={cardStyle(m)}>
            <div style={{display:"flex",alignItems:"center",gap:10,flexWrap:"wrap",marginBottom:12}}>
              <span style={{fontSize:13,fontWeight:800,color:"#8a97a8"}}>#{i+1}</span>
              <span style={{fontSize:15,fontWeight:800,color:"#fff",background:"#10243e",borderRadius:7,padding:"4px 11px"}}>{it.id}</span>
              <span style={{fontSize:11.5,color:"#5b6675",background:"#eef1f5",borderRadius:6,padding:"3px 9px",fontWeight:600}}>{it.cat}</span>
              <a style={S.openbtn} href={it.url} target="_blank" rel="noopener noreferrer">▶ Open record</a>
            </div>
            <div style={{fontSize:12.5,color:"#41506a",margin:"-4px 0 12px"}}>{it.rec}</div>
            <div style={{display:"grid",gridTemplateColumns:"110px 1fr",gap:12,fontSize:13.5,marginBottom:10}}>
              <span style={{fontSize:11,fontWeight:800,textTransform:"uppercase",color:"#7a8696"}}>Action</span><span>{it.action}</span></div>
            <div style={{display:"grid",gridTemplateColumns:"110px 1fr",gap:12,fontSize:13.5,marginBottom:10}}>
              <span style={{fontSize:11,fontWeight:800,textTransform:"uppercase",color:"#7a8696"}}>Field</span><span><b>{it.field}</b></span></div>
            <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:12,margin:"12px 0 14px"}}>
              <div style={S.panel("p")}><div style={{fontSize:11,fontWeight:800,textTransform:"uppercase",color:"#16794d",marginBottom:5}}>✅ Fixed (PASS) looks like</div>{it.pass}</div>
              <div style={S.panel("f")}><div style={{fontSize:11,fontWeight:800,textTransform:"uppercase",color:"#b3261e",marginBottom:5}}>❌ Still-broken (FAIL) looks like</div>{it.fail}</div>
            </div>
            <div style={{display:"flex",gap:8,flexWrap:"wrap"}}>
              <button style={mkStyle(m==="fixed","fixed")} onClick={()=>mark(it.id,"fixed")}>✅ Fixed</button>
              <button style={mkStyle(m==="broken","broken")} onClick={()=>mark(it.id,"broken")}>❌ Still broken</button>
              <button style={mkStyle(m==="skip","skip")} onClick={()=>mark(it.id,"skip")}>— Skip</button>
            </div>
          </div>); })}
        <div style={{fontSize:12.5,color:"#7a8696",background:"#fff",border:"1px dashed #cdd8e6",borderRadius:10,padding:"12px 16px",marginTop:16}}>
          <b>Two are config/data checks, not a reprice:</b> G-08 = Manage Currencies rates; A-07 = whether the FIM CCM product carries the "Maintenance Type Defn" attribute (BoKS has it, FIM CCM doesn't).</div>
        {out && <textarea readOnly value={out} style={{width:"100%",height:120,marginTop:10,fontFamily:"ui-monospace,Menlo,monospace",fontSize:12,border:"1px solid #d4dce6",borderRadius:8,padding:10}} />}
      </div>
    </div>
  );
}
