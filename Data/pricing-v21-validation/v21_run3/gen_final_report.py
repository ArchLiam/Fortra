#!/usr/bin/env python3
# V21_FINAL_STATUS.html + .jsx — full 104-scenario status after fixes (2026-07-01).
import json, html, os
BASE=os.path.dirname(__file__); OUT=os.path.dirname(BASE)
D=json.load(open(f'{BASE}/report_data.json'))
matrix={m['id']:m for m in D['matrix']}
def esc(s): return html.escape(str(s if s is not None else ''))

# --- apply the 2026-07-01 fix-verification outcome ---
FIXED={  # were FAIL -> now PASS (with the live after-state)
 'K-01':'Reprice OK; cancel line net −15000 (negative credit).',
 'F-12':'Reprice OK; net −75000 (credit produced). Minor residual: PTC null (not term-prorated).',
 'G-02':'Both EUR combos net 2708.47 from EUR list; no $0, no raw-USD-in-net.',
 'H-01':'Net stable 45000 across repeated reprices (was compounding 20000→15000→10000).',
 'E-04':'BoKS Perp net 312.4 = 355×0.88 (Non_Orig 12%); PartnerDiscountPercent=12.',
 'F-09':'Cobalt EUR net 4521.59 (EUR list×0.82, single FX).',
 'J-06':'Maint net 62.48 = 71×0.88 (New-Maintenance 12% band).',
 'J-10':'EUR maint net 3177.64 (committed, non-zero).',
}
DEFERRED={  # still failing, accepted by decision (architectural)
 'G-01':('UnitPrice 1471.995 ≠ net 2708.47 — display desynced after the G-02 net change.',
         'Deferred by decision — needs an architectural call (which base the Unit-Price-Display step should source) plus currency-dataset knowledge. Accepted as-is.'),
 'I-03':('Mid-term net still full 750, not prorated by PTC 0.7397.',
         'Deferred by decision — the proration multiply gating needs an architectural change (fire on all TermDefined lines, not just the adjustment path) and validation against real term data. Accepted as-is.'),
}
FAIL={  # couldn't fix — owner/data/platform
 'A-07':('MTD attribute backfilled 186→277 (the ~91 viable); FIM CCM family still missing.',
         "Couldn't fix — the FIM CCM family (~1,400 products) can't receive the Maintenance-Type attribute via data load (ProductClassificationAttribute is per-classification and non-nillable; ~935 have a null BasedOnId). Needs a product-owner decision (add the attribute upstream) or a documented Standard-0.20 default in V21 step 39."),
 'J-09':('Derived line still prices null (0 PBEDP rows).',
         "Couldn't fix — the PBEDP backfill is gated on Marc DeBrey. The staged ~476-row CSV was ~47% mis-scoped (221 rows pointed at the INACTIVE Standard Price Book); only ~253 are safely actionable, pending his scope sign-off. Blind-inserting would create bad contributor config."),
 'G-08':('7 currencies (ARS/CHF/GBP/ILS/JPY/NZD/SEK) still at rate 1.0.',
         "Couldn't fix — these are org-level currency conversion rates in Setup → Manage Currencies, owned by the FX/finance admin and requiring the Manage Currencies permission (not held). Escalated to the owner. Affects reporting / DocGen / Workday-invoicing FX only — the pricing procedure is unaffected."),
}
OUT_OF_SCOPE={'A-04':'contracted','A-06':'contracted','D-06':'contracted','I-05':'contracted',
              'B-04':'evergreen','B-05':'evergreen','B-06':'evergreen','I-04':'evergreen','I-07':'evergreen'}

for sid,after in FIXED.items():
    matrix[sid]['verdict']='PASS'; matrix[sid]['actual']=after; matrix[sid]['rootCause']='N-A(pass)'; matrix[sid]['reason']=''
for sid,(after,why) in DEFERRED.items():
    matrix[sid]['verdict']='DEFERRED'; matrix[sid]['actual']=after; matrix[sid]['reason']=why
for sid,(after,why) in FAIL.items():
    matrix[sid]['verdict']='FAIL'; matrix[sid]['actual']=after; matrix[sid]['reason']=why
for sid,kind in OUT_OF_SCOPE.items():
    matrix[sid]['verdict']='N-A'; matrix[sid]['reason']=f'Out of scope for Fortra ({kind} not used).'
for m in matrix.values(): m.setdefault('reason','')

rows=[matrix[k] for k in matrix]
from collections import Counter
tal=Counter(m['verdict'] for m in rows)
ORDER=['FAIL','DEFERRED','PASS','BLOCKED','N-A']
VCOL={'PASS':'#16794d','FAIL':'#b3261e','DEFERRED':'#c77700','BLOCKED':'#8a6d00','N-A':'#5b6675'}
DATA_JS=json.dumps(rows, ensure_ascii=False)

CSS='''*{box-sizing:border-box}body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif;color:#1a1f29;background:#eef1f5;line-height:1.5}
.wrap{max-width:1200px;margin:0 auto;padding:0 18px 80px}
header{background:linear-gradient(120deg,#10243e,#1c3a5e);color:#fff;padding:28px 18px}h1{margin:0 0 4px;font-size:27px}.sub{color:#bcd3ec;font-size:14px}
section{background:#fff;border-radius:12px;padding:22px 24px;margin:20px 0;box-shadow:0 1px 3px rgba(16,36,62,.08)}
h2{font-size:19px;margin:0 0 14px;padding-bottom:9px;border-bottom:2px solid #eef1f5}
.verdict{font-size:16px;background:#f8fafc;border-left:5px solid #16794d;padding:13px 17px;border-radius:8px;margin-bottom:18px}
.tiles{display:grid;grid-template-columns:repeat(5,1fr);gap:11px}
.tile{border:1px solid #e7ecf2;border-radius:10px;padding:14px 10px;text-align:center;border-top:5px solid #c9d2de}
.tnum{font-size:28px;font-weight:800}.tlab{font-size:11.5px;color:#5b6675;font-weight:600;margin-top:4px}
.leg{display:flex;gap:14px;flex-wrap:wrap;margin-top:14px;font-size:12.5px;color:#41506a}
.legchip{font-weight:800;color:#fff;border-radius:6px;padding:2px 9px}
.fcard{border:1px solid #e7ecf2;border-left:6px solid #b3261e;border-radius:11px;padding:14px 16px;margin:11px 0}
.fcard.def{border-left-color:#c77700}
.fh{display:flex;gap:9px;align-items:center;flex-wrap:wrap;margin-bottom:8px}
.idb{font-size:14px;font-weight:800;color:#fff;background:#10243e;border-radius:7px;padding:3px 10px}
.sb{font-size:11px;font-weight:800;color:#fff;border-radius:6px;padding:3px 10px}
.catb{font-size:11px;color:#5b6675;background:#eef1f5;border-radius:6px;padding:3px 9px}
.fobs{font-size:13px;color:#41506a;margin-bottom:7px}
.fwhy{font-size:13px;border-radius:9px;padding:10px 13px}
.fwhy.f{background:#fdecea;border:1px solid #f4c7c1;color:#7a1a13}.fwhy.d{background:#fdf6e8;border:1px solid #f0dca8;color:#5a3a00}
.filters{display:flex;gap:7px;flex-wrap:wrap;align-items:center;margin-bottom:12px}
.fbtn{font-size:12px;font-weight:700;border:1.5px solid #d4dce6;background:#fff;color:#41506a;border-radius:18px;padding:5px 12px;cursor:pointer}
.fbtn.on{background:#10243e;color:#fff;border-color:#10243e}
.search{margin-left:auto;border:1.5px solid #d4dce6;border-radius:18px;padding:6px 13px;font-size:13px;min-width:200px}
table{width:100%;border-collapse:collapse;font-size:12.5px}th,td{text-align:left;padding:7px 9px;border-bottom:1px solid #eef1f5;vertical-align:top}
th{font-size:10.5px;text-transform:uppercase;letter-spacing:.4px;color:#7a8696;background:#fafbfc;position:sticky;top:0;cursor:pointer}
.vcell{font-weight:800;font-size:10.5px;padding:3px 7px;border-radius:5px;color:#fff;display:inline-block;min-width:64px;text-align:center}
.mono{font-family:ui-monospace,Menlo,monospace;font-weight:700}.rc{font-size:10.5px;color:#7a8696}
@media(max-width:820px){.tiles{grid-template-columns:repeat(2,1fr)}}'''

def tiles():
    T=[('PASS','Pass','#16794d'),('FAIL','Fail (couldn\'t fix)','#b3261e'),('DEFERRED','Deferred','#c77700'),('BLOCKED','Blocked (env/data)','#8a6d00'),('N-A','N-A (out of scope)','#5b6675')]
    return ''.join(f'<div class="tile" style="border-top-color:{c}"><div class="tnum" style="color:{c}">{tal.get(k,0)}</div><div class="tlab">{esc(l)}</div></div>' for k,l,c in T)

def fails_html():
    out=[]
    out.append('<h3 style="font-size:15px;margin:4px 0 10px;color:#b3261e">Fails — couldn\'t fix (3)</h3>')
    for sid in ['A-07','J-09','G-08']:
        m=matrix[sid]; after,why=FAIL[sid]
        out.append(f'''<div class="fcard"><div class="fh"><span class="idb">{sid}</span>
          <span class="sb" style="background:#b3261e">FAIL</span><span class="catb">{esc(m["category"])}</span><span class="rc">{esc(m["pri"])}</span></div>
          <div class="fobs"><b>State:</b> {esc(after)}</div><div class="fwhy f"><b>Why not fixed:</b> {esc(why)}</div></div>''')
    out.append('<h3 style="font-size:15px;margin:18px 0 10px;color:#c77700">Deferred by decision — needs architecture / dataset knowledge (2)</h3>')
    for sid in ['G-01','I-03']:
        m=matrix[sid]; after,why=DEFERRED[sid]
        out.append(f'''<div class="fcard def"><div class="fh"><span class="idb">{sid}</span>
          <span class="sb" style="background:#c77700">DEFERRED</span><span class="catb">{esc(m["category"])}</span><span class="rc">{esc(m["pri"])}</span></div>
          <div class="fobs"><b>State:</b> {esc(after)}</div><div class="fwhy d"><b>Why deferred:</b> {esc(why)}</div></div>''')
    return ''.join(out)

HTMLDOC=f'''<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>V21 Final Status — 104 scenarios</title><style>{CSS}</style></head><body>
<header><div style="max-width:1200px;margin:0 auto"><h1>V21 Pricing Procedure — Final Status</h1>
<div class="sub">FortraUAT · Rev_Mgmt_Default_Pricing_Procedure V21 (active, 2026-07-01) · all 104 scenarios · post-fix</div></div></header>
<div class="wrap">
<section><h2>Executive summary</h2>
<div class="verdict">Of 104 scenarios, <b>{tal.get('PASS',0)} pass</b>, {tal.get('BLOCKED',0)} blocked on the UAT environment/data (not defects), {tal.get('N-A',0)} out of scope for Fortra. The 13 original defects: <b>8 fixed &amp; verified</b>, <b>2 deferred</b> by decision (architectural), and <b>3 that couldn't be fixed</b> — each owned/blocked elsewhere.</div>
<div class="tiles">{tiles()}</div>
<div class="leg">
<span><span class="legchip" style="background:#16794d">PASS</span> verified correct on live reprice</span>
<span><span class="legchip" style="background:#b3261e">FAIL</span> couldn't fix (owner/data/platform)</span>
<span><span class="legchip" style="background:#c77700">DEFERRED</span> accepted as-is (needs architecture decision)</span>
<span><span class="legchip" style="background:#8a6d00">BLOCKED</span> UAT env/data gap, not a defect</span>
<span><span class="legchip" style="background:#5b6675">N-A</span> out of scope (no evergreen / contracted)</span>
</div></section>
<section><h2>The 5 not-passing — with reasons</h2>{fails_html()}</section>
<section><h2>All 104 scenarios</h2>
<div class="filters" id="filters">
<button class="fbtn on" data-v="ALL">All</button>
<button class="fbtn" data-v="PASS">Pass</button><button class="fbtn" data-v="FAIL">Fail</button>
<button class="fbtn" data-v="DEFERRED">Deferred</button><button class="fbtn" data-v="BLOCKED">Blocked</button><button class="fbtn" data-v="N-A">N-A</button>
<input id="search" class="search" placeholder="search…"></div>
<table id="t"><thead><tr><th data-s="id">ID</th><th data-s="cat">Cat</th><th data-s="pri">Pri</th><th data-s="verdict">Status</th><th>Scenario / result / reason</th></tr></thead>
<tbody id="tb"></tbody></table><div class="rc" id="cnt" style="margin-top:8px"></div></section>
</div>
<script id="DATA" type="application/json">{DATA_JS}</script>
<script>
const VCOL={json.dumps(VCOL)};const ROWS=JSON.parse(document.getElementById('DATA').textContent);
let fv='ALL',q='',sk='id',sd=1;const tb=document.getElementById('tb'),cnt=document.getElementById('cnt');
const ORD={{FAIL:0,DEFERRED:1,PASS:2,BLOCKED:3,'N-A':4}};
function esc(s){{return (s||'').replace(/[&<>]/g,c=>({{'&':'&amp;','<':'&lt;','>':'&gt;'}}[c]))}}
function render(){{let r=ROWS.filter(x=>(fv==='ALL'||x.verdict===fv)&&(!q||(x.id+' '+x.name+' '+x.expected+' '+x.actual+' '+(x.reason||'')).toLowerCase().includes(q)));
r.sort((a,b)=>{{if(sk==='verdict')return (ORD[a.verdict]-ORD[b.verdict])*sd;let A=(a[sk]||'')+'',B=(b[sk]||'')+'';return A<B?-sd:A>B?sd:0}});
tb.innerHTML=r.map(x=>`<tr><td class="mono">${{x.id}}</td><td>${{x.cat}}</td><td class="rc">${{x.pri}}</td>
<td><span class="vcell" style="background:${{VCOL[x.verdict]}}">${{x.verdict}}</span></td>
<td><b style="font-size:12px">${{esc(x.name)}}</b><div class="rc"><b>Result:</b> ${{esc(x.actual)}}</div>${{x.reason?`<div class="rc" style="color:#b3261e"><b>Why:</b> ${{esc(x.reason)}}</div>`:''}}</td></tr>`).join('');
cnt.textContent=`Showing ${{r.length}} of ${{ROWS.length}}`;}}
document.getElementById('filters').addEventListener('click',e=>{{const b=e.target.closest('.fbtn');if(!b)return;fv=b.dataset.v;document.querySelectorAll('.fbtn').forEach(x=>x.classList.toggle('on',x===b));render();}});
document.getElementById('search').addEventListener('input',e=>{{q=e.target.value.toLowerCase();render();}});
document.querySelectorAll('#t th[data-s]').forEach(th=>th.addEventListener('click',()=>{{const k=th.dataset.s;sd=(sk===k)?-sd:1;sk=k;render();}}));
render();
</script></body></html>'''
open(f'{OUT}/V21_FINAL_STATUS.html','w').write(HTMLDOC)
print('wrote V21_FINAL_STATUS.html',len(HTMLDOC),'| tallies:',dict(tal))

# JSX
DATA2=json.dumps({'rows':rows,'tal':dict(tal),'fail':FAIL,'deferred':DEFERRED}, ensure_ascii=False)
JSX='''import React,{useState,useMemo} from "react";
/** V21 Final Status — all 104 scenarios after the 2026-07-01 fixes. <V21FinalStatus /> */
const D=__DATAJSON__;
const VCOL={"PASS":"#16794d","FAIL":"#b3261e","DEFERRED":"#c77700","BLOCKED":"#8a6d00","N-A":"#5b6675"};
const ORD={"FAIL":0,"DEFERRED":1,"PASS":2,"BLOCKED":3,"N-A":4};
export default function V21FinalStatus(){
 const [fv,setFv]=useState("ALL");const [q,setQ]=useState("");
 const rows=useMemo(()=>D.rows.filter(x=>(fv==="ALL"||x.verdict===fv)&&(!q||(x.id+" "+x.name+" "+x.actual+" "+(x.reason||"")).toLowerCase().includes(q.toLowerCase())))
   .sort((a,b)=>(ORD[a.verdict]-ORD[b.verdict])||a.id.localeCompare(b.id)),[fv,q]);
 const t=D.tal;const tiles=[["PASS","Pass","#16794d"],["FAIL","Fail (couldn't fix)","#b3261e"],["DEFERRED","Deferred","#c77700"],["BLOCKED","Blocked (env/data)","#8a6d00"],["N-A","N-A (out of scope)","#5b6675"]];
 const S={page:{fontFamily:"-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif",color:"#1a1f29",background:"#eef1f5",margin:0,lineHeight:1.5},wrap:{maxWidth:1200,margin:"0 auto",padding:"0 18px 80px"},section:{background:"#fff",borderRadius:12,padding:"22px 24px",margin:"20px 0",boxShadow:"0 1px 3px rgba(16,36,62,.08)"},th:{fontSize:10.5,textTransform:"uppercase",color:"#7a8696",background:"#fafbfc",textAlign:"left",padding:"7px 9px",cursor:"pointer",borderBottom:"1px solid #eef1f5"},td:{padding:"7px 9px",borderBottom:"1px solid #eef1f5",verticalAlign:"top",fontSize:12.5},rc:{fontSize:10.5,color:"#7a8696"}};
 const btn=on=>({fontSize:12,fontWeight:700,border:`1.5px solid ${on?"#10243e":"#d4dce6"}`,background:on?"#10243e":"#fff",color:on?"#fff":"#41506a",borderRadius:18,padding:"5px 12px",cursor:"pointer"});
 const fcard=(sid,st)=>{const m=D.rows.find(r=>r.id===sid);const [after,why]=(st==="FAIL"?D.fail:D.deferred)[sid];const c=VCOL[st];
   return <div key={sid} style={{border:"1px solid #e7ecf2",borderLeft:`6px solid ${c}`,borderRadius:11,padding:"14px 16px",margin:"11px 0"}}>
     <div style={{display:"flex",gap:9,alignItems:"center",flexWrap:"wrap",marginBottom:8}}><span style={{fontSize:14,fontWeight:800,color:"#fff",background:"#10243e",borderRadius:7,padding:"3px 10px"}}>{sid}</span>
     <span style={{fontSize:11,fontWeight:800,color:"#fff",background:c,borderRadius:6,padding:"3px 10px"}}>{st}</span><span style={{fontSize:11,color:"#5b6675",background:"#eef1f5",borderRadius:6,padding:"3px 9px"}}>{m.category}</span><span style={S.rc}>{m.pri}</span></div>
     <div style={{fontSize:13,color:"#41506a",marginBottom:7}}><b>State:</b> {after}</div>
     <div style={{fontSize:13,borderRadius:9,padding:"10px 13px",background:st==="FAIL"?"#fdecea":"#fdf6e8",border:st==="FAIL"?"1px solid #f4c7c1":"1px solid #f0dca8",color:st==="FAIL"?"#7a1a13":"#5a3a00"}}><b>{st==="FAIL"?"Why not fixed:":"Why deferred:"}</b> {why}</div></div>;};
 return <div style={S.page}>
  <div style={{background:"linear-gradient(120deg,#10243e,#1c3a5e)",color:"#fff",padding:"28px 18px"}}><div style={{maxWidth:1200,margin:"0 auto"}}>
    <h1 style={{margin:"0 0 4px",fontSize:27}}>V21 Pricing Procedure — Final Status</h1><div style={{color:"#bcd3ec",fontSize:14}}>FortraUAT · V21 (2026-07-01) · all 104 scenarios · post-fix</div></div></div>
  <div style={S.wrap}>
   <div style={S.section}><h2 style={{fontSize:19,margin:"0 0 14px",paddingBottom:9,borderBottom:"2px solid #eef1f5"}}>Executive summary</h2>
    <div style={{fontSize:16,background:"#f8fafc",borderLeft:"5px solid #16794d",padding:"13px 17px",borderRadius:8,marginBottom:18}}>Of 104 scenarios, <b>{t.PASS} pass</b>, {t.BLOCKED||0} blocked on UAT env/data (not defects), {t["N-A"]||0} out of scope. The 13 original defects: <b>8 fixed &amp; verified</b>, <b>2 deferred</b> by decision, <b>3 couldn't be fixed</b> (owned/blocked elsewhere).</div>
    <div style={{display:"grid",gridTemplateColumns:"repeat(5,1fr)",gap:11}}>{tiles.map(([k,l,c])=><div key={k} style={{border:"1px solid #e7ecf2",borderTop:`5px solid ${c}`,borderRadius:10,padding:"14px 10px",textAlign:"center"}}><div style={{fontSize:28,fontWeight:800,color:c}}>{t[k]||0}</div><div style={{fontSize:11.5,color:"#5b6675",fontWeight:600,marginTop:4}}>{l}</div></div>)}</div></div>
   <div style={S.section}><h2 style={{fontSize:19,margin:"0 0 14px",paddingBottom:9,borderBottom:"2px solid #eef1f5"}}>The 5 not-passing — with reasons</h2>
    <h3 style={{fontSize:15,margin:"4px 0 10px",color:"#b3261e"}}>Fails — couldn't fix (3)</h3>{["A-07","J-09","G-08"].map(s=>fcard(s,"FAIL"))}
    <h3 style={{fontSize:15,margin:"18px 0 10px",color:"#c77700"}}>Deferred by decision (2)</h3>{["G-01","I-03"].map(s=>fcard(s,"DEFERRED"))}</div>
   <div style={S.section}><h2 style={{fontSize:19,margin:"0 0 14px",paddingBottom:9,borderBottom:"2px solid #eef1f5"}}>All 104 scenarios</h2>
    <div style={{display:"flex",gap:7,flexWrap:"wrap",alignItems:"center",marginBottom:12}}>
     {["ALL","PASS","FAIL","DEFERRED","BLOCKED","N-A"].map(v=><button key={v} style={btn(fv===v)} onClick={()=>setFv(v)}>{v==="ALL"?"All":v}</button>)}
     <input value={q} onChange={e=>setQ(e.target.value)} placeholder="search…" style={{marginLeft:"auto",border:"1.5px solid #d4dce6",borderRadius:18,padding:"6px 13px",fontSize:13,minWidth:200}}/></div>
    <table style={{width:"100%",borderCollapse:"collapse",fontSize:12.5}}><thead><tr>{["ID","Cat","Pri","Status","Scenario / result / reason"].map(h=><th key={h} style={S.th}>{h}</th>)}</tr></thead>
     <tbody>{rows.map(x=><tr key={x.id}><td style={{...S.td,fontFamily:"monospace",fontWeight:700}}>{x.id}</td><td style={S.td}>{x.cat}</td><td style={{...S.td,...S.rc}}>{x.pri}</td>
       <td style={S.td}><span style={{fontWeight:800,fontSize:10.5,padding:"3px 7px",borderRadius:5,color:"#fff",background:VCOL[x.verdict],display:"inline-block",minWidth:64,textAlign:"center"}}>{x.verdict}</span></td>
       <td style={S.td}><b style={{fontSize:12}}>{x.name}</b><div style={S.rc}><b>Result:</b> {x.actual}</div>{x.reason&&<div style={{...S.rc,color:"#b3261e"}}><b>Why:</b> {x.reason}</div>}</td></tr>)}</tbody></table>
    <div style={{...S.rc,marginTop:8}}>Showing {rows.length} of {D.rows.length}</div></div>
  </div></div>;
}
'''
JSX=JSX.replace('__DATAJSON__',DATA2)
open(f'{OUT}/V21_FINAL_STATUS.jsx','w').write(JSX)
print('wrote V21_FINAL_STATUS.jsx',len(JSX))
