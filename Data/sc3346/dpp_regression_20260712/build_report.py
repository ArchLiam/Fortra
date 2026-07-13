#!/usr/bin/env python3
"""Generate the SC-3346 DPP regression HTML report (v2, adversarially-reviewed) from captured oracle snapshots."""
import json, os, html
DIR = os.path.join(os.path.dirname(__file__), 'snap')

def load(label, p):
    fp = os.path.join(DIR, f'{label}_p{p}.json')
    if not os.path.exists(fp): return None
    return json.load(open(fp)).get('result', {}).get('records', [])

def find(recs, code_sub=None, fpt=None, line=None):
    for r in recs or []:
        pc = (r.get('Product2') or {}).get('ProductCode', '') or ''
        if line and r.get('LineNumber') != line: continue
        if code_sub and code_sub not in pc: continue
        if fpt and r.get('Fortra_Product_Type__c') != fpt: continue
        return r
    return None

def g(r, k): return r.get(k) if r else None
def esc(x): return html.escape(str(x)) if x is not None else '—'

META = {
    'org': 'FortraUAT · liam.jeong.c@fortra.com.uat · https://fortra--uat.sandbox.my.salesforce.com',
    'proc': 'Rev_Mgmt_Default_Pricing_Procedure — V25 Active (SELECT VersionNumber,Status FROM ExpressionSetDefinitionVersion WHERE …DeveloperName=\'Rev_Mgmt_Default_Pricing_Procedure\' AND Status=\'Active\' → 1 row: {V25, Active}; re-verified at run start AND end)',
    'run': '2026-07-12',
    'tester': 'Claude Code (CLI) — SOQL/sf read-oracle + authorized pricing writes (Force-reprice, provision, QLIA create)',
    'guards': '152 tests / 100% pass, 0 fail across COLAUpliftCalculatorTest, COLAUpliftTest, PartnerNetPricePosthookTest. Named §CHECKS methods present & green: COLAUpliftTest.testPopulateCOLAFields_FirstRenewalMaintenanceNetsPriorDiscount (L221), PartnerNetPricePosthookTest.loadNewMaintenanceLines_defaultsUntaggedLineToStandard (L1126). Scope guard COLAUpliftHandler.cls:358-359 (isFirstRenewalMaintenance gated on SourceAsset.Product2.Fortra_Product_Type__c==\'New Maintenance\') confirmed by source read.',
    'd18': 'baseline 0 → final 0 rows (Exception_Log__c WHERE CreatedDate=TODAY). Checked after every reprice batch. NOTE: the SCN10/SCN15 mis-prices threw NO exception — they are wrong computed values, invisible to the D-18 net.',
}

def mini(rows, cols):
    h = '<table class="mini"><thead><tr>' + ''.join(f'<th>{c}</th>' for c in cols) + '</tr></thead><tbody>'
    for row in rows:
        h += '<tr>' + ''.join(f'<td>{html.escape(str(v)) if v is not None else "—"}</td>' for v in row) + '</tr>'
    return h + '</tbody></table>'

SCN = []
g_p0, g_p2, g_p3 = load('goldA',0), load('goldA',2), load('goldA',3)
b16, b17 = find(g_p3,line='04267516'), find(g_p3,line='04267517')
b16_0 = find(g_p0,line='04267516')
f4, f4_0 = find(g_p3,line='04267561'), find(g_p0,line='04267561')

# SCN1
SCN.append(dict(n=1, title='New-biz maint — Standard tier', verdict='PASS', ccy='EUR',
    accept='NetUnitPrice = round(sourceBase × 0.20, 2). BoKS 355×0.20 = 71.',
    quote='0Q0WC000003JXMj', line='04267516 (qty10) / 04267517 (qty1) — both MTD QLIA = Standard (verified)',
    expected='71.00', actual=str(g(b16,'NetUnitPrice')),
    formula='Base_Price__c 355 × 0.20 (Standard) = 71.00 (no own discounts)',
    evidence=mini([['before p0', g(b16_0,'NetUnitPrice'), g(b16_0,'Base_Price__c'), g(b16_0,'Quantity')],
                   ['after ×3 p3', g(b16,'NetUnitPrice'), g(b16,'Base_Price__c'), g(b16,'Quantity')]],
                  ['pass','Net','Base','Qty']),
    note='Net = 71 = 355 × 0.20 on both lines; idempotent across 3 passes. Both carry MTD = Standard.'))
# SCN2
SCN.append(dict(n=2, title='New-biz maint — Premier tier (0.30)', verdict='BLOCKED', ccy='',
    accept='= sourceBase × 0.30 (355 → 106.50).',
    quote='J-02 fixture 0Q0WC000003KrOD0A0 (minted, tagged Premier)', line='—',
    expected='106.50', actual='no repriceable data',
    formula='Maintenance_Rate__mdt.Premier.Rate__c = 0.30 (confirmed in metadata)',
    evidence='<p>No live QuoteLineItem carries <code>Maintenance Type Defn = Premier</code> (org-wide QLIA scan = 0). The J-02 fixture '
             'was minted and tagged Premier (QLIA <code>0zuWC000006Q3d7YAC</code>), but a Force-reprice returns '
             '<code>SF-Pricing-00006 DerivedPricingFilter#1</code> — the §MECH-designated <b>BLOCKED (pre-existing infra, NOT DPP)</b> '
             'condition (Apex-inserted lines lack derived-pricing context). Premier rate <b>0.30</b> confirmed in metadata; tier '
             'mechanism proven live for Standard (SCN1). Retagging a live BoKS line was rejected: it already holds a Standard QLIA '
             '(can\'t hold two MTD values) and swapping requires a forbidden QLIA delete.</p>',
    note='BLOCKED — no repriceable Premier line. Metadata + live Standard proof give strong indirect confidence.'))
# SCN3
SCN.append(dict(n=3, title='New-biz maint — Professional tier (0.20)', verdict='BLOCKED', ccy='',
    accept='= sourceBase × 0.20.',
    quote='J-02 fixture 0Q0WC000003KrOD0A0 (tagged Professional)', line='—',
    expected='71.00 (355×0.20)', actual='no repriceable data',
    formula='Maintenance_Rate__mdt.Professional.Rate__c = 0.20 (confirmed in metadata)',
    evidence='<p>Same block as SCN2 (<code>DerivedPricingFilter#1</code>). Professional rate <b>0.20</b> confirmed in metadata — '
             'identical to Standard (0.20), which passes live in SCN1/SCN4. QLIA created: <code>0zuWC000006Q3ejYAC</code>.</p>',
    note='BLOCKED — no repriceable Professional line. Rate == Standard (0.20), proven live.'))
# SCN4
SCN.append(dict(n=4, title='New-biz UNTAGGED New-Maint (no MTD attr, base>0)', verdict='PASS', ccy='EUR',
    accept='SC-3346-MTD: = base × 0.20 (Std default). Repro 04267561 → 60.75.',
    quote='0Q0WC000003JXMj', line='04267561 (FIM-FIM-RNM-DPEENM, NO MTD QLIA — verified)',
    expected='60.75', actual=str(g(f4,'NetUnitPrice')),
    formula='Source_List_Price__c 303.745 × 0.20 (UNTAGGED posthook default) = 60.75',
    evidence=mini([['before p0', g(f4_0,'NetUnitPrice'), g(f4_0,'Source_List_Price__c')],
                   ['after p3', g(f4,'NetUnitPrice'), g(f4,'Source_List_Price__c')]],['pass','Net','SrcList']),
    note='Line has no Maintenance Type Defn QLIA yet prices 60.75 via PartnerNetPricePosthook.UNTAGGED_MAINTENANCE_DEFAULT_TIER. '
         'The source base for this line is Source_List_Price__c (303.745), not Base_Price__c (325). Idempotent.'))
# SCN5
bl, bl0 = find(load('baseless',2),code_sub='RNM'), find(load('baseless',0),code_sub='RNM')
SCN.append(dict(n=5, title='New-biz BASE-LESS maint', verdict='PASS', ccy='USD',
    accept='NetUnitPrice = 0 (scope guard; no fabricated price).',
    quote='0Q0WC000003FJ2D0AW', line='04266972 (FIM-FIM-RNM-TREN)',
    expected='0', actual=str(g(bl,'NetUnitPrice')),
    formula='Base_Price__c<=0 AND Source_List_Price__c<=0 → correctly $0',
    evidence=mini([['before p0', g(bl0,'NetUnitPrice'), g(bl0,'Base_Price__c'), g(bl0,'Source_List_Price__c')],
                   ['after p2', g(bl,'NetUnitPrice'), g(bl,'Base_Price__c'), g(bl,'Source_List_Price__c')]],['pass','Net','Base','SrcList']),
    note='No pricing base → $0; scope guard holds, no fabricated price.'))
# SCN6 -> WARN
d6, d6_0, d6_1 = find(load('scn6b',2),code_sub='RNM'), find(load('scn6b',0),code_sub='RNM'), find(load('scn6b',1),code_sub='RNM')
SCN.append(dict(n=6, title='New-biz DISCOUNT netting', verdict='WARN', ccy='USD',
    accept='final net = (sourceBase × tier) − partner − discretionary (applied after base×tier).',
    quote='0Q0WC000003DIAL0A4', line='04266878 (PIA-PIA-RNM-PIAMBK; PartnerPct=15, Discount=10)',
    expected='54.32 (strict waterfall)', actual=str(g(d6,'NetUnitPrice')),
    formula='waterfall 355×0.20×(1−0.15)×(1−0.10) = 54.32  —  BUT reprice converged to 56.23 (does NOT reconcile to 15%/10% on 71)',
    evidence=mini([['before p0', g(d6_0,'NetUnitPrice'), g(d6_0,'Base_Price__c'), g(d6_0,'PartnerDiscountPercent'), g(d6_0,'Discount')],
                   ['after p1', g(d6_1,'NetUnitPrice'), g(d6_1,'Base_Price__c'), g(d6_1,'PartnerDiscountPercent'), g(d6_1,'Discount')],
                   ['after p2', g(d6,'NetUnitPrice'), g(d6,'Base_Price__c'), g(d6,'PartnerDiscountPercent'), g(d6,'Discount')]],
                  ['pass','Net','Base','PartnerPct','Disc']),
    note='QUALIFIED. Netting IS applied after base×tier (71 → 56.23, both discount fields bite) and is idempotent (p1==p2). '
         'HOWEVER the reprice moved the line OFF its formula-correct value: the stored p0 value 54.32 exactly equals the strict '
         'waterfall 71×0.85×0.90, but the reprice converged to 56.23, which reconciles to no clean combination of the 15% partner / '
         '10% discount on 71. Directionally correct, numerically unexplained → WARN, not clean PASS. Needs a discount-order review.'))
# SCN7
SCN.append(dict(n=7, title='New-biz MULTI-CURRENCY', verdict='PASS', ccy='EUR',
    accept='non-USD maint prices; ListPrice native, NetUnitPrice converted; no $0.',
    quote='0Q0WC000003JXMj (EUR)', line='04267561 (FIM — graded on native-list line)',
    expected='EUR native list, converted non-zero net', actual=f"EUR; List {g(f4,'ListPrice')}; Net {g(f4,'NetUnitPrice')}",
    formula='CurrencyIsoCode=EUR; ListPrice native 134.5824 (FIM); NetUnitPrice 60.75 — no $0',
    evidence=mini([['FIM 04267561', g(f4,'CurrencyIsoCode'), g(f4,'ListPrice'), g(f4,'NetUnitPrice')],
                   ['BoKS 04267516', g(b16,'CurrencyIsoCode'), g(b16,'ListPrice'), g(b16,'NetUnitPrice')]],['line','Ccy','List(native)','Net']),
    note='Graded on the FIM line (native EUR ListPrice 134.5824, converted Net 60.75). BoKS derived lines legitimately carry '
         'ListPrice=0 (derived, not catalog-priced) — not a data gap.'))
def ren(label,p,sub='RNM'): return find(load(label,p),code_sub=sub)
# SCN8 -> WARN
r8, r8_0 = ren('frshFRPZ',2), ren('frshFRPZ',0)
dknn2 = ren('renDKNN',2)
SCN.append(dict(n=8, title='First-renewal maint — WITH partner discount', verdict='WARN', ccy='USD',
    accept='post-provision TermDefined/Renew: Net after reprice == UnitPrice == (assetPx − priorPartner − priorDisc) × (1+COLA).',
    quote='fresh 0Q0WC000003FRPZ0A4  ·  named §DATA 0Q0WC000003DKNN0A4', line='04267917 (fresh)  ·  04267884 (DKNN)',
    expected='3666.90 (fresh) · 65.09 (named DKNN)', actual=f"3666.90 (fresh PASS) · {g(dknn2,'NetUnitPrice')} (DKNN — MISS)",
    formula='fresh: (4000 − 600 − 0) × 1.0785 = 3666.90 ✔  ·  DKNN expected (71 − 10.65) × 1.0785 = 65.09, actual reprice = 58.58 (= over-eroded Base 54.32 × 1.0785)',
    evidence=mini([['fresh FRPZ born p0', g(r8_0,'UnitPrice'), g(r8_0,'NetUnitPrice'), g(r8_0,'Base_Price__c')],
                   ['fresh FRPZ reprice p2', g(r8,'UnitPrice'), g(r8,'NetUnitPrice'), g(r8,'Base_Price__c')],
                   ['named DKNN reprice p2', g(dknn2,'UnitPrice'), g(dknn2,'NetUnitPrice'), g(dknn2,'Base_Price__c')]],
                  ['line','Unit','Net','Base']),
    note='QUALIFIED. The FRESH provision→reprice path (the code under test per §GR5) is CORRECT: FRPZ gets Base = asset − priorPartner '
         '= 3400 and Net == Unit == 3666.90. BUT the prompt\'s NAMED §DATA real-data sample DKNN reprices to 58.58, not its documented '
         '65.09 — its born Base (54.32 = 71×0.85×0.90) is an over-eroded value carried from an earlier state, and the reprice uplifts '
         'that wrong base by COLA rather than the correct (asset − priorPartner) = 60.35. FRPZ passes partly because a partner-ONLY '
         'line\'s correct base (asset−partner) coincides with what the buggy path yields; the named DKNN (which also embeds a phantom '
         'discretionary erosion) exposes the gap. Fresh partner-only ✔; pre-existing born renewal lines are at risk → WARN. '
         'This is the same reprice-does-not-preserve-born-net family as SCN10 (mechanism 2: over-eroded base).'))
# SCN9
r9 = ren('frshFR6D',2); r9_0 = ren('frshFR6D',0); dggl = ren('renDGgL',2); dggl0 = ren('renDGgL',0)
SCN.append(dict(n=9, title='First-renewal maint — NO discount', verdict='PASS', ccy='USD',
    accept='Net = assetPrice × (1+COLA); fix is a no-op.',
    quote='fresh 0Q0WC000003FR6D0AW  ·  §DATA 0Q0WC000003DGgL0AW', line='04267918 · 04267884',
    expected='4314.00 · 76.57', actual=f"{g(r9,'NetUnitPrice')} · {g(dggl,'NetUnitPrice')}",
    formula='4000 × 1.0785 = 4314.00  ·  71 × 1.0785 = 76.57',
    evidence=mini([['FR6D born p0', g(r9_0,'UnitPrice'), g(r9_0,'NetUnitPrice')],
                   ['FR6D reprice p2', g(r9,'UnitPrice'), g(r9,'NetUnitPrice')],
                   ['DGgL reprice p2', g(dggl,'UnitPrice'), g(dggl,'NetUnitPrice')]],['line','Unit','Net']),
    note='Both no-discount renewals reprice to Net == Unit (fix is a no-op). Base stays consistent — the discount-erosion bug does not '
         'trigger without a discount.'))
# SCN10 FAIL
r10, r10_0, r10_1 = ren('frshDOpB',2), ren('frshDOpB',0), ren('frshDOpB',1)
dlbo = ren('renDLBO',2)
SCN.append(dict(n=10, title='First-renewal maint — WITH discretionary (manual Discount)', verdict='FAIL', ccy='USD',
    accept='Net after reprice == UnitPrice == (assetPx − priorPartner − priorDisc) × (1+COLA).',
    quote='fresh 0Q0WC000003DOpB0AW  ·  §DATA 0Q0WC000003DLBO0A4', line='04267919 (fresh) · 04266884 (DLBO)',
    expected='3645.33 (fresh born Unit) · 60.37 (DLBO)', actual=f"660.04 (fresh) · {g(dlbo,'NetUnitPrice')} (DLBO)",
    formula='fresh born Unit = (4000−600−20)×1.0785 = 3645.33 ✔  ·  reprice Net = 660.04 = (assetPx 4000 × 0.20 = 800) × 0.85 × 0.90 × 1.0785',
    evidence=mini([['fresh DOpB born p0', g(r10_0,'UnitPrice'), g(r10_0,'NetUnitPrice'), g(r10_0,'Base_Price__c'), g(r10_0,'Discount')],
                   ['fresh DOpB reprice p1', g(r10_1,'UnitPrice'), g(r10_1,'NetUnitPrice'), g(r10_1,'Base_Price__c'), g(r10_1,'Discount')],
                   ['fresh DOpB reprice p2', g(r10,'UnitPrice'), g(r10,'NetUnitPrice'), g(r10,'Base_Price__c'), g(r10,'Discount')],
                   ['named DLBO reprice p2', g(dlbo,'UnitPrice'), g(dlbo,'NetUnitPrice'), g(dlbo,'Base_Price__c'), g(dlbo,'Discount')]],
                  ['line','Unit','Net','Base','Disc']),
    note='DEFECT (confirmed by 2 independent re-graders + an adversarial refuter that could not overturn it). Provision borns the '
         'correct 3-component UnitPrice (3645.33), but a Force-reprice does NOT preserve it. TWO wrong mechanisms observed for '
         'discretionary renewals: (1) FRESH DOpB — Base collapses to assetPx×0.20 = 800 (the NEW-BIZ maintenance tier base, wrong for a '
         'QAtype=Renew line) then partner% + manual Discount + COLA compound → Net 660.04 (a 5.5× under-price); (2) pre-existing DLBO — '
         'over-eroded Base 54.32 × COLA → 58.58. Both overwrite NetUnitPrice/NetTotalPrice while only the cosmetic UnitPrice keeps the '
         'correct value. Root: the RNM1 fix was validated on born UnitPrice only; the reprice/NetUnitPrice path is unguarded when a '
         'discretionary discount is present. ERROR IS SILENT — no D-18 row.'))
# SCN11 -> fix RRM filter
r11, r11_1 = ren('rrm',2,sub='RRM'), ren('rrm',1,sub='RRM')
SCN.append(dict(n=11, title='RRM (2nd+ renewal) non-regression', verdict='PASS', ccy='USD',
    accept='Net = assetPrice × (1+COLA); prior partner discount NOT re-subtracted.',
    quote='0Q0WC00000382MH0AY', line='PIA-PIA-RRM-PIAM (QA=Renew; priorPartner=8.52; COLA=20%)',
    expected='72.77 (NOT 62.54)', actual=str(g(r11,'NetUnitPrice')),
    formula='assetPx 60.64 × (1 + 20%) = 72.77. If it re-netted the 8.52 partner → (60.64−8.52)×1.20 = 62.54 = FAIL.',
    evidence=mini([['after p1', g(r11_1,'NetUnitPrice'), g(r11_1,'UnitPrice')],
                   ['after p2', g(r11,'NetUnitPrice'), g(r11,'UnitPrice')]],['pass','Net','Unit']),
    note='Scope guard holds: RRM (Renewal Maintenance product) is EXCLUDED from the first-renewal discount-net. Net = asset × COLA = '
         '72.77; the prior 8.52 partner discount is NOT re-subtracted (would be 62.54). Idempotent p1==p2. (This line\'s own COLA is 20%, '
         'higher than the 7.85% on the SCN8-10 lines — that is the record\'s actual COLA_Uplift_Percent__c.)'))
# SCN12 BLOCKED
SCN.append(dict(n=12, title='Renewal MULTI-CURRENCY', verdict='BLOCKED', ccy='',
    accept='non-USD renewal maint commits; interacts w/ SC-3398.',
    quote='—', line='—', expected='non-USD first-renewal maint', actual='0 rows exist',
    formula='—',
    evidence='<p>Org-wide scan for a non-USD first-renewal maintenance line (<code>QuoteAction.Type=Renew</code> AND '
             '<code>CurrencyIsoCode!=USD</code> AND RNM product) = <b>0 rows</b>. No repriceable data. Minting requires a non-USD renewal '
             'quote with OneTime carryovers (none exist); Apex-fixture quotes hit the same <code>DerivedPricingFilter#1</code> block. '
             'Interacts with SC-3398 (localization by Apex posthook).</p>',
    note='BLOCKED — no non-USD first-renewal maintenance data in the org.'))
# SCN13
SCN.append(dict(n=13, title='qty>1 no inflation', verdict='PASS', ccy='EUR',
    accept='born net is per-unit; qty-N unit net = qty-1 value (not ×N).',
    quote='0Q0WC000003JXMj', line='04267516 (qty=10) vs 04267517 (qty=1)',
    expected='71 per-unit (not 710)', actual=str(g(b16,'NetUnitPrice')),
    formula='qty-10 NetUnitPrice = 71 (per-unit) == qty-1 NetUnitPrice = 71; NetTotalPrice = 710 (correct extension)',
    evidence=mini([['04267516 qty10', g(b16,'Quantity'), g(b16,'NetUnitPrice'), g(b16,'NetTotalPrice')],
                   ['04267517 qty1', g(b17,'Quantity'), g(b17,'NetUnitPrice'), g(b17,'NetTotalPrice')]],['line','Qty','NetUnit','NetTotal']),
    note='qty-10 per-unit net = 71 (== qty-1), NOT 710. Verified on the new-biz derived-maint path (AssetNetUnitPrice.perUnit). '
         'Caveat: a qty>1 RENEWAL born line was not separately available (fresh renewal fixtures are qty-1), so the renewal per-unit path '
         'is not independently exercised here.'))
# SCN14
drift = [r.get('LineNumber') for r in g_p3 if find(g_p2,line=r.get('LineNumber')) and find(g_p2,line=r.get('LineNumber')).get('NetUnitPrice')!=r.get('NetUnitPrice')]
SCN.append(dict(n=14, title='Idempotency + convergence', verdict='PASS', ccy='EUR',
    accept='reprice ×3 → converges by pass 2, pass 2 == pass 3.',
    quote='0Q0WC000003JXMj (×3)', line='all 6 lines',
    expected='pass2 == pass3 on every line', actual=('converged — 0 drift' if not drift else f'DRIFT {drift}'),
    formula='p2 NetUnitPrice == p3 NetUnitPrice for all lines',
    evidence=mini([[r.get('LineNumber'), find(g_p2,line=r.get('LineNumber')).get('NetUnitPrice'), r.get('NetUnitPrice'),
                    'OK' if find(g_p2,line=r.get('LineNumber')).get('NetUnitPrice')==r.get('NetUnitPrice') else 'DRIFT'] for r in g_p3],
                  ['line','Net p2','Net p3','idem']),
    note='Gold quote converges: pass2 == pass3 on all 6 lines. CAVEAT: SC-3346-ASSET override-license quotes are NOT idempotent — '
         'DOfV (0Q0WC000003DOfV0AW) went 54.32 → 56.23 → 3168 across passes as its Base flipped to the inflated 20000 (SCN15).'))
# SCN15 DATA (reconciled)
cat = json.load(open(os.path.join(os.path.dirname(__file__),'scn15_categorized.json')))
Arows = [[r['QuoteId'], r['LineNumber'], r['NetUnitPrice'], r['Base_Price__c'], r['Source_List_Price__c']] for r in cat['A_inflated']]
Drows = [[r['QuoteId'], r['LineNumber'], r['assetPx'], r['Net']] for r in cat['D_renewal_asset']]
SCN.append(dict(n=15, title='SC-3346-ASSET data check', verdict='DATA', ccy='USD',
    accept='flag any RNM line whose base/SourceAsset.Price is license-scale — DATA finding, do not "fix" in formula.',
    quote='multiple quotes', line='PIA-PIA-RNM-PIAMBK',
    expected='flag & list Ids', actual=f"{len(cat['A_inflated'])} inflated-base + {len(cat['D_renewal_asset'])} license-scale-asset = {len(cat['A_inflated'])+len(cat['D_renewal_asset'])} affected",
    formula='root: contributor license manually overridden (DOfV license PIAP list 355 → Unit 15300 / Base 20000) → derived maint base inherits 20000 → 0.20×20000 pathway',
    evidence='<b>Scan of 19 large-base/asset PIAMBK lines reconciles to:</b>'
             '<div style="margin:6px 0"><b>A · inflated-license base</b> (Base=20000, SrcList≈355, priced high) — ' + str(len(cat['A_inflated'])) + ' lines:</div>'
             + mini(Arows, ['Quote','Line','Net','Base','SrcList'])
             + '<div style="margin:6px 0"><b>D · license-scale renewal source-asset</b> (SourceAsset.Price=4000) — ' + str(len(cat['D_renewal_asset'])) + ' lines:</div>'
             + mini(Drows, ['Quote','Line','assetPx','Net'])
             + '<p style="margin-top:8px"><b>B · bad base but Net=0</b> (never priced, SEPARATE issue) — 2 lines: <code>0Q0WC000003J3en0AC</code>, <code>0Q0WC000003FN970AG</code>. '
             '<b>C · EXCLUDED as correctly-priced</b> (mis-swept by the ≥1000 filter): <code>0Q0WC000003FZN70AO</code> Net 3666.9 = Base 3400 × 1.0785 (a correct renewal, NOT inflated). '
             'Distinct affected assetIds: <code>02iWC000008Oz2XYAS, 02iWC000008WteHYAS, 02iWC000008dbCnYAI, 02iWC000008dfGPYAY, 02iWC000008pQn5YAE</code>.</p>',
    note='DATA finding, NOT a formula bug. The formula correctly computes 0.20 × base; the base is inflated because the source '
         'license was manually over-priced (e.g. DOfV license Unit 15300 / Base 20000 vs list 355). A Force-reprice can flip a '
         'stale-clean value to the inflated one (DOfV 54.32 → 3168), which also breaks idempotency (see SCN14).'))
# SCN16
SCN.append(dict(n=16, title='D-18 exception log clean', verdict='PASS', ccy='',
    accept='zero new Exception_Log__c across the whole run.',
    quote='org-wide', line='Exception_Log__c WHERE CreatedDate=TODAY',
    expected='0 rows', actual='0 rows',
    formula='no PartnerNetPricePosthook / COLAUplift* / RenewalMaintenance* rows after any reprice',
    evidence='<p>Baseline 0 → final 0 after all provisions + reprices; checked after each reprice batch.</p>',
    note='PASS. CRITICAL OBSERVATION: the SCN10 (660.04) and SCN15/DOfV (3168) mis-prices produced NO D-18 row — they are wrong '
         'COMPUTED values, not thrown exceptions, so the D-18 net does not catch them. Recommend a value-plausibility guard on '
         'derived-maintenance nets.'))

from collections import Counter
tally = Counter(s['verdict'] for s in SCN)
ORDER = ['PASS','WARN','FAIL','BLOCKED','DATA']
VCLR = {'PASS':'pass','WARN':'warn','FAIL':'fail','BLOCKED':'blocked','DATA':'data'}

cards = ''
for s in SCN:
    ccy = f'<span class="ccy">{s["ccy"]}</span>' if s['ccy'] else ''
    cards += f'''
    <div class="scn {VCLR[s['verdict']]}" id="scn{s['n']}">
      <div class="scnhead" onclick="tog({s['n']})">
        <span class="num">#{s['n']}</span><span class="stitle">{esc(s['title'])}</span>
        <span class="badge {VCLR[s['verdict']]}">{s['verdict']}</span>
        <span class="ev">exp <b>{esc(s['expected'])}</b> · act <b>{esc(s['actual'])}</b> {ccy}</span>
        <span class="chev">▾</span>
      </div>
      <div class="body" id="body{s['n']}">
        <div class="row"><span class="lbl">Acceptance</span><span>{esc(s['accept'])}</span></div>
        <div class="row"><span class="lbl">Quote / Line</span><span><code>{esc(s['quote'])}</code> — {esc(s['line'])}</span></div>
        <div class="row"><span class="lbl">Formula</span><span class="mono">{esc(s['formula'])}</span></div>
        <div class="row"><span class="lbl">Evidence</span><span>{s['evidence']}</span></div>
        <div class="row"><span class="lbl">Notes</span><span>{s['note']}</span></div>
      </div>
    </div>'''

commands = '''<pre>— Sole-active proc:  SELECT VersionNumber,Status FROM ExpressionSetDefinitionVersion WHERE ExpressionSetDefinition.DeveloperName='Rev_Mgmt_Default_Pricing_Procedure' AND Status='Active'   → 1 row {V25, Active}
— Oracle (per line): SELECT Id,LineNumber,Product2.ProductCode,Fortra_Product_Type__c,PricebookEntry.ProductSellingModel.SellingModelType,Quantity,CurrencyIsoCode,ListPrice,UnitPrice,NetUnitPrice,NetTotalPrice,Base_Price__c,Source_List_Price__c,Prior_Partner_Discount__c,Prior_Discretionary_Discount__c,PartnerDiscountPercent,Discount,COLA_Uplift_Percent__c,COLACalculatedPrice__c,QuoteAction.Type,QuoteAction.SourceAsset.Price FROM QuoteLineItem WHERE QuoteId='&lt;QID&gt;' ORDER BY LineNumber
— Force-reprice (×2/×3): POST /services/data/v64.0/connect/rev/sales-transaction/actions/place {"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},"graph":{...PATCH Quote &lt;QID&gt;...}}
— Provision first-renewal: RenewalMaintenanceProvisionService.provision(new Set&lt;Id&gt;{'&lt;QID&gt;'});
— Add MTD QLIA: sf data create record --sobject QuoteLineItemAttribute --values "QuoteLineItemId=&lt;lid&gt; AttributeName='Maintenance Type Defn' AttributeDefinitionId=0tjWC000000096bYAA AttributeValue=&lt;tier&gt; AttributePicklistValueId=&lt;pvid&gt;"
— D-18: SELECT Source__c,Exception_Type__c,Message__c,CreatedDate FROM Exception_Log__c WHERE CreatedDate=TODAY</pre>'''

artifacts = '''<pre>QUOTES (repriced / provisioned — NOTHING deleted):
  0Q0WC000003JXMj    gold EUR new-biz (SCN1,4,7,13,14)              repriced ×3
  0Q0WC000003DKNN0A4 / DGgL0AW / DLBO0A4  §DATA born renewals (SCN8,9,10) repriced ×2
  0Q0WC000003FRPZ0A4 / FR6D0AW / DOpB0AW  fresh carryovers        PROVISIONED + repriced ×2
  0Q0WC000003FJ2D0AW  base-less (SCN5)                             repriced ×2
  0Q0WC00000382MH0AY  RRM non-regression (SCN11)                   repriced ×2
  0Q0WC000003DIAL0A4  discount-netting (SCN6)                      repriced ×2
  0Q0WC000003DOfV0AW  first SCN6 pick — flipped 54.32→3168 on reprice (SC-3346-ASSET; value CHANGED, not deleted)
  0Q0WC000003KrOD0A0  J-02 fixture (SCN2/3) MINTED; reprice BLOCKED (DerivedPricingFilter#1); left in place
BORN LINES (post-provision): 04267917 (FRPZ) · 04267918 (FR6D) · 04267919 (DOpB)
QLIA created: 0zuWC000006Q3d7YAC (Premier on J02 mntStd) · 0zuWC000006Q3ejYAC (Professional on J02 mntExp)
SC-3346-ASSET assets: 02iWC000008Oz2XYAS · 02iWC000008WteHYAS · 02iWC000008dbCnYAI · 02iWC000008dfGPYAY · 02iWC000008pQn5YAE
Snapshots + scripts + categorized data: Data/sc3346/dpp_regression_20260712/</pre>'''

tallyhtml = ''.join(f'<span class="tchip {VCLR[k]}">{k} {tally.get(k,0)}</span>' for k in ORDER)
changeline = ('2026-07-12 — CLI regression run (Claude Code): 16 scenarios · PASS 9 / WARN 2 / FAIL 1 / BLOCKED 3 / DATA 1. '
  'FAIL SCN10 = first-renewal maint with a discretionary/manual Discount does not survive Force-reprice '
  '(fresh DOpB born 3645.33 → 660.04 via Base→assetPx×0.20; stale DLBO 60.37 → 58.58 via over-eroded base); error is SILENT (no D-18). '
  'WARN SCN8 (named §DATA sample DKNN reprices 58.58 ≠ 65.09; fresh partner-only FRPZ correct 3666.9) & SCN6 (netting applied but 56.23 ≠ waterfall 54.32). '
  'DATA SCN15 = 16 PIAMBK lines inherit inflated base from override-priced contributor licenses. '
  'Guards held: SCN1/4/11/13/14 + 152 unit tests green. BLOCKED SCN2/3 (no live tier tags; fixture DerivedPricingFilter#1), SCN12 (no non-USD first-renewal maint).')

HTML = f'''<meta charset="utf-8">
<title>SC-3346 DPP Regression — FortraUAT — {META['run']}</title>
<style>
:root{{--bg:#0f1117;--card:#181b23;--line:#262b36;--tx:#e6e9ef;--mut:#98a2b3;--pass:#22c55e;--warn:#eab308;--fail:#ef4444;--blk:#94a3b8;--data:#f97316;--acc:#60a5fa}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--bg);color:var(--tx);font:14px/1.55 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif}}
.wrap{{max-width:1100px;margin:0 auto;padding:28px 20px 80px}}
h1{{font-size:22px;margin:0 0 4px}}.sub{{color:var(--mut);font-size:13px}}
.hdr{{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px 18px;margin:16px 0}}
.hdr div{{margin:4px 0}}.hdr .k{{color:var(--mut);display:inline-block;min-width:112px;vertical-align:top}}
.tally{{display:flex;gap:8px;flex-wrap:wrap;margin:14px 0}}
.tchip{{padding:6px 12px;border-radius:20px;font-weight:700;font-size:13px;color:#0b0d12}}
.tchip.pass{{background:var(--pass)}}.tchip.warn{{background:var(--warn)}}.tchip.fail{{background:var(--fail);color:#fff}}.tchip.blocked{{background:var(--blk)}}.tchip.data{{background:var(--data)}}
.scn{{background:var(--card);border:1px solid var(--line);border-left:4px solid var(--line);border-radius:10px;margin:10px 0;overflow:hidden}}
.scn.pass{{border-left-color:var(--pass)}}.scn.warn{{border-left-color:var(--warn)}}.scn.fail{{border-left-color:var(--fail)}}.scn.blocked{{border-left-color:var(--blk)}}.scn.data{{border-left-color:var(--data)}}
.scnhead{{display:flex;align-items:center;gap:12px;padding:12px 16px;cursor:pointer;user-select:none}}
.scnhead:hover{{background:#1d212b}}
.num{{color:var(--mut);font-weight:700;min-width:28px}}.stitle{{font-weight:600}}
.badge{{padding:3px 10px;border-radius:6px;font-weight:700;font-size:12px;color:#0b0d12}}
.badge.pass{{background:var(--pass)}}.badge.warn{{background:var(--warn)}}.badge.fail{{background:var(--fail);color:#fff}}.badge.blocked{{background:var(--blk)}}.badge.data{{background:var(--data)}}
.ev{{margin-left:auto;color:var(--mut);font-size:12.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:52%}}
.ev b{{color:var(--tx)}}.ccy{{background:#11141b;border:1px solid var(--line);border-radius:4px;padding:0 5px;margin-left:4px;font-size:11px}}
.chev{{color:var(--mut);transition:.2s}}
.body{{display:none;padding:6px 16px 16px;border-top:1px solid var(--line)}}.body.open{{display:block}}.scn.open .chev{{transform:rotate(180deg)}}
.row{{display:flex;gap:14px;padding:7px 0;border-bottom:1px dashed #232833;align-items:flex-start}}.row:last-child{{border-bottom:0}}
.lbl{{color:var(--mut);min-width:96px;flex:none;font-size:12px;text-transform:uppercase;letter-spacing:.03em;padding-top:2px}}
.mono{{font-family:ui-monospace,Menlo,monospace;font-size:12.5px}}
code{{background:#11141b;padding:1px 5px;border-radius:4px;font-size:12.5px;color:#cbd5e1}}
table.mini{{border-collapse:collapse;margin:4px 0;font-size:12.5px}}
table.mini th{{text-align:left;color:var(--mut);font-weight:600;padding:3px 14px 3px 0;border-bottom:1px solid var(--line)}}
table.mini td{{padding:3px 14px 3px 0;font-family:ui-monospace,Menlo,monospace}}
pre{{background:#0b0d12;border:1px solid var(--line);border-radius:8px;padding:12px;overflow-x:auto;font-size:11.5px;color:#cbd5e1;white-space:pre}}
h2{{font-size:15px;margin:26px 0 8px;color:var(--acc)}}
.callout{{background:#2a1416;border:1px solid #7f1d1d;border-radius:8px;padding:12px 14px;margin:14px 0;font-size:13px}}
.callout.data{{background:#2a1a0c;border-color:#9a4a12}}.callout.warn{{background:#2a2408;border-color:#8a6d0a}}
.foot{{color:var(--mut);font-size:12px;margin-top:30px;border-top:1px solid var(--line);padding-top:12px}}
.chg{{background:#0b0d12;border:1px solid var(--line);border-left:3px solid var(--acc);border-radius:6px;padding:10px 12px;margin:8px 0;font-size:12px;color:#cbd5e1}}
</style>
<div class="wrap">
  <h1>SC-3346 — Derived Maintenance Pricing (DPP) Regression</h1>
  <div class="sub">FortraUAT · real-data · Salesforce CLI oracle + authorized pricing writes · independently re-graded (2 blind verifiers + adversarial refuters + completeness critic)</div>
  <div class="tally">{tallyhtml}</div>
  <div class="hdr">
    <div><span class="k">Org</span>{esc(META['org'])}</div>
    <div><span class="k">Procedure</span>{esc(META['proc'])}</div>
    <div><span class="k">Run date</span>{esc(META['run'])}</div>
    <div><span class="k">Tester</span>{esc(META['tester'])}</div>
    <div><span class="k">Static guards</span>{esc(META['guards'])}</div>
    <div><span class="k">D-18 log</span>{esc(META['d18'])}</div>
  </div>

  <div class="callout">
    <b>HEADLINE FAIL — SCN10:</b> a first-renewal maintenance line carrying a <b>discretionary / manual Discount</b> does not survive a
    Force-reprice. Provision borns the correct 3-component <code>UnitPrice</code> (3645.33), but the reprice overwrites <code>NetUnitPrice</code>
    two different wrong ways: <b>(1) fresh</b> — Base collapses to <code>assetPx × 0.20 = 800</code> (the new-biz tier base) → 660.04; <b>(2) pre-existing</b> —
    over-eroded Base 54.32 × COLA → 58.58. Only the cosmetic <code>UnitPrice</code> keeps the right number. The RNM1 fix was validated on
    born <code>UnitPrice</code> only; the reprice/<code>NetUnitPrice</code> path is unguarded when a discount is present. The error is <b>silent</b> (no D-18 row).
  </div>
  <div class="callout warn">
    <b>WARN — SCN8 &amp; SCN6:</b> SCN8 — the prompt\'s <b>named §DATA real-data sample DKNN reprices to 58.58, not its documented 65.09</b>
    (over-eroded born Base 54.32); the <i>fresh</i> partner-only path (FRPZ) is correct at 3666.9, so pre-existing born renewal lines are the risk.
    SCN6 — discount netting is applied (71 → 56.23) but 56.23 does not reconcile to the 15%/10% waterfall (54.32); the reprice shifted the line off its formula-correct value.
  </div>
  <div class="callout data">
    <b>DATA — SC-3346-ASSET (SCN15):</b> 16 <code>PIA-PIA-RNM-PIAMBK</code> lines (11 inflated-base + 5 license-scale asset) inherit an
    inflated base from a manually over-priced contributor license (e.g. license PIAP list 355 → <code>Unit 15300 / Base 20000</code>), so the
    derived maint prices ~56× high. A Force-reprice can flip a stale-clean value to the inflated one (<code>0Q0WC000003DOfV0AW</code>: 54.32 → 3168),
    also breaking idempotency on those quotes. Formula is correct (0.20 × base) — flag the upstream data, do not "fix" the formula.
  </div>

  <h2>Scenarios (click any row to expand evidence)</h2>
  {cards}

  <h2>Commands / SOQL used</h2>
  {commands}
  <h2>Artifacts — every Id touched (nothing deleted)</h2>
  {artifacts}

  <h2>CHANGELOG line (append to the prompt)</h2>
  <div class="chg">{changeline}</div>

  <div class="foot">
    Generated by Claude Code (CLI); all prices in the quote\'s own currency (badge per scenario). Before &amp; after snapshots under
    <code>Data/sc3346/dpp_regression_20260712/</code>. Verdicts independently re-derived by 2 blind verifiers (full agreement) + adversarial
    refutation of the FAIL (held) &amp; the PASSes (SCN8/SCN6 downgraded to WARN) + a completeness critic (fixes applied).
    Tally: PASS {tally.get('PASS',0)} · WARN {tally.get('WARN',0)} · FAIL {tally.get('FAIL',0)} · BLOCKED {tally.get('BLOCKED',0)} · DATA {tally.get('DATA',0)}.
  </div>
</div>
<script>
function tog(n){{document.getElementById('body'+n).classList.toggle('open');document.getElementById('scn'+n).classList.toggle('open');}}
[6,8,10,15].forEach(tog);
</script>'''

out = '/Users/liamjeong/Documents/Code/Fortra/docs/sc3346_dpp_cli_report_2026-07-12.html'
open(out,'w').write(HTML)
print('WROTE', out, len(HTML), 'bytes')
print('TALLY', dict(tally))
