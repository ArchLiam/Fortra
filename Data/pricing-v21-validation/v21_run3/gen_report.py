#!/usr/bin/env python3
# Generates V21_VALIDATION_RESULTS.html (.jsx) (.md) from report_data.json + authored.json
import json, html, os

BASE = os.path.dirname(__file__)
OUT = os.path.dirname(BASE)  # Data/pricing-v21-validation
D = json.load(open(f'{BASE}/report_data.json'))
A = json.load(open(f'{BASE}/authored.json'))
matrix = D['matrix']; tal = D['tallies']; trans = D['transitions']
meta = A['meta']; legend = A['legend']

VCOL = {'PASS': '#16794d', 'FAIL': '#b3261e', 'BLOCKED': '#8a6d00'}
TCOL = {'PROCEDURE': '#b3261e', 'ORG-CONFIG': '#5b3fb0'}
def esc(s): return html.escape(str(s if s is not None else ''))
def esc_md(s):
    s = str(s if s is not None else '').replace('|', '\\|').replace('\n', ' ').strip()
    return s

ov = tal['overall']; bp = tal['byPriority']
p0 = bp['P0']; tested0 = p0['PASS'] + p0['FAIL']
p0rate = round(p0['PASS'] / tested0 * 100, 1) if tested0 else 0
overall_tested = ov['PASS'] + ov['FAIL']
overall_rate = round(ov['PASS'] / overall_tested * 100, 1)

# ---------- shared HTML fragments ----------
def stat_tiles():
    tiles = [
        ('104', 'scenarios smoke-tested', '#1f2937'),
        (str(ov['PASS']), 'PASS', VCOL['PASS']),
        (str(ov['FAIL']), 'FAIL (defects)', VCOL['FAIL']),
        (str(ov['BLOCKED']), 'BLOCKED', VCOL['BLOCKED']),
        (f'{p0rate}%', 'P0 pass-of-tested', '#0b6bcb'),
    ]
    return ''.join(
        f'<div class="tile" style="border-top:5px solid {c}"><div class="tnum" style="color:{c}">{esc(n)}</div><div class="tlab">{esc(l)}</div></div>'
        for n, l, c in tiles)

def legend_html():
    vs = ''.join(
        f'<div class="legrow"><span class="vchip" style="background:{v["color"]}">{esc(v["key"])}</span>'
        f'<div><b>{esc(v["meaning"])}</b><div class="legwhy">{esc(v["why"])}</div></div></div>'
        for v in legend['verdicts'])
    rc = ''.join(
        f'<div class="rcrow"><span class="rcchip">{esc(r["key"])}</span> <span>{esc(r["desc"])}</span></div>'
        for r in legend['rootCauses'])
    return (f'<div class="legbox"><div class="legverdicts">{vs}</div>'
            f'<div class="legrc"><div class="legrc-h">Root-cause classes (applied to FAIL / corrected scenarios)</div>{rc}</div></div>')

def headlines_html():
    return ''.join(
        f'<div class="hl"><div class="hltag">{esc(h["tag"])}</div><div class="hltext">{esc(h["text"])}</div></div>'
        for h in A['headlines'])

def defect_cards():
    out = []
    for pri in ['P0', 'P1', 'P2']:
        ds = [d for d in A['defects'] if d['pri'] == pri]
        if not ds: continue
        out.append(f'<h3 class="prihdr">{pri} defects <span class="cnt">({len(ds)})</span></h3>')
        out.append('<div class="cards">')
        for d in ds:
            tcol = TCOL[d['type']]
            reg = '<span class="regbadge">NEW REGRESSION</span>' if d.get('regression') else ''
            tk = f'<span class="ticket">{esc(d["ticket"])}</span>' if d.get('ticket') and d['ticket'] != '—' else ''
            out.append(f'''<div class="card" style="border-left:6px solid {tcol}">
  <div class="card-h"><span class="idchip" style="background:{tcol}">{esc(d["id"])}</span>
    <span class="typechip" style="color:{tcol};border-color:{tcol}">{esc(d["type"])}-DEFECT</span>
    <span class="catchip">{esc(d["cat"])}</span>{tk}{reg}</div>
  <div class="card-title">{esc(d["title"])}</div>
  <div class="kv"><span class="k">Responsible step</span><span class="v">{esc(d["step"])}</span></div>
  <div class="kv"><span class="k">Expected</span><span class="v">{esc(d["expected"])}</span></div>
  <div class="kv"><span class="k">Observed (live)</span><span class="v obs">{esc(d["observed"])}</span></div>
  <div class="kv"><span class="k">Proposed fix <i>(not applied)</i></span><span class="v">{esc(d["fix"])}</span></div>
  <a class="ev" href="{esc(d["url"])}" target="_blank" rel="noopener">▶ Evidence record</a>
</div>''')
        out.append('</div>')
    return ''.join(out)

def corrections_html():
    rows = []
    KIND = {'False defect caught': '#b3261e', 'Expectation corrected': '#0b6bcb', 'Real defect rescued': '#16794d'}
    for c in A['corrections']:
        col = KIND.get(c['kind'], '#555')
        rows.append(f'''<div class="corr" style="border-left:5px solid {col}">
  <div class="corr-h"><span class="idchip" style="background:{col}">{esc(c["id"])}</span>
    <span class="corrkind" style="color:{col}">{esc(c["kind"])}</span>
    <span class="corrflow">{esc(c["from"])} &nbsp;→&nbsp; <b>{esc(c["to"])}</b></span>
    <span class="corrby">via {esc(c["resolvedBy"])}</span></div>
  <div class="corr-fact">{esc(c["fact"])}</div></div>''')
    return ''.join(rows)

def coverage_html():
    rows = []
    for ct in sorted(tal['byCategory']):
        c = tal['byCategory'][ct]; P, F, B = c.get('PASS', 0), c.get('FAIL', 0), c.get('BLOCKED', 0)
        tot = P + F + B
        bar = (f'<span style="width:{P/tot*100}%;background:{VCOL["PASS"]}"></span>'
               f'<span style="width:{F/tot*100}%;background:{VCOL["FAIL"]}"></span>'
               f'<span style="width:{B/tot*100}%;background:{VCOL["BLOCKED"]}"></span>')
        rows.append(f'<tr><td class="cl">{esc(ct)}</td><td class="num">{tot}</td>'
                    f'<td class="num" style="color:{VCOL["PASS"]}">{P}</td>'
                    f'<td class="num" style="color:{VCOL["FAIL"]}">{F or ""}</td>'
                    f'<td class="num" style="color:{VCOL["BLOCKED"]}">{B or ""}</td>'
                    f'<td><div class="bar">{bar}</div></td></tr>')
    # priority rows
    prirows = []
    for p in ['P0', 'P1', 'P2']:
        c = bp[p]; P, F, B = c.get('PASS', 0), c.get('FAIL', 0), c.get('BLOCKED', 0)
        t = P + F + B; tested = P + F
        prirows.append(f'<tr><td class="cl"><b>{p}</b></td><td class="num">{t}</td>'
                       f'<td class="num" style="color:{VCOL["PASS"]}">{P}</td>'
                       f'<td class="num" style="color:{VCOL["FAIL"]}">{F}</td>'
                       f'<td class="num" style="color:{VCOL["BLOCKED"]}">{B}</td>'
                       f'<td class="num"><b>{round(P/tested*100,1) if tested else 0}%</b></td></tr>')
    return rows, prirows

def transitions_html():
    T = [('Fixed', 'prior FAIL → now PASS', trans.get('fixed', []), VCOL['PASS']),
         ('Reclassified', 'prior FAIL → now BLOCKED (data-artifact / env gap, not a real defect)', trans.get('reclassified', []), VCOL['BLOCKED']),
         ('Persistent', 'FAIL in both runs', trans.get('persistent', []), VCOL['FAIL']),
         ('New FAIL', 'prior PASS → now FAIL', trans.get('newfail', []), '#d9480f')]
    return ''.join(
        f'<tr><td class="cl" style="color:{c}"><b>{t}</b></td><td>{esc(desc)}</td>'
        f'<td class="num">{len(ids)}</td><td class="ids">{esc(", ".join(ids)) or "—"}</td></tr>'
        for t, desc, ids, c in T)

cov_rows, pri_rows = coverage_html()

CSS = '''
*{box-sizing:border-box} html{scroll-behavior:smooth}
body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;color:#1a1f29;background:#eef1f5;line-height:1.5}
.wrap{max-width:1180px;margin:0 auto;padding:0 20px 80px}
header{background:linear-gradient(120deg,#10243e,#1c3a5e);color:#fff;padding:30px 0 26px;margin-bottom:0}
header .wrap{padding-bottom:0}
h1{margin:0 0 4px;font-size:30px;letter-spacing:-.5px}
.sub{font-size:16px;color:#bcd3ec;margin-bottom:14px}
.metaline{font-size:12.5px;color:#9fbbd8;display:flex;flex-wrap:wrap;gap:16px}
.metaline b{color:#dcebff}
.vonly{display:inline-block;background:#f4b400;color:#1a1f29;font-weight:700;font-size:11px;padding:3px 9px;border-radius:5px;letter-spacing:.4px;margin-left:8px;vertical-align:middle}
section{background:#fff;border-radius:12px;padding:24px 26px;margin:22px 0;box-shadow:0 1px 3px rgba(16,36,62,.08)}
h2{font-size:20px;margin:0 0 16px;padding-bottom:10px;border-bottom:2px solid #eef1f5;letter-spacing:-.3px}
.verdict{font-size:16.5px;line-height:1.6;background:#f8fafc;border-left:5px solid #0b6bcb;padding:14px 18px;border-radius:8px;margin-bottom:20px}
.tiles{display:grid;grid-template-columns:repeat(5,1fr);gap:14px;margin-bottom:22px}
.tile{background:#fafbfc;border:1px solid #e7ecf2;border-radius:10px;padding:16px 12px;text-align:center}
.tnum{font-size:30px;font-weight:800;line-height:1}
.tlab{font-size:12px;color:#5b6675;margin-top:6px;font-weight:600}
.legbox{display:grid;grid-template-columns:1.35fr 1fr;gap:22px;margin-bottom:8px}
.legrow{display:flex;gap:12px;margin-bottom:14px;align-items:flex-start}
.vchip{color:#fff;font-weight:800;font-size:12px;padding:4px 10px;border-radius:6px;min-width:78px;text-align:center;flex-shrink:0;margin-top:2px}
.legwhy{font-size:13px;color:#5b6675;margin-top:3px}
.legrc{background:#f8fafc;border-radius:10px;padding:14px 16px}
.legrc-h{font-size:12.5px;font-weight:700;color:#3a4654;margin-bottom:10px;text-transform:uppercase;letter-spacing:.4px}
.rcrow{font-size:12.5px;margin-bottom:9px;color:#41506a}
.rcchip{display:inline-block;background:#eaeef4;border-radius:5px;padding:1px 7px;font-weight:700;font-size:11px;color:#33415c}
.hl{border-left:4px solid #0b6bcb;background:#f8fafc;padding:11px 16px;border-radius:7px;margin-bottom:11px}
.hltag{font-weight:800;font-size:13px;color:#10243e;margin-bottom:3px}
.hltext{font-size:13.5px;color:#33415c}
.methodbox{font-size:13px;color:#41506a;background:#fbfcfe;border:1px dashed #cdd8e6;border-radius:9px;padding:14px 16px;margin-top:6px}
.prihdr{font-size:16px;margin:22px 0 12px;color:#10243e}
.prihdr .cnt{color:#8a97a8;font-weight:500}
.cards{display:grid;grid-template-columns:1fr 1fr;gap:16px}
.card{background:#fff;border:1px solid #e7ecf2;border-radius:11px;padding:16px 18px;box-shadow:0 1px 2px rgba(16,36,62,.05)}
.card-h{display:flex;flex-wrap:wrap;gap:7px;align-items:center;margin-bottom:9px}
.idchip{color:#fff;font-weight:800;font-size:12.5px;padding:3px 9px;border-radius:6px}
.typechip{font-size:10.5px;font-weight:800;border:1.5px solid;border-radius:5px;padding:2px 7px;letter-spacing:.3px}
.catchip{font-size:11px;color:#5b6675;background:#eef1f5;border-radius:5px;padding:2px 8px}
.ticket{font-size:11px;color:#5b3fb0;background:#efeafc;border-radius:5px;padding:2px 8px;font-weight:600}
.regbadge{font-size:10px;font-weight:800;color:#fff;background:#d9480f;border-radius:5px;padding:2px 8px;letter-spacing:.4px}
.card-title{font-size:15px;font-weight:700;color:#16202e;margin-bottom:11px;line-height:1.35}
.kv{display:grid;grid-template-columns:128px 1fr;gap:10px;font-size:12.7px;margin-bottom:8px}
.kv .k{color:#7a8696;font-weight:700;font-size:11px;text-transform:uppercase;letter-spacing:.3px}
.kv .k i{font-weight:400;text-transform:none;letter-spacing:0}
.kv .v{color:#2b3646}
.kv .v.obs{background:#fff6f5;border-radius:6px;padding:6px 9px;border:1px solid #f6dcd9}
.ev{display:inline-block;margin-top:6px;font-size:12px;font-weight:700;color:#0b6bcb;text-decoration:none}
.ev:hover{text-decoration:underline}
.corr{background:#fff;border:1px solid #e7ecf2;border-radius:10px;padding:13px 16px;margin-bottom:12px}
.corr-h{display:flex;flex-wrap:wrap;gap:10px;align-items:center;margin-bottom:7px}
.corrkind{font-weight:800;font-size:12.5px}
.corrflow{font-size:12.5px;color:#41506a}
.corrby{font-size:11px;color:#8a97a8;margin-left:auto}
.corr-fact{font-size:13px;color:#33415c;line-height:1.55}
table{width:100%;border-collapse:collapse;font-size:13px}
th,td{text-align:left;padding:8px 10px;border-bottom:1px solid #eef1f5;vertical-align:top}
th{font-size:11px;text-transform:uppercase;letter-spacing:.4px;color:#7a8696;background:#fafbfc;position:sticky;top:0;cursor:pointer;user-select:none}
td.num,th.num{text-align:center}
.cl{font-weight:600}
.ids{font-family:ui-monospace,Menlo,monospace;font-size:11.5px;color:#5b6675}
.bar{display:flex;height:13px;border-radius:4px;overflow:hidden;background:#eef1f5;min-width:130px}
.bar span{display:block}
.filters{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin-bottom:14px}
.fbtn{font-size:12px;font-weight:700;border:1.5px solid #d4dce6;background:#fff;color:#41506a;border-radius:20px;padding:5px 13px;cursor:pointer}
.fbtn.on{background:#10243e;color:#fff;border-color:#10243e}
.search{margin-left:auto;border:1.5px solid #d4dce6;border-radius:20px;padding:6px 14px;font-size:13px;min-width:220px}
.vcell{font-weight:800;font-size:11px;padding:3px 8px;border-radius:5px;color:#fff;display:inline-block;min-width:62px;text-align:center}
.pcell{font-size:11px;font-weight:700;color:#5b6675}
.mono{font-family:ui-monospace,Menlo,monospace;font-weight:700}
.alink{color:#0b6bcb;text-decoration:none}.alink:hover{text-decoration:underline}
.rc{font-size:10.5px;color:#7a8696}
.foot{font-size:12px;color:#7a8696;margin-top:8px;line-height:1.6}
.toc{display:flex;flex-wrap:wrap;gap:8px;margin-top:14px}
.toc a{font-size:12px;font-weight:700;color:#10243e;background:#eef3fa;border-radius:6px;padding:5px 11px;text-decoration:none}
@media(max-width:900px){.tiles{grid-template-columns:repeat(2,1fr)}.legbox,.cards{grid-template-columns:1fr}}
'''

matrix_json = json.dumps(matrix)

HTMLDOC = f'''<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{esc(meta["title"])} — Results</title><style>{CSS}</style></head>
<body>
<header><div class="wrap">
  <h1>{esc(meta["title"])} <span class="vonly">VALIDATION ONLY</span></h1>
  <div class="sub">{esc(meta["subtitle"])}</div>
  <div class="metaline">
    <span>Org <b>{esc(meta["org"])}</b></span>
    <span><b>{esc(meta["procVersion"])}</b></span>
    <span>Context <b>{esc(meta["context"])}</b></span>
    <span>Run <b>{esc(meta["date"])}</b></span>
  </div>
  <div class="toc">
    <a href="#exec">Executive summary</a><a href="#defects">Defects ({ov["FAIL"]})</a>
    <a href="#corrections">Data / expectation corrections</a><a href="#delta">Prior-run delta</a>
    <a href="#coverage">Coverage</a><a href="#matrix">Full 104-row matrix</a>
  </div>
</div></header>
<div class="wrap">

<section id="exec">
  <h2>Executive summary</h2>
  <div class="verdict">{esc(meta["verdictLine"])}</div>
  <div class="tiles">{stat_tiles()}</div>
  <h3 style="font-size:15px;margin:6px 0 12px;color:#10243e">Legend — what each verdict means &amp; why</h3>
  {legend_html()}
  <h3 style="font-size:15px;margin:22px 0 12px;color:#10243e">Headline findings</h3>
  {headlines_html()}
  <div class="methodbox"><b>How this was tested.</b> {esc(meta["method"])}<br><br><b>Data discipline.</b> {esc(meta["dataDiscipline"])}</div>
</section>

<section id="defects">
  <h2>Defects — {ov["FAIL"]} reportable ({sum(1 for d in A["defects"] if d["type"]=="PROCEDURE")} procedure · {sum(1 for d in A["defects"] if d["type"]=="ORG-CONFIG")} org-config)</h2>
  {defect_cards()}
</section>

<section id="corrections">
  <h2>Data &amp; expectation corrections <span style="font-size:13px;font-weight:500;color:#8a97a8">— what the adversarial audit + tie-breaker caught</span></h2>
  <p style="font-size:13.5px;color:#41506a;margin-top:-6px">These are the scenarios where the first-pass FAIL did <b>not</b> survive scrutiny — proof that the run distinguishes a malformed fixture from a real procedure fault.</p>
  {corrections_html()}
</section>

<section id="delta">
  <h2>What changed since the prior run</h2>
  <p style="font-size:13.5px;color:#41506a;margin-top:-6px">FAIL fell from ~23–25 to {ov["FAIL"]} for two distinct reasons: a handful of genuine fixes, and a larger set of prior FAILs that this run’s stricter verification correctly downgraded to BLOCKED (they had been logged on data artifacts, not V21 faults).</p>
  <table><thead><tr><th>Transition</th><th>Meaning</th><th class="num">#</th><th>Scenarios</th></tr></thead>
  <tbody>{transitions_html()}</tbody></table>
</section>

<section id="coverage">
  <h2>Coverage</h2>
  <div style="display:grid;grid-template-columns:1fr 1fr;gap:26px">
    <div><h3 style="font-size:14px;margin:0 0 8px">By priority</h3>
      <table><thead><tr><th>Pri</th><th class="num">Tot</th><th class="num">P</th><th class="num">F</th><th class="num">B</th><th class="num">Pass%*</th></tr></thead>
      <tbody>{''.join(pri_rows)}</tbody></table>
      <div class="foot">*Pass% = PASS / (PASS+FAIL), excluding BLOCKED.</div></div>
    <div><h3 style="font-size:14px;margin:0 0 8px">By category</h3>
      <table><thead><tr><th>Category</th><th class="num">Tot</th><th class="num">P</th><th class="num">F</th><th class="num">B</th><th>Mix</th></tr></thead>
      <tbody>{''.join(cov_rows)}</tbody></table></div>
  </div>
</section>

<section id="matrix">
  <h2>Full results matrix — 104 scenarios</h2>
  <div class="filters" id="filters">
    <button class="fbtn on" data-f="verdict" data-v="ALL">All</button>
    <button class="fbtn" data-f="verdict" data-v="PASS">PASS</button>
    <button class="fbtn" data-f="verdict" data-v="FAIL">FAIL</button>
    <button class="fbtn" data-f="verdict" data-v="BLOCKED">BLOCKED</button>
    <span style="width:1px;height:22px;background:#dce3ec;margin:0 4px"></span>
    <button class="fbtn on" data-f="pri" data-v="ALL">All pri</button>
    <button class="fbtn" data-f="pri" data-v="P0">P0</button>
    <button class="fbtn" data-f="pri" data-v="P1">P1</button>
    <button class="fbtn" data-f="pri" data-v="P2">P2</button>
    <input id="search" class="search" placeholder="search id / name / detail…">
  </div>
  <table id="mtable"><thead><tr>
    <th data-s="id">ID</th><th data-s="cat">Cat</th><th data-s="pri">Pri</th>
    <th data-s="dataSource">Data</th><th data-s="preflight">Pre</th>
    <th data-s="verdict">Verdict</th><th data-s="rootCause">Root cause</th>
    <th>Expected → Actual (live)</th><th>Ev</th></tr></thead>
  <tbody id="mbody"></tbody></table>
  <div class="foot" id="mcount"></div>
</section>

<div class="foot" style="padding:0 4px">
  <b>Fixtures &amp; cleanup.</b> {esc(A["fixtures"]["note"])} {esc(A["fixtures"]["cleanup"])}<br>
  <b>Durability / follow-ups.</b> {' · '.join(esc(x) for x in A["durability"])}
</div>

</div>
<script id="DATA" type="application/json">{matrix_json}</script>
<script>
const VCOL={json.dumps(VCOL)};
const ROWS=JSON.parse(document.getElementById('DATA').textContent);
let F={{verdict:'ALL',pri:'ALL',q:''}}, sortKey='id', sortDir=1;
const body=document.getElementById('mbody'), count=document.getElementById('mcount');
function render(){{
  let r=ROWS.filter(x=>(F.verdict==='ALL'||x.verdict===F.verdict)&&(F.pri==='ALL'||x.pri===F.pri)&&
    (!F.q|| (x.id+' '+x.name+' '+x.expected+' '+x.actual+' '+x.rootCause).toLowerCase().includes(F.q)));
  r.sort((a,b)=>{{let A=(a[sortKey]||'')+'',B=(b[sortKey]||'')+'';return A<B?-sortDir:A>B?sortDir:0}});
  body.innerHTML=r.map(x=>{{
    const ev=x.url?`<a class="alink" href="${{x.url}}" target="_blank" rel="noopener">▶</a>`:'';
    const adj=x.adjudication?`<div class="rc" style="color:#0b6bcb">⚖ ${{esc(x.adjudication)}}</div>`:'';
    return `<tr>
      <td class="mono">${{x.id}}</td><td>${{x.cat}}</td><td class="pcell">${{x.pri}}</td>
      <td class="rc">${{x.dataSource||''}}</td><td class="rc">${{x.preflight||''}}</td>
      <td><span class="vcell" style="background:${{VCOL[x.verdict]}}">${{x.verdict}}</span></td>
      <td class="rc">${{x.rootCause||''}}</td>
      <td><b style="font-size:12px">${{esc(x.name)}}</b><div class="rc"><b>Exp:</b> ${{esc(x.expected)}}</div><div class="rc"><b>Act:</b> ${{esc(x.actual)}}</div>${{adj}}</td>
      <td>${{ev}}</td></tr>`;
  }}).join('');
  count.textContent=`Showing ${{r.length}} of ${{ROWS.length}} scenarios`;
}}
function esc(s){{return (s||'').replace(/[&<>]/g,c=>({{'&':'&amp;','<':'&lt;','>':'&gt;'}}[c]))}}
document.getElementById('filters').addEventListener('click',e=>{{
  const b=e.target.closest('.fbtn'); if(!b)return;
  F[b.dataset.f]=b.dataset.v;
  document.querySelectorAll(`.fbtn[data-f="${{b.dataset.f}}"]`).forEach(x=>x.classList.toggle('on',x===b));
  render();
}});
document.getElementById('search').addEventListener('input',e=>{{F.q=e.target.value.toLowerCase();render()}});
document.querySelectorAll('#mtable th[data-s]').forEach(th=>th.addEventListener('click',()=>{{
  const k=th.dataset.s; sortDir=(sortKey===k)?-sortDir:1; sortKey=k; render();
}}));
render();
</script>
</body></html>'''

with open(f'{OUT}/V21_VALIDATION_RESULTS.html', 'w') as f:
    f.write(HTMLDOC)
print('wrote V21_VALIDATION_RESULTS.html', len(HTMLDOC), 'bytes')

# ---------------- JSX ----------------
DATA_JS = json.dumps({'meta': meta, 'legend': legend, 'headlines': A['headlines'],
                      'defects': A['defects'], 'corrections': A['corrections'],
                      'tallies': tal, 'transitions': trans, 'matrix': matrix,
                      'fixtures': A['fixtures'], 'durability': A['durability']}, indent=1)

JSX = '''import React, { useState, useMemo } from "react";

/**
 * V21 Pricing-Procedure Validation — Results (FortraUAT, active V21).
 * Self-contained, dependency-free (inline styles). Drop into any React app:
 *   import V21Results from "./V21_VALIDATION_RESULTS.jsx";  ->  <V21Results />
 * Source of truth: Data/pricing-v21-validation/V21_VALIDATION_RESULTS.md + rows_run3/*.json.
 * 69 PASS / 13 FAIL / 22 BLOCKED. Validation only — fixes are PROPOSED, not applied.
 */

const DATA = ''' + DATA_JS + ''';

const VCOL = { PASS: "#16794d", FAIL: "#b3261e", BLOCKED: "#8a6d00" };
const TCOL = { PROCEDURE: "#b3261e", "ORG-CONFIG": "#5b3fb0" };
const S = {
  page: { fontFamily: "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif", color: "#1a1f29", background: "#eef1f5", margin: 0, lineHeight: 1.5 },
  wrap: { maxWidth: 1180, margin: "0 auto", padding: "0 20px 80px" },
  header: { background: "linear-gradient(120deg,#10243e,#1c3a5e)", color: "#fff", padding: "30px 20px 26px" },
  section: { background: "#fff", borderRadius: 12, padding: "24px 26px", margin: "22px 0", boxShadow: "0 1px 3px rgba(16,36,62,.08)" },
  h2: { fontSize: 20, margin: "0 0 16px", paddingBottom: 10, borderBottom: "2px solid #eef1f5" },
  verdict: { fontSize: 16.5, background: "#f8fafc", borderLeft: "5px solid #0b6bcb", padding: "14px 18px", borderRadius: 8, marginBottom: 20 },
  tiles: { display: "grid", gridTemplateColumns: "repeat(5,1fr)", gap: 14, marginBottom: 22 },
  tile: (c) => ({ background: "#fafbfc", border: "1px solid #e7ecf2", borderTop: `5px solid ${c}`, borderRadius: 10, padding: "16px 12px", textAlign: "center" }),
  card: (c) => ({ background: "#fff", border: "1px solid #e7ecf2", borderLeft: `6px solid ${c}`, borderRadius: 11, padding: "16px 18px" }),
  chip: (bg) => ({ color: "#fff", fontWeight: 800, fontSize: 12.5, padding: "3px 9px", borderRadius: 6, background: bg }),
  vcell: (bg) => ({ fontWeight: 800, fontSize: 11, padding: "3px 8px", borderRadius: 5, color: "#fff", background: bg, display: "inline-block", minWidth: 62, textAlign: "center" }),
  th: { fontSize: 11, textTransform: "uppercase", letterSpacing: ".4px", color: "#7a8696", background: "#fafbfc", textAlign: "left", padding: "8px 10px", cursor: "pointer", borderBottom: "1px solid #eef1f5" },
  td: { padding: "8px 10px", borderBottom: "1px solid #eef1f5", verticalAlign: "top", fontSize: 13 },
  rc: { fontSize: 10.5, color: "#7a8696" },
};

function KV({ k, v, obs }) {
  return (
    <div style={{ display: "grid", gridTemplateColumns: "128px 1fr", gap: 10, fontSize: 12.7, marginBottom: 8 }}>
      <span style={{ color: "#7a8696", fontWeight: 700, fontSize: 11, textTransform: "uppercase" }}>{k}</span>
      <span style={obs ? { background: "#fff6f5", borderRadius: 6, padding: "6px 9px", border: "1px solid #f6dcd9" } : { color: "#2b3646" }}>{v}</span>
    </div>
  );
}

function Bar({ P, F, B }) {
  const t = P + F + B || 1;
  return (
    <div style={{ display: "flex", height: 13, borderRadius: 4, overflow: "hidden", background: "#eef1f5", minWidth: 130 }}>
      <span style={{ width: `${P / t * 100}%`, background: VCOL.PASS }} />
      <span style={{ width: `${F / t * 100}%`, background: VCOL.FAIL }} />
      <span style={{ width: `${B / t * 100}%`, background: VCOL.BLOCKED }} />
    </div>
  );
}

export default function V21Results() {
  const { meta, legend, headlines, defects, corrections, tallies, transitions, matrix, fixtures, durability } = DATA;
  const [fv, setFv] = useState("ALL");
  const [fp, setFp] = useState("ALL");
  const [q, setQ] = useState("");
  const [sortKey, setSortKey] = useState("id");
  const [dir, setDir] = useState(1);

  const ov = tallies.overall, bp = tallies.byPriority;
  const p0 = bp.P0, tested0 = p0.PASS + p0.FAIL;
  const p0rate = tested0 ? Math.round(p0.PASS / tested0 * 1000) / 10 : 0;

  const rows = useMemo(() => {
    let r = matrix.filter((x) => (fv === "ALL" || x.verdict === fv) && (fp === "ALL" || x.pri === fp) &&
      (!q || (x.id + " " + x.name + " " + x.expected + " " + x.actual + " " + x.rootCause).toLowerCase().includes(q.toLowerCase())));
    r = [...r].sort((a, b) => { const A = (a[sortKey] || "") + "", B = (b[sortKey] || "") + ""; return A < B ? -dir : A > B ? dir : 0; });
    return r;
  }, [fv, fp, q, sortKey, dir, matrix]);

  const tiles = [["104", "scenarios", "#1f2937"], [ov.PASS, "PASS", VCOL.PASS], [ov.FAIL, "FAIL (defects)", VCOL.FAIL], [ov.BLOCKED, "BLOCKED", VCOL.BLOCKED], [p0rate + "%", "P0 pass-of-tested", "#0b6bcb"]];
  const procN = defects.filter((d) => d.type === "PROCEDURE").length, orgN = defects.filter((d) => d.type === "ORG-CONFIG").length;
  const transDefs = [["Fixed", "prior FAIL → now PASS", transitions.fixed, VCOL.PASS], ["Reclassified", "prior FAIL → BLOCKED (data-artifact, not a defect)", transitions.reclassified, VCOL.BLOCKED], ["Persistent", "FAIL in both runs", transitions.persistent, VCOL.FAIL], ["New FAIL", "prior PASS → now FAIL", transitions.newfail, "#d9480f"]];
  const sortBy = (k) => { if (k === sortKey) setDir(-dir); else { setSortKey(k); setDir(1); } };

  return (
    <div style={S.page}>
      <div style={S.header}>
        <div style={{ maxWidth: 1180, margin: "0 auto" }}>
          <h1 style={{ margin: "0 0 4px", fontSize: 30 }}>{meta.title}
            <span style={{ background: "#f4b400", color: "#1a1f29", fontWeight: 700, fontSize: 11, padding: "3px 9px", borderRadius: 5, marginLeft: 8, verticalAlign: "middle" }}>VALIDATION ONLY</span></h1>
          <div style={{ fontSize: 16, color: "#bcd3ec", marginBottom: 14 }}>{meta.subtitle}</div>
          <div style={{ fontSize: 12.5, color: "#9fbbd8", display: "flex", flexWrap: "wrap", gap: 16 }}>
            <span>Org <b style={{ color: "#dcebff" }}>{meta.org}</b></span>
            <span><b style={{ color: "#dcebff" }}>{meta.procVersion}</b></span>
            <span>Context <b style={{ color: "#dcebff" }}>{meta.context}</b></span>
            <span>Run <b style={{ color: "#dcebff" }}>{meta.date}</b></span>
          </div>
        </div>
      </div>
      <div style={S.wrap}>

        {/* EXEC */}
        <div style={S.section}>
          <h2 style={S.h2}>Executive summary</h2>
          <div style={S.verdict}>{meta.verdictLine}</div>
          <div style={S.tiles}>{tiles.map(([n, l, c], i) => (
            <div key={i} style={S.tile(c)}><div style={{ fontSize: 30, fontWeight: 800, color: c }}>{n}</div><div style={{ fontSize: 12, color: "#5b6675", marginTop: 6, fontWeight: 600 }}>{l}</div></div>
          ))}</div>

          <h3 style={{ fontSize: 15, margin: "6px 0 12px", color: "#10243e" }}>Legend — what each verdict means &amp; why</h3>
          <div style={{ display: "grid", gridTemplateColumns: "1.35fr 1fr", gap: 22 }}>
            <div>{legend.verdicts.map((v) => (
              <div key={v.key} style={{ display: "flex", gap: 12, marginBottom: 14, alignItems: "flex-start" }}>
                <span style={{ ...S.chip(v.color), minWidth: 78, textAlign: "center", marginTop: 2 }}>{v.key}</span>
                <div><b>{v.meaning}</b><div style={{ fontSize: 13, color: "#5b6675", marginTop: 3 }}>{v.why}</div></div>
              </div>))}</div>
            <div style={{ background: "#f8fafc", borderRadius: 10, padding: "14px 16px" }}>
              <div style={{ fontSize: 12.5, fontWeight: 700, color: "#3a4654", marginBottom: 10, textTransform: "uppercase" }}>Root-cause classes</div>
              {legend.rootCauses.map((r) => (
                <div key={r.key} style={{ fontSize: 12.5, marginBottom: 9, color: "#41506a" }}>
                  <span style={{ background: "#eaeef4", borderRadius: 5, padding: "1px 7px", fontWeight: 700, fontSize: 11 }}>{r.key}</span> {r.desc}
                </div>))}
            </div>
          </div>

          <h3 style={{ fontSize: 15, margin: "22px 0 12px", color: "#10243e" }}>Headline findings</h3>
          {headlines.map((h, i) => (
            <div key={i} style={{ borderLeft: "4px solid #0b6bcb", background: "#f8fafc", padding: "11px 16px", borderRadius: 7, marginBottom: 11 }}>
              <div style={{ fontWeight: 800, fontSize: 13, color: "#10243e", marginBottom: 3 }}>{h.tag}</div>
              <div style={{ fontSize: 13.5, color: "#33415c" }}>{h.text}</div>
            </div>))}
          <div style={{ fontSize: 13, color: "#41506a", background: "#fbfcfe", border: "1px dashed #cdd8e6", borderRadius: 9, padding: "14px 16px", marginTop: 6 }}>
            <b>How this was tested.</b> {meta.method}<br /><br /><b>Data discipline.</b> {meta.dataDiscipline}
          </div>
        </div>

        {/* DEFECTS */}
        <div style={S.section}>
          <h2 style={S.h2}>Defects — {ov.FAIL} reportable ({procN} procedure · {orgN} org-config)</h2>
          {["P0", "P1", "P2"].map((pri) => {
            const ds = defects.filter((d) => d.pri === pri); if (!ds.length) return null;
            return (
              <div key={pri}>
                <h3 style={{ fontSize: 16, margin: "22px 0 12px", color: "#10243e" }}>{pri} defects <span style={{ color: "#8a97a8", fontWeight: 500 }}>({ds.length})</span></h3>
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
                  {ds.map((d) => (
                    <div key={d.id} style={S.card(TCOL[d.type])}>
                      <div style={{ display: "flex", flexWrap: "wrap", gap: 7, alignItems: "center", marginBottom: 9 }}>
                        <span style={S.chip(TCOL[d.type])}>{d.id}</span>
                        <span style={{ fontSize: 10.5, fontWeight: 800, border: `1.5px solid ${TCOL[d.type]}`, color: TCOL[d.type], borderRadius: 5, padding: "2px 7px" }}>{d.type}-DEFECT</span>
                        <span style={{ fontSize: 11, color: "#5b6675", background: "#eef1f5", borderRadius: 5, padding: "2px 8px" }}>{d.cat}</span>
                        {d.ticket && d.ticket !== "—" && <span style={{ fontSize: 11, color: "#5b3fb0", background: "#efeafc", borderRadius: 5, padding: "2px 8px", fontWeight: 600 }}>{d.ticket}</span>}
                        {d.regression && <span style={{ fontSize: 10, fontWeight: 800, color: "#fff", background: "#d9480f", borderRadius: 5, padding: "2px 8px" }}>NEW REGRESSION</span>}
                      </div>
                      <div style={{ fontSize: 15, fontWeight: 700, color: "#16202e", marginBottom: 11 }}>{d.title}</div>
                      <KV k="Responsible step" v={d.step} />
                      <KV k="Expected" v={d.expected} />
                      <KV k="Observed (live)" v={d.observed} obs />
                      <KV k="Proposed fix" v={d.fix} />
                      <a href={d.url} target="_blank" rel="noopener noreferrer" style={{ fontSize: 12, fontWeight: 700, color: "#0b6bcb", textDecoration: "none" }}>▶ Evidence record</a>
                    </div>))}
                </div>
              </div>);
          })}
        </div>

        {/* CORRECTIONS */}
        <div style={S.section}>
          <h2 style={S.h2}>Data &amp; expectation corrections</h2>
          <p style={{ fontSize: 13.5, color: "#41506a", marginTop: -6 }}>Scenarios where the first-pass FAIL did <b>not</b> survive scrutiny — proof the run separates a malformed fixture from a real fault.</p>
          {corrections.map((c) => {
            const col = c.kind === "False defect caught" ? "#b3261e" : c.kind === "Expectation corrected" ? "#0b6bcb" : "#16794d";
            return (
              <div key={c.id} style={{ background: "#fff", border: "1px solid #e7ecf2", borderLeft: `5px solid ${col}`, borderRadius: 10, padding: "13px 16px", marginBottom: 12 }}>
                <div style={{ display: "flex", flexWrap: "wrap", gap: 10, alignItems: "center", marginBottom: 7 }}>
                  <span style={S.chip(col)}>{c.id}</span>
                  <span style={{ fontWeight: 800, fontSize: 12.5, color: col }}>{c.kind}</span>
                  <span style={{ fontSize: 12.5, color: "#41506a" }}>{c.from} → <b>{c.to}</b></span>
                  <span style={{ fontSize: 11, color: "#8a97a8", marginLeft: "auto" }}>via {c.resolvedBy}</span>
                </div>
                <div style={{ fontSize: 13, color: "#33415c" }}>{c.fact}</div>
              </div>);
          })}
        </div>

        {/* DELTA */}
        <div style={S.section}>
          <h2 style={S.h2}>What changed since the prior run</h2>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead><tr>{["Transition", "Meaning", "#", "Scenarios"].map((h) => <th key={h} style={S.th}>{h}</th>)}</tr></thead>
            <tbody>{transDefs.map(([t, desc, ids, c]) => (
              <tr key={t}><td style={{ ...S.td, color: c, fontWeight: 700 }}>{t}</td><td style={S.td}>{desc}</td><td style={{ ...S.td, textAlign: "center" }}>{ids.length}</td><td style={{ ...S.td, fontFamily: "monospace", fontSize: 11.5, color: "#5b6675" }}>{ids.join(", ") || "—"}</td></tr>
            ))}</tbody>
          </table>
        </div>

        {/* COVERAGE */}
        <div style={S.section}>
          <h2 style={S.h2}>Coverage</h2>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 26 }}>
            <div><h3 style={{ fontSize: 14, margin: "0 0 8px" }}>By priority</h3>
              <table style={{ width: "100%", borderCollapse: "collapse" }}>
                <thead><tr>{["Pri", "Tot", "P", "F", "B", "Pass%*"].map((h) => <th key={h} style={{ ...S.th, textAlign: h === "Pri" ? "left" : "center" }}>{h}</th>)}</tr></thead>
                <tbody>{["P0", "P1", "P2"].map((p) => { const c = bp[p], P = c.PASS || 0, F = c.FAIL || 0, B = c.BLOCKED || 0, te = P + F; return (
                  <tr key={p}><td style={{ ...S.td, fontWeight: 700 }}>{p}</td><td style={{ ...S.td, textAlign: "center" }}>{P + F + B}</td>
                    <td style={{ ...S.td, textAlign: "center", color: VCOL.PASS }}>{P}</td><td style={{ ...S.td, textAlign: "center", color: VCOL.FAIL }}>{F}</td>
                    <td style={{ ...S.td, textAlign: "center", color: VCOL.BLOCKED }}>{B}</td><td style={{ ...S.td, textAlign: "center", fontWeight: 700 }}>{te ? Math.round(P / te * 1000) / 10 : 0}%</td></tr>); })}</tbody>
              </table>
              <div style={{ fontSize: 12, color: "#7a8696", marginTop: 8 }}>*Pass% = PASS / (PASS+FAIL), excluding BLOCKED.</div></div>
            <div><h3 style={{ fontSize: 14, margin: "0 0 8px" }}>By category</h3>
              <table style={{ width: "100%", borderCollapse: "collapse" }}>
                <thead><tr>{["Category", "T", "P", "F", "B", "Mix"].map((h) => <th key={h} style={{ ...S.th, textAlign: h === "Category" ? "left" : "center" }}>{h}</th>)}</tr></thead>
                <tbody>{Object.keys(tallies.byCategory).sort().map((ct) => { const c = tallies.byCategory[ct], P = c.PASS || 0, F = c.FAIL || 0, B = c.BLOCKED || 0; return (
                  <tr key={ct}><td style={{ ...S.td, fontWeight: 600 }}>{ct}</td><td style={{ ...S.td, textAlign: "center" }}>{P + F + B}</td>
                    <td style={{ ...S.td, textAlign: "center", color: VCOL.PASS }}>{P}</td><td style={{ ...S.td, textAlign: "center", color: VCOL.FAIL }}>{F || ""}</td>
                    <td style={{ ...S.td, textAlign: "center", color: VCOL.BLOCKED }}>{B || ""}</td><td style={S.td}><Bar P={P} F={F} B={B} /></td></tr>); })}</tbody>
              </table></div>
          </div>
        </div>

        {/* MATRIX */}
        <div style={S.section}>
          <h2 style={S.h2}>Full results matrix — 104 scenarios</h2>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 8, alignItems: "center", marginBottom: 14 }}>
            {["ALL", "PASS", "FAIL", "BLOCKED"].map((v) => (
              <button key={v} onClick={() => setFv(v)} style={btn(fv === v)}>{v === "ALL" ? "All" : v}</button>))}
            <span style={{ width: 1, height: 22, background: "#dce3ec", margin: "0 4px" }} />
            {["ALL", "P0", "P1", "P2"].map((p) => (
              <button key={p} onClick={() => setFp(p)} style={btn(fp === p)}>{p === "ALL" ? "All pri" : p}</button>))}
            <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="search id / name / detail…"
              style={{ marginLeft: "auto", border: "1.5px solid #d4dce6", borderRadius: 20, padding: "6px 14px", fontSize: 13, minWidth: 220 }} />
          </div>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead><tr>{[["id", "ID"], ["cat", "Cat"], ["pri", "Pri"], ["dataSource", "Data"], ["preflight", "Pre"], ["verdict", "Verdict"], ["rootCause", "Root cause"], [null, "Expected → Actual (live)"], [null, "Ev"]].map(([k, h], i) => (
              <th key={i} style={S.th} onClick={() => k && sortBy(k)}>{h}</th>))}</tr></thead>
            <tbody>{rows.map((x) => (
              <tr key={x.id}>
                <td style={{ ...S.td, fontFamily: "monospace", fontWeight: 700 }}>{x.id}</td>
                <td style={S.td}>{x.cat}</td><td style={{ ...S.td, fontWeight: 700, color: "#5b6675" }}>{x.pri}</td>
                <td style={{ ...S.td, ...S.rc }}>{x.dataSource}</td><td style={{ ...S.td, ...S.rc }}>{x.preflight}</td>
                <td style={S.td}><span style={S.vcell(VCOL[x.verdict])}>{x.verdict}</span></td>
                <td style={{ ...S.td, ...S.rc }}>{x.rootCause}</td>
                <td style={S.td}><b style={{ fontSize: 12 }}>{x.name}</b>
                  <div style={S.rc}><b>Exp:</b> {x.expected}</div><div style={S.rc}><b>Act:</b> {x.actual}</div>
                  {x.adjudication && <div style={{ ...S.rc, color: "#0b6bcb" }}>⚖ {x.adjudication}</div>}</td>
                <td style={S.td}>{x.url && <a href={x.url} target="_blank" rel="noopener noreferrer" style={{ color: "#0b6bcb", textDecoration: "none" }}>▶</a>}</td>
              </tr>))}</tbody>
          </table>
          <div style={{ fontSize: 12, color: "#7a8696", marginTop: 8 }}>Showing {rows.length} of {matrix.length} scenarios</div>
        </div>

        <div style={{ fontSize: 12, color: "#7a8696", padding: "0 4px", lineHeight: 1.6 }}>
          <b>Fixtures &amp; cleanup.</b> {fixtures.note} {fixtures.cleanup}<br />
          <b>Durability / follow-ups.</b> {durability.join(" · ")}
        </div>
      </div>
    </div>
  );
}

function btn(on) {
  return { fontSize: 12, fontWeight: 700, border: `1.5px solid ${on ? "#10243e" : "#d4dce6"}`, background: on ? "#10243e" : "#fff", color: on ? "#fff" : "#41506a", borderRadius: 20, padding: "5px 13px", cursor: "pointer" };
}
'''

with open(f'{OUT}/V21_VALIDATION_RESULTS.jsx', 'w') as f:
    f.write(JSX)
print('wrote V21_VALIDATION_RESULTS.jsx', len(JSX), 'bytes')

# ---------------- Markdown ----------------
md = []
md.append(f'# {meta["title"]} — Results\n')
md.append(f'**Procedure:** `Rev_Mgmt_Default_Pricing_Procedure` V21 — {meta["procVersion"]}  ')
md.append(f'**Org:** {meta["org"]} · **Context:** {meta["context"]} · **Run:** {meta["date"]} · **VALIDATION ONLY**\n')
md.append('## Executive summary\n')
md.append(f'> {meta["verdictLine"]}\n')
md.append(f'| Scenarios | PASS | FAIL (defects) | BLOCKED | P0 pass-of-tested | Overall pass-of-tested |')
md.append('|---|---|---|---|---|---|')
md.append(f'| 104 | {ov["PASS"]} | {ov["FAIL"]} | {ov["BLOCKED"]} | {p0rate}% | {overall_rate}% |\n')
md.append('### Legend\n')
for v in legend['verdicts']:
    md.append(f'- **{v["key"]}** — {v["meaning"]} _{v["why"]}_')
md.append('\n_Root-cause classes:_ ' + ' · '.join(f'**{r["key"]}** {r["desc"]}' for r in legend['rootCauses']) + '\n')
md.append('### Headline findings\n')
for h in A['headlines']:
    md.append(f'- **{h["tag"]}** — {h["text"]}')
md.append(f'\n**Method.** {meta["method"]}\n\n**Data discipline.** {meta["dataDiscipline"]}\n')

md.append(f'## Defects ({ov["FAIL"]})\n')
md.append('| id | pri | type | category | ticket | title | responsible step | expected | observed (live) | proposed fix (not applied) | regression | evidence |')
md.append('|---|---|---|---|---|---|---|---|---|---|---|---|')
for d in A['defects']:
    md.append('| ' + ' | '.join(esc_md(x) for x in [d['id'], d['pri'], d['type'], d['cat'], d.get('ticket', ''), d['title'], d['step'], d['expected'], d['observed'], d['fix'], 'YES' if d.get('regression') else '', d['url']]) + ' |')

md.append('\n## Data & expectation corrections\n')
md.append('| id | kind | from → to | resolved by | decisive fact |')
md.append('|---|---|---|---|---|')
for c in A['corrections']:
    md.append(f'| {c["id"]} | {c["kind"]} | {esc_md(c["from"])} → {esc_md(c["to"])} | {c["resolvedBy"]} | {esc_md(c["fact"])} |')

md.append('\n## What changed since the prior run\n')
md.append('| transition | meaning | # | scenarios |')
md.append('|---|---|---|---|')
for t, desc, ids, c in [('Fixed', 'prior FAIL → now PASS', trans.get('fixed', []), ''), ('Reclassified', 'prior FAIL → BLOCKED (data-artifact)', trans.get('reclassified', []), ''), ('Persistent', 'FAIL both runs', trans.get('persistent', []), ''), ('New FAIL', 'prior PASS → now FAIL', trans.get('newfail', []), '')]:
    md.append(f'| {t} | {desc} | {len(ids)} | {", ".join(ids) or "—"} |')

md.append('\n## Coverage\n')
md.append('| priority | total | PASS | FAIL | BLOCKED | pass-of-tested |')
md.append('|---|---|---|---|---|---|')
for p in ['P0', 'P1', 'P2']:
    c = bp[p]; P, F, B = c.get('PASS', 0), c.get('FAIL', 0), c.get('BLOCKED', 0); te = P + F
    md.append(f'| {p} | {P+F+B} | {P} | {F} | {B} | {round(P/te*100,1) if te else 0}% |')
md.append(f'| **All** | 104 | {ov["PASS"]} | {ov["FAIL"]} | {ov["BLOCKED"]} | {overall_rate}% |\n')
md.append('| category | total | PASS | FAIL | BLOCKED |')
md.append('|---|---|---|---|---|')
for ct in sorted(tal['byCategory']):
    c = tal['byCategory'][ct]
    md.append(f'| {ct} | {sum(c.values())} | {c.get("PASS",0)} | {c.get("FAIL",0)} | {c.get("BLOCKED",0)} |')

md.append('\n## Full results matrix (104)\n')
md.append('| id | cat | pri | data | preflight | verdict | root cause | expected | actual (live) | evidence |')
md.append('|---|---|---|---|---|---|---|---|---|---|')
for x in matrix:
    md.append('| ' + ' | '.join(esc_md(v) for v in [x['id'], x['cat'], x['pri'], x['dataSource'], x['preflight'], x['verdict'], x['rootCause'], x['expected'], x['actual'], x['url']]) + ' |')

md.append('\n## Fixtures created & cleanup\n')
md.append(f'{A["fixtures"]["note"]}\n\n{A["fixtures"]["cleanup"]}\n')
md.append('## Durability / risk follow-ups\n')
for x in A['durability']:
    md.append(f'- {x}')
md.append('')

with open(f'{OUT}/V21_VALIDATION_RESULTS.md', 'w') as f:
    f.write('\n'.join(md))
print('wrote V21_VALIDATION_RESULTS.md')
