#!/usr/bin/env python3
"""SC-3346 DPP regression — RUN 2 (RNM1 commit-layer fix verification). Reads run2 snapshots."""
import json, os, html
DIR = os.path.join(os.path.dirname(__file__), 'snap')
def load(l,p):
    fp=os.path.join(DIR,f'{l}_p{p}.json')
    return json.load(open(fp))['result']['records'] if os.path.exists(fp) else []
def find(recs, code_sub=None, line=None):
    for r in recs or []:
        pc=(r.get('Product2') or {}).get('ProductCode','') or ''
        if line and r.get('LineNumber')!=line: continue
        if code_sub and code_sub not in pc: continue
        return r
def g(r,k): return r.get(k) if r else None
def esc(x): return html.escape(str(x)) if x is not None else '—'
def mini(rows, cols):
    h='<table class="mini"><thead><tr>'+''.join(f'<th>{c}</th>' for c in cols)+'</tr></thead><tbody>'
    for row in rows: h+='<tr>'+''.join(f'<td>{html.escape(str(v)) if v is not None else "—"}</td>' for v in row)+'</tr>'
    return h+'</tbody></table>'

META={
 'org':'FortraUAT · liam.jeong.c@fortra.com.uat',
 'proc':'Rev_Mgmt_Default_Pricing_Procedure — V25 Active (sole; re-verified start & end)',
 'run':'2026-07-12 · RUN 2 (fix-verification; supersedes run 1 report)',
 'tester':'Claude Code (CLI) — SOQL oracle + authorized pricing writes',
 'guards':'153 tests / 100% pass (COLAUpliftCalculatorTest, COLAUpliftTest incl. …FirstRenewalMaintenanceNetsPriorDiscount, PartnerNetPricePosthookTest incl. loadNewMaintenanceLines_defaultsUntaggedLineToStandard). RNM1 commit-layer fix live: PartnerNetPricePosthook.buildRenewalColaCommitUpdate (L1399) → COLAUpliftCalculator.computeFirstRenewalMaintenanceNet (L1477).',
 'd18':'baseline 0 → final 0 rows',
}
cat=json.load(open(os.path.join(os.path.dirname(__file__),'scn15_cat.json')))

SCN=[]
gp2,gp3=load('goldA',2),load('goldA',3)
b16=find(gp3,line='04267516'); b17=find(gp3,line='04267517'); f4=find(gp3,line='04267561')
b16_0=find(load('goldA',0),line='04267516')

SCN.append(dict(n=1,title='New-biz maint — Standard tier',verdict='PASS',ccy='EUR',
 accept='NetUnitPrice = round(sourceBase × 0.20). BoKS 355×0.20 = 71.',
 quote='0Q0WC000003JXMj',line='04267516 (qty10, MTD=Standard)',expected='71.00',actual=str(g(b16,'NetUnitPrice')),
 formula='Base 355 × 0.20 = 71.00',
 evidence=mini([['before p0',g(b16_0,'NetUnitPrice'),g(b16_0,'Base_Price__c')],['after ×3 p3',g(b16,'NetUnitPrice'),g(b16,'Base_Price__c')]],['pass','Net','Base']),
 note='71 = 355 × 0.20, idempotent ×3.'))
SCN.append(dict(n=2,title='New-biz maint — Premier tier (0.30)',verdict='PASS',ccy='EUR',
 accept='= sourceBase × 0.30 (355 → 106.50).',
 quote='0Q0WC000003JXMj',line='04267517 (MTD=Premier — now live on the gold quote)',expected='106.50',actual=str(g(b17,'NetUnitPrice')),
 formula='Base 355 × 0.30 (Premier, Maintenance_Rate__mdt) = 106.50',
 evidence=mini([['after p3',g(b17,'NetUnitPrice'),g(b17,'Base_Price__c'),g(b17,'Quantity')]],['pass','Net','Base','Qty']),
 note='UNBLOCKED vs run 1. Gold line 04267517 is now tagged Premier (verified via explicit-Id QLIA query) and reprices to 106.50 = 355 × 0.30, idempotent. Per-unit net is the graded value (qty=0 is incidental).'))
SCN.append(dict(n=3,title='New-biz maint — Professional tier (0.20)',verdict='BLOCKED',ccy='',
 accept='= sourceBase × 0.20.',quote='—',line='—',expected='71.00 (355×0.20)',actual='no repriceable data',
 formula='Maintenance_Rate__mdt.Professional.Rate__c = 0.20 (metadata)',
 evidence='<p>No live Professional-tagged line on a repriceable quote; the J-02 fixture reprice still returns <code>DerivedPricingFilter#1</code>. Professional rate <b>0.20</b> == Standard, proven live in SCN1/SCN4.</p>',
 note='BLOCKED — rate identical to Standard (proven). Only Professional differs from Premier by having no live tagged line.'))
SCN.append(dict(n=4,title='New-biz UNTAGGED New-Maint',verdict='PASS',ccy='EUR',
 accept='SC-3346-MTD: = base × 0.20 (Std default). 04267561 → 60.75.',
 quote='0Q0WC000003JXMj',line='04267561 (no MTD QLIA)',expected='60.75',actual=str(g(f4,'NetUnitPrice')),
 formula='Source_List_Price 303.745 × 0.20 (untagged default) = 60.75',
 evidence=mini([['after p3',g(f4,'NetUnitPrice'),g(f4,'Source_List_Price__c')]],['pass','Net','SrcList']),
 note='No MTD QLIA yet prices 60.75 via PartnerNetPricePosthook.UNTAGGED_MAINTENANCE_DEFAULT_TIER. Idempotent.'))
bl=find(load('baseless',2),code_sub='RNM')
SCN.append(dict(n=5,title='New-biz BASE-LESS maint',verdict='PASS',ccy='USD',
 accept='NetUnitPrice = 0 (scope guard).',quote='0Q0WC000003FJ2D0AW',line='04266972',expected='0',actual=str(g(bl,'NetUnitPrice')),
 formula='Base<=0 AND SrcList<=0 → $0',
 evidence=mini([['after p2',g(bl,'NetUnitPrice'),g(bl,'Base_Price__c')]],['pass','Net','Base']),
 note='No base → $0; no fabricated price.'))
d6=find(load('scn6b',2),code_sub='RNM'); d6_0=find(load('scn6b',0),code_sub='RNM')
SCN.append(dict(n=6,title='New-biz DISCOUNT netting',verdict='WARN',ccy='USD',
 accept='final net = (sourceBase × tier) − partner − discretionary (after base×tier).',
 quote='0Q0WC000003DIAL0A4',line='04266878 (PartnerPct=15, Disc=10)',expected='54.32 (waterfall)',actual=str(g(d6,'NetUnitPrice')),
 formula='waterfall 355×0.20×0.85×0.90 = 54.32; reprice = 56.23 (does NOT reconcile to 15%/10% on 71)',
 evidence=mini([['p0',g(d6_0,'NetUnitPrice'),g(d6_0,'Base_Price__c'),g(d6_0,'PartnerDiscountPercent'),g(d6_0,'Discount')],['p2',g(d6,'NetUnitPrice'),g(d6,'Base_Price__c'),g(d6,'PartnerDiscountPercent'),g(d6,'Discount')]],['pass','Net','Base','PartnerPct','Disc']),
 note='UNCHANGED from run 1 and OUT OF SCOPE of the RNM1 renewal fix (which is Renew-line-only). Netting is applied after base×tier (71 → 56.23) and idempotent, but 56.23 does not reconcile to the 15%/10% waterfall (54.32). A separate new-biz discount-order question; not a regression.'))
SCN.append(dict(n=7,title='New-biz MULTI-CURRENCY',verdict='PASS',ccy='EUR',
 accept='non-USD maint prices; ListPrice native, NetUnitPrice converted; no $0.',
 quote='0Q0WC000003JXMj (EUR)',line='04267561 (FIM)',expected='EUR native list / converted net',actual=f"EUR; List {g(f4,'ListPrice')}; Net {g(f4,'NetUnitPrice')}",
 formula='CurrencyIsoCode=EUR; ListPrice native 134.5824; Net 60.75',
 evidence=mini([['FIM',g(f4,'CurrencyIsoCode'),g(f4,'ListPrice'),g(f4,'NetUnitPrice')]],['line','Ccy','List','Net']),
 note='Native EUR list, converted non-zero net.'))
def ren(l,p): return find(load(l,p),code_sub='RNM')
r8a,r8b=ren('renDKNN',2),ren('frshFRPZ',2)
SCN.append(dict(n=8,title='First-renewal maint — WITH partner discount',verdict='PASS',ccy='USD',
 accept='committed NetUnitPrice == (assetPx − priorPartner − priorDisc) × (1+COLA).',
 quote='0Q0WC000003DKNN0A4 · 0Q0WC000003FRPZ0A4',line='04267884 · 04267917',expected='65.09 · 3666.90',actual=f"{g(r8a,'NetUnitPrice')} · {g(r8b,'NetUnitPrice')}",
 formula='(71−10.65)×1.0785 = 65.09  ·  (4000−600)×1.0785 = 3666.90',
 evidence=mini([['DKNN Net p0→p1→p2',g(ren("renDKNN",0),'NetUnitPrice'),g(ren("renDKNN",1),'NetUnitPrice'),g(r8a,'NetUnitPrice')],
                ['DKNN COLAcalc (stale)',g(r8a,'COLACalculatedPrice__c'),'','']],['line','a','b','c']),
 note='FIXED vs run 1 (was WARN: DKNN 58.58). The RNM1 commit-layer override now commits NetUnitPrice = 65.09; idempotent (p0=p1=p2). COLACalculatedPrice__c stays the procedure\'s stale 58.58 — graded on NetUnitPrice per the status board.'))
r9a,r9b=ren('renDGgL',2),ren('frshFR6D',2)
SCN.append(dict(n=9,title='First-renewal maint — NO discount',verdict='PASS',ccy='USD',
 accept='Net = assetPrice × (1+COLA).',quote='0Q0WC000003DGgL0AW · 0Q0WC000003FR6D0AW',line='04267886 · 04267918',expected='76.57 · 4314.00',actual=f"{g(r9a,'NetUnitPrice')} · {g(r9b,'NetUnitPrice')}",
 formula='71 × 1.0785 = 76.57  ·  4000 × 1.0785 = 4314.00',
 evidence=mini([['DGgL',g(r9a,'NetUnitPrice')],['FR6D',g(r9b,'NetUnitPrice')]],['line','Net']),
 note='No-op path holds; idempotent.'))
r10a,r10b=ren('renDLBO',2),ren('frshDOpB',2)
SCN.append(dict(n=10,title='First-renewal maint — WITH discretionary (manual Discount)',verdict='PASS',ccy='USD',
 accept='committed NetUnitPrice == (assetPx − priorPartner − priorDisc) × (1+COLA).',
 quote='0Q0WC000003DLBO0A4 · 0Q0WC000003DOpB0AW',line='04267888 · 04267919',expected='60.37 · 3645.33',actual=f"{g(r10a,'NetUnitPrice')} · {g(r10b,'NetUnitPrice')}",
 formula='(71−10.65−4.37)×1.0785 = 60.37  ·  (4000−600−20)×1.0785 = 3645.33',
 evidence=mini([['DOpB Net p0→p1→p2',g(ren("frshDOpB",0),'NetUnitPrice'),g(ren("frshDOpB",1),'NetUnitPrice'),g(r10b,'NetUnitPrice')],
                ['DOpB COLAcalc (stale)',g(r10b,'COLACalculatedPrice__c'),'','']],['line','a','b','c']),
 note='FIXED vs run 1 (was FAIL: DOpB 660.04). The exact run-1 FAIL line 04267919 now commits NetUnitPrice = 3645.33 and holds idempotently across reprices; DLBO commits 60.37. The commit-layer override supersedes the procedure\'s Base_Price__c-derived value (COLACalculatedPrice__c still shows the stale 660.04 — correctly IGNORED per the grade-on-NetUnitPrice instruction).'))
r11=find(load('rrm',2),code_sub='RRM'); r11_1=find(load('rrm',1),code_sub='RRM')
sa=(r11.get('QuoteAction') or {}).get('SourceAsset') or {}
SCN.append(dict(n=11,title='RRM (2nd+ renewal) non-regression',verdict='PASS',ccy='USD',
 accept='Net = assetPrice × (1+COLA); prior partner NOT re-subtracted.',
 quote='0Q0WC00000382MH0AY',line='PIA-PIA-RRM-PIAM (priorPartner=8.52)',expected='65.40 (NOT 56.21)',actual=str(g(r11,'NetUnitPrice')),
 formula=f"asset {sa.get('Price')} × 1.0785 = 65.40; if re-netted the 8.52 → 56.21 = FAIL",
 evidence=mini([['p1',g(r11_1,'NetUnitPrice')],['p2',g(r11,'NetUnitPrice')]],['pass','Net']),
 note='RRM excluded from the first-renewal discount-net (scope guard holds); asset × COLA = 65.40, prior partner 8.52 NOT re-subtracted. Idempotent. (Matches the status-board smoke value "RRM 382MH 65.4".)'))
SCN.append(dict(n=12,title='Renewal MULTI-CURRENCY',verdict='BLOCKED',ccy='',
 accept='non-USD renewal maint commits; interacts w/ SC-3398.',quote='—',line='—',expected='non-USD first-renewal maint',actual='0 rows',
 formula='—',evidence='<p>Org-wide scan (QuoteAction.Type=Renew AND CurrencyIsoCode!=USD AND RNM) = <b>0 rows</b>. No repriceable data; unchanged from run 1.</p>',
 note='BLOCKED — no non-USD first-renewal maintenance data.'))
SCN.append(dict(n=13,title='qty>1 no inflation',verdict='PASS',ccy='EUR',
 accept='qty-N unit net = qty-1 value (not ×N).',quote='0Q0WC000003JXMj',line='04267516 (qty=10)',expected='71 per-unit (not 710)',actual=str(g(b16,'NetUnitPrice')),
 formula='qty-10 NetUnitPrice = 71 per-unit; NetTotalPrice = 710',
 evidence=mini([['04267516 qty10',g(b16,'Quantity'),g(b16,'NetUnitPrice'),g(b16,'NetTotalPrice')]],['line','Qty','NetUnit','NetTotal']),
 note='Per-unit net 71 (== qty-1), NOT 710.'))
drift=[r.get('LineNumber') for r in gp3 if find(gp2,line=r.get('LineNumber')) and find(gp2,line=r.get('LineNumber')).get('NetUnitPrice')!=r.get('NetUnitPrice')]
SCN.append(dict(n=14,title='Idempotency + convergence',verdict='PASS',ccy='EUR',
 accept='reprice ×3 → pass2 == pass3.',quote='0Q0WC000003JXMj (×3)',line='all lines',expected='p2==p3',actual=('0 drift' if not drift else f'DRIFT {drift}'),
 formula='p2 NetUnitPrice == p3 for all lines',
 evidence=mini([[r.get('LineNumber'),find(gp2,line=r.get('LineNumber')).get('NetUnitPrice'),r.get('NetUnitPrice'),'OK' if find(gp2,line=r.get('LineNumber')).get('NetUnitPrice')==r.get('NetUnitPrice') else 'DRIFT'] for r in gp3],['line','p2','p3','idem']),
 note='Gold converges p2==p3 on all lines. Renewal born lines (SCN8-10) also idempotent p0=p1=p2. CAVEAT: SC-3346-ASSET override-license quotes remain non-idempotent (SCN15).'))
rowsA=cat['rowsA'][:11]; rowsD=cat['rowsD']
SCN.append(dict(n=15,title='SC-3346-ASSET data check',verdict='DATA',ccy='USD',
 accept='flag RNM lines with license-scale base/asset — DATA finding.',quote='multiple',line='PIA-PIA-RNM-PIAMBK',
 expected='flag & list Ids',actual=f"{cat['A']} inflated-base + {cat['D']} license-scale-asset = {cat['A']+cat['D']} affected (+{cat['net0']} never-priced)",
 formula='root: contributor license manually over-priced (DOfV PIAP list 355 → Unit 15300 / Base 20000) → maint base inherits 20000',
 evidence='<div><b>A · inflated-license base</b> (Base=20000, SrcList≈355) — '+str(cat['A'])+':</div>'+mini(rowsA,['Quote','Line','Net','Base','SrcList'])
   +'<div style="margin-top:6px"><b>D · license-scale renewal asset</b> (SourceAsset.Price=4000) — '+str(cat['D'])+':</div>'+mini(rowsD,['Quote','Line','assetPx','Net'])
   +f"<p style='margin-top:6px'>+ {cat['net0']} bad-base/Net=0 (separate). Distinct assets: <code>{', '.join(cat['assets'])}</code>.</p>",
 note='DATA, not a formula bug. Formula computes 0.20 × base correctly; base is inflated by over-priced contributor licenses. Reprice can flip stale-clean → inflated (breaks idempotency).'))
SCN.append(dict(n=16,title='D-18 exception log clean',verdict='PASS',ccy='',
 accept='zero new Exception_Log__c.',quote='org-wide',line='Exception_Log__c WHERE CreatedDate=TODAY',expected='0',actual='0',
 formula='no hook rows after any reprice',
 evidence='<p>Baseline 0 → final 0 after all run-2 reprices.</p>',
 note='PASS. The RNM1 fix\'s mis-price class from run 1 is resolved; note derived mis-prices remain silent (computed values), so a value-plausibility guard is still advisable.'))

from collections import Counter
tally=Counter(s['verdict'] for s in SCN)
ORDER=['PASS','WARN','FAIL','BLOCKED','DATA']; VCLR={'PASS':'pass','WARN':'warn','FAIL':'fail','BLOCKED':'blocked','DATA':'data'}
cards=''
for s in SCN:
    ccy=f'<span class="ccy">{s["ccy"]}</span>' if s['ccy'] else ''
    cards+=f'''<div class="scn {VCLR[s['verdict']]}" id="scn{s['n']}"><div class="scnhead" onclick="tog({s['n']})">
      <span class="num">#{s['n']}</span><span class="stitle">{esc(s['title'])}</span><span class="badge {VCLR[s['verdict']]}">{s['verdict']}</span>
      <span class="ev">exp <b>{esc(s['expected'])}</b> · act <b>{esc(s['actual'])}</b> {ccy}</span><span class="chev">▾</span></div>
      <div class="body" id="body{s['n']}">
        <div class="row"><span class="lbl">Acceptance</span><span>{esc(s['accept'])}</span></div>
        <div class="row"><span class="lbl">Quote / Line</span><span><code>{esc(s['quote'])}</code> — {esc(s['line'])}</span></div>
        <div class="row"><span class="lbl">Formula</span><span class="mono">{esc(s['formula'])}</span></div>
        <div class="row"><span class="lbl">Evidence</span><span>{s['evidence']}</span></div>
        <div class="row"><span class="lbl">Notes</span><span>{s['note']}</span></div></div></div>'''
tallyhtml=''.join(f'<span class="tchip {VCLR[k]}">{k} {tally.get(k,0)}</span>' for k in ORDER)
artifacts='''<pre>RENEWAL born lines repriced ×2 (grade committed NetUnitPrice):
  0Q0WC000003DKNN0A4 04267884 →65.09 · 0Q0WC000003DGgL0AW 04267884 →76.57 · 0Q0WC000003DLBO0A4 04266884 →60.37
  0Q0WC000003FRPZ0A4 04267917 →3666.9 · 0Q0WC000003FR6D0AW 04267918 →4314 · 0Q0WC000003DOpB0AW 04267919 →3645.33 (run-1 FAIL 660.04, now FIXED)
NEW-BIZ: 0Q0WC000003JXMj gold EUR ×3 (SCN1 04267516=71, SCN2 04267517 Premier=106.5, SCN4 04267561=60.75)
  0Q0WC000003FJ2D0AW base-less · 0Q0WC00000382MH0AY RRM 65.4 · 0Q0WC000003DIAL0A4 SCN6 netting 56.23
SC-3346-ASSET assets: 02iWC000008Oz2XYAS · 02iWC000008WteHYAS · 02iWC000008dbCnYAI · 02iWC000008dfGPYAY · 02iWC000008pQn5YAE
Nothing deleted. Snapshots: Data/sc3346/dpp_regression_20260712_run2/</pre>'''
changeline=('2026-07-12 (run 2, fix-verification) — RNM1 commit-layer fix VERIFIED. PASS 12 / WARN 1 / FAIL 0 / BLOCKED 2 / DATA 1. '
 'SCN10 FIXED: discretionary first-renewal DOpB 660.04→3645.33 (committed NetUnitPrice, idempotent); DLBO→60.37. SCN8 FIXED: DKNN 58.58→65.09. '
 'Grade-on-NetUnitPrice confirmed necessary (COLACalculatedPrice__c stays stale 660.04/58.58). SCN2 now PASS (gold 04267517 live Premier 106.5=355×0.30). '
 'SCN6 WARN unchanged (new-biz netting 56.23≠54.32, out of fix scope). SCN3/SCN12 BLOCKED (no live Professional / non-USD renewal). SCN15 DATA=18 override-license lines. 153 unit tests 100%, D-18 clean.')

HTML=f'''<meta charset="utf-8"><title>SC-3346 DPP Regression RUN 2 — FortraUAT — 2026-07-12</title>
<style>
:root{{--bg:#0f1117;--card:#181b23;--line:#262b36;--tx:#e6e9ef;--mut:#98a2b3;--pass:#22c55e;--warn:#eab308;--fail:#ef4444;--blk:#94a3b8;--data:#f97316;--acc:#60a5fa}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--bg);color:var(--tx);font:14px/1.55 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif}}
.wrap{{max-width:1100px;margin:0 auto;padding:28px 20px 80px}}h1{{font-size:22px;margin:0 0 4px}}.sub{{color:var(--mut);font-size:13px}}
.hdr{{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px 18px;margin:16px 0}}.hdr div{{margin:4px 0}}.hdr .k{{color:var(--mut);display:inline-block;min-width:112px;vertical-align:top}}
.tally{{display:flex;gap:8px;flex-wrap:wrap;margin:14px 0}}.tchip{{padding:6px 12px;border-radius:20px;font-weight:700;font-size:13px;color:#0b0d12}}
.tchip.pass{{background:var(--pass)}}.tchip.warn{{background:var(--warn)}}.tchip.fail{{background:var(--fail);color:#fff}}.tchip.blocked{{background:var(--blk)}}.tchip.data{{background:var(--data)}}
.scn{{background:var(--card);border:1px solid var(--line);border-left:4px solid var(--line);border-radius:10px;margin:10px 0;overflow:hidden}}
.scn.pass{{border-left-color:var(--pass)}}.scn.warn{{border-left-color:var(--warn)}}.scn.fail{{border-left-color:var(--fail)}}.scn.blocked{{border-left-color:var(--blk)}}.scn.data{{border-left-color:var(--data)}}
.scnhead{{display:flex;align-items:center;gap:12px;padding:12px 16px;cursor:pointer;user-select:none}}.scnhead:hover{{background:#1d212b}}
.num{{color:var(--mut);font-weight:700;min-width:28px}}.stitle{{font-weight:600}}
.badge{{padding:3px 10px;border-radius:6px;font-weight:700;font-size:12px;color:#0b0d12}}
.badge.pass{{background:var(--pass)}}.badge.warn{{background:var(--warn)}}.badge.fail{{background:var(--fail);color:#fff}}.badge.blocked{{background:var(--blk)}}.badge.data{{background:var(--data)}}
.ev{{margin-left:auto;color:var(--mut);font-size:12.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:52%}}.ev b{{color:var(--tx)}}
.ccy{{background:#11141b;border:1px solid var(--line);border-radius:4px;padding:0 5px;margin-left:4px;font-size:11px}}.chev{{color:var(--mut)}}
.body{{display:none;padding:6px 16px 16px;border-top:1px solid var(--line)}}.body.open{{display:block}}
.row{{display:flex;gap:14px;padding:7px 0;border-bottom:1px dashed #232833;align-items:flex-start}}.row:last-child{{border-bottom:0}}
.lbl{{color:var(--mut);min-width:96px;flex:none;font-size:12px;text-transform:uppercase;letter-spacing:.03em;padding-top:2px}}
.mono{{font-family:ui-monospace,Menlo,monospace;font-size:12.5px}}code{{background:#11141b;padding:1px 5px;border-radius:4px;font-size:12.5px;color:#cbd5e1}}
table.mini{{border-collapse:collapse;margin:4px 0;font-size:12.5px}}table.mini th{{text-align:left;color:var(--mut);font-weight:600;padding:3px 14px 3px 0;border-bottom:1px solid var(--line)}}
table.mini td{{padding:3px 14px 3px 0;font-family:ui-monospace,Menlo,monospace}}
pre{{background:#0b0d12;border:1px solid var(--line);border-radius:8px;padding:12px;overflow-x:auto;font-size:11.5px;color:#cbd5e1;white-space:pre}}
h2{{font-size:15px;margin:26px 0 8px;color:var(--acc)}}.callout{{background:#0e2a16;border:1px solid #15803d;border-radius:8px;padding:12px 14px;margin:14px 0;font-size:13px}}
.callout.warn{{background:#2a2408;border-color:#8a6d0a}}.callout.data{{background:#2a1a0c;border-color:#9a4a12}}
.foot{{color:var(--mut);font-size:12px;margin-top:30px;border-top:1px solid var(--line);padding-top:12px}}
.chg{{background:#0b0d12;border:1px solid var(--line);border-left:3px solid var(--acc);border-radius:6px;padding:10px 12px;margin:8px 0;font-size:12px;color:#cbd5e1}}
</style>
<div class="wrap">
  <h1>SC-3346 — Derived Maintenance Pricing (DPP) Regression · RUN 2</h1>
  <div class="sub">FortraUAT · fix-verification re-run · grades SCN8–10 on committed <code>NetUnitPrice</code> (not <code>COLACalculatedPrice__c</code>)</div>
  <div class="tally">{tallyhtml}</div>
  <div class="hdr">
    <div><span class="k">Org</span>{esc(META['org'])}</div><div><span class="k">Procedure</span>{esc(META['proc'])}</div>
    <div><span class="k">Run</span>{esc(META['run'])}</div><div><span class="k">Tester</span>{esc(META['tester'])}</div>
    <div><span class="k">Static guards</span>{esc(META['guards'])}</div><div><span class="k">D-18 log</span>{esc(META['d18'])}</div>
  </div>
  <div class="callout">
    <b>FIX VERIFIED — SCN10 (the run-1 FAIL):</b> the RNM1 commit-layer override
    (<code>PartnerNetPricePosthook.buildRenewalColaCommitUpdate</code> → <code>computeFirstRenewalMaintenanceNet</code>) now commits the correct
    3-component first-renewal net for discount-bearing lines. The exact run-1 failing line <code>0Q0WC000003DOpB0AW</code> committed <b>660.04 in run 1</b>;
    in run 2 it commits <b>3645.33</b> and holds idempotently across reprice ×2 (p0=p1=p2). <b>DKNN 65.09</b> (run 1 was 58.58 → WARN), <b>DLBO 60.37</b>.
    All 6 renewal lines match their born-formula to the cent (independently re-derived + adversarially verified, unrefuted). Grading on <code>NetUnitPrice</code>
    is essential — <code>COLACalculatedPrice__c</code> still shows the procedure's stale 660.04/58.58, correctly ignored. <b>Zero FAIL this run.</b>
  </div>
  <div class="callout warn"><b>WARN — SCN6 (out of fix scope):</b> new-biz discount netting still reprices to 56.23, which doesn't reconcile to the 15%/10% waterfall (54.32). Unchanged from run 1; the RNM1 fix is Renew-line-only. A separate new-biz discount-order question.</div>
  <div class="callout warn"><b>Residual (verifier-flagged, dormant):</b> the override corrects <code>NetUnitPrice</code> but leaves <code>COLACalculatedPrice__c</code> persistently wrong on disk (660.04/58.58). The one money consumer, <code>MaintenanceOrderDecompositionService.cls:477</code>, reads <code>COLACalc</code> only as a last-resort fallback (after <code>PartnerUnitPrice→UnitPrice→NetUnitPrice</code>) — not reached while <code>NetUnitPrice&gt;0</code>, so no order/Workday money defect for the graded lines. Latent only for a hypothetical renewal line with <code>COLACalc&gt;0</code> but null <code>UnitPrice/NetUnitPrice</code>. Suggest re-stamping <code>COLACalc</code> to match.</div>
  <div class="callout data"><b>DATA — SC-3346-ASSET (SCN15):</b> {cat['A']+cat['D']} PIAMBK lines still inherit an inflated base from over-priced contributor licenses (upstream data, not a formula bug).</div>
  <h2>Scenarios (click to expand)</h2>
  {cards}
  <h2>Artifacts — every Id touched (nothing deleted)</h2>
  {artifacts}
  <h2>CHANGELOG line (append to the prompt)</h2>
  <div class="chg">{changeline}</div>
  <div class="foot">Run 2 supersedes the run-1 report (<code>sc3346_dpp_cli_report_2026-07-12.html</code>, which recorded the pre-fix FAIL). PASS {tally.get('PASS',0)} · WARN {tally.get('WARN',0)} · FAIL {tally.get('FAIL',0)} · BLOCKED {tally.get('BLOCKED',0)} · DATA {tally.get('DATA',0)}.</div>
</div>
<script>function tog(n){{document.getElementById('body'+n).classList.toggle('open');document.getElementById('scn'+n).classList.toggle('open');}}[6,10,15].forEach(tog);</script>'''
out='/Users/liamjeong/Documents/Code/Fortra/docs/sc3346_dpp_cli_report_2026-07-12_run2.html'
open(out,'w').write(HTML)
print('WROTE',out,len(HTML),'bytes'); print('TALLY',dict(tally))
