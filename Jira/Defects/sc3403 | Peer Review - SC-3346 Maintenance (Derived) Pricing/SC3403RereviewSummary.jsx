// SC3403RereviewSummary.jsx
// Self-contained executive summary of the SC-3403 peer RE-review of SC-3346
// Maintenance (Derived) Pricing. No external UI deps — inline styles only.
// Drop into any React 17+ app:  import SC3403RereviewSummary from './SC3403RereviewSummary'
// Date: 2026-06-26 · Reviewer: Liam Jeong · 61-agent read-only workflow vs FortraUAT

import React from "react";

const C = {
  bg: "#0b0e14", panel: "#141925", panel2: "#1b2230", line: "#283142",
  ink: "#e6edf6", mut: "#93a1b5", dim: "#6b7a90",
  pass: "#2ea043", passBg: "#0f2a17", passBr: "#1f5c30",
  fail: "#e5484d", failBg: "#2c1416", failBr: "#6e2327",
  part: "#e3a008", partBg: "#2c2410", partBr: "#6b5414",
  oos: "#6b7a90", oosBg: "#1a2030", oosBr: "#33415a",
  accent: "#4c8dff", accent2: "#9a7cff",
};

const VERDICT_STYLE = {
  PASS: { bg: C.passBg, br: C.passBr, fg: "#5fd37a" },
  FAIL: { bg: C.failBg, br: C.failBr, fg: "#ff7b7f" },
  PARTIAL: { bg: C.partBg, br: C.partBr, fg: "#f3c24b" },
  "OUT-OF-SCOPE": { bg: C.oosBg, br: C.oosBr, fg: "#9fb0c6" },
};

const KPIS = [
  { n: "13 / 15", l: "Acceptance criteria PASS", s: "AC12 + AC13 fail", c: C.pass },
  { n: "302 / 302", l: "Maintenance tests green", s: "COLAUpliftTest drift gone", c: C.accent },
  { n: "59.5%", l: "PartnerNetPricePosthook cov.", s: "< 75% gate · Q2OMapper 65.2%", c: C.fail },
  { n: "3 / 11", l: "SC-3346 classes in PROD", s: "from-zero cutover", c: C.fail },
];

const CHANGES = [
  { warn: false, t: "SC-3404 root cause structurally fixed in V16.", d: "Native DerivedProductsRenewals is now scoped out of renewal lines by the DerivedProductsNonRenewal filter; List Container 2 (COLACalculatedPrice__c → NetUnitPrice) is the last writer. Done as list-scope — not the risky resultIncluded flip that threatened ~536K lines." },
  { warn: false, t: "NB-DERIVED-TIER resolved.", d: "V16 DerivedPricingFormula encodes all 7 tiers matching Maintenance_Rate__mdt (was 3-of-7 in V14)." },
  { warn: false, t: "M-2 dead competing formula gone from the active proc.", d: "0 Source_List_Price__c / platinum refs; one formula reading the stamped Base_Price__c." },
  { warn: false, t: "B-3 fixed · SC-3410/3412 born-zero fix live · COLAUpliftTest drift gone.", d: "Partner map-miss falls through; 21 BoKS lines 355→71; suite compiles." },
  { warn: true, t: "RenewalMaintenanceFlip was de-wired on the 2026-06-24 republish.", d: "Fortra_Create_Renewal_Quote V7 called it; active V8 dropped that node (SC-3371 lost-fix pattern). Renewal now commits via RenewalMaintenancePricingService; Flip dead-wired but still in the org." },
];

const ACS = [
  ["AC1", "Base = source pre-discount UnitPrice × tier", "PASS", "21 live BoKS lines 355→71 (0.20)"],
  ["AC2", "Base discount-immune", "PASS", "3 layers key on pre-discount source fields"],
  ["AC3", "Base tracks attribute change ($325→$468)", "PASS", "source attribute-priced before LC9"],
  ["AC4", "Discounts apply after base (200→140)", "PASS", "LC9 (seq 17) then discount group (seq 21)"],
  ["AC5", "Stable across 3 reprices (no shrinkage)", "PASS", "multiplies stamped base, not own NetUnitPrice"],
  ["AC6", "Tier change Standard→Premier 0.20→0.30", "PASS", "both APVs present; data-driven"],
  ["AC7", "Selling-model backfill prices, not $0/error", "PASS", "BoKS chain aligned; both maint PBEs have PBEDP"],
  ["AC8", "Renewal 3-component carry-forward × (1+COLA)", "PASS", "67.38 = 62.48×1.0785 · overturned PARTIAL"],
  ["AC9", "Renewal overrides native pull", "PASS", "native pull filtered out; LC2 last writer"],
  ["AC10", "COLA + components from Flow; no double-discount", "PASS", "Apex guard nulls COLA-owned lines"],
  ["AC11", "Branch partition by QuoteTypeText__c", "PASS", "every shared step gated on 'Renewal'"],
  ["AC12", "No Apex prehook; one Flow only · minor", "FAIL", "2 stamp flows + prehook+posthook write net (doc)"],
  ["AC13", "Fallback / straggler tiers · major latent", "FAIL", "GS-GSE-RRM-EFSMB → off-list 'platinum' → $0"],
  ["AC14", "Source 'Unit Volume' attribute wired/removed", "PASS", "wired & functional · overturned PARTIAL"],
  ["AC15", "Decision tables refreshed", "PASS", "all V16 tables refreshed 06-25 · overturned PARTIAL"],
];

const FINDINGS = [
  ["B-3", "PASS", "partner map-miss falls through (class 06-21)"],
  ["B-4", "PASS", "renewal null-guard + carry-forward QLI→OI"],
  ["B-5", "OUT-OF-SCOPE", "AssetActionSource table Failed but not in V16 maint path · overturned FAIL"],
  ["B-6", "PASS", "all 6,162 live New-Maint OIs stamp maintenance base · overturned PARTIAL"],
  ["M-1", "FAIL", "4 Apex automations touch maint pricing — reconcile SDD (minor)"],
  ["M-2", "PASS", "dead formula gone from V16 · overturned PARTIAL"],
  ["M-3", "FAIL", "PROD lacks SalesTransactionContextExt_v2 (prod)"],
  ["M-4", "PASS", "Source_List_Price__c Q2O mapping live; 8/8 OIs match"],
  ["M-5", "PARTIAL", "197/1889 derived maint PBEs covered (~89.6% uncovered); BoKS fine (major)"],
  ["M-6", "OUT-OF-SCOPE", "prod prehook stale (39,956 vs 47,235 chars)"],
  ["M-7", "FAIL", "Posthook 59.5% + Q2OMapper 65.2% < 75% · overturned PARTIAL (blocker)"],
  ["SC-3404", "PARTIAL", "fixed but UNPROVEN E2E — lines predate V16, 5/6 still 60.64/0 (major)"],
  ["NB-DERIVED-TIER", "PASS", "all 7 tiers in V16"],
  ["FLIP-WIRING", "FAIL", "Flip dropped from active flow V8; dead class in org (hygiene)"],
];

const BLOCKERS = [
  { h: "B-2 · Packaging — from-zero, non-deployable bundle", d: "PROD has 3 of 11 classes (stale 06-11), 0 SC-3346 triggers, no SalesTransactionContextExt_v2, Maintenance_Rate__mdt = 0 rows, proc V1 vs V16, 23 QLI + 32 OI fields absent. force-app holds none of the build classes, a stale Q2O mapper, a V1–V3 proc XML, and a deploy-blocking rca_diagnostic.cls-meta.xml orphan." },
  { h: "M-7 · Coverage gate", d: "PartnerNetPricePosthook 59.5% (765/1286) and QuoteToOrderFieldMapper 65.2% (73/112) below 75%. The 521 uncovered posthook lines are the newly-absorbed regional / SC-3441 paths on the class that writes the production net." },
  { h: "SC-3404 · Verification gap", d: "The fix is structurally real but every instrumented BoKS renewal-maintenance line predates V16 and 5 of 6 still show 60.64 / 0. Needs one live V16 renewal reprice committing 67.38 before it can close." },
];

const OPEN = [
  ["AC13 platinum straggler", "GS-GSE-RRM-EFSMB defaults to off-list 'platinum' → silent $0; decide fallback, re-tag / retire 3 APVs."],
  ["FLIP de-wiring", "confirm RenewalMaintenanceFlip retired for RenewalMaintenancePricingService; remove dead class + usage header."],
  ["Year-2 PCR 14OWC0000022Eyb2AE", "Active — confirm the design pivoted to the AutoAdd-PCR model (old Flip-deactivates-PCR step is void)."],
  ["Single source of truth", "3-component renewal COLA math triplicated across prehook / posthook / RMPS and beginning to diverge; consolidate."],
  ["Interactive vs migration reprice", "Apex backstop wired only into Fortra_Quote_Reprice; confirm interactive reprice commits 67.38 via LC2 alone."],
  ["M-5 PBEDP backfill (~1,692 rows)", "staged but not applied; broad non-BoKS rollout gated on Marc crosswalk + DML auth."],
];

const TICKET_COMMENT = `Nir — SC-3403 re-review (read-only, FortraUAT 2026-06-26). CONDITIONAL-GO. BoKS maintenance logic is correct in UAT and reproduced live (Base 355→Net 71; Premier→106.50; proc V16 now encodes all 7 tiers; SC-3404 native-pull override structurally fixed; B-3/B-4/B-6/M-2/M-4 closed; 302/302 maintenance tests green). Not production-deployable: (1) from-zero packaging — PROD missing 8/11 classes, all triggers, _v2 context, V16 proc, 7 rate rows, 55 fields; force-app holds none of it + the rca_diagnostic orphan; (2) PartnerNetPricePosthook 59.5% / QuoteToOrderFieldMapper 65.2% below the 75% gate; (3) SC-3404 needs one live V16 renewal commit of 67.38 captured E2E. Two hygiene items: RenewalMaintenanceFlip got dropped from Fortra_Create_Renewal_Quote V8 (confirm retired for RenewalMaintenancePricingService); and GS-GSE-RRM-EFSMB still defaults to off-list 'platinum' → $0 (open half of AC13). Happy to pair on the deploy manifest.`;

const Pill = ({ v }) => {
  const s = VERDICT_STYLE[v] || VERDICT_STYLE.PASS;
  return (
    <span style={{ display: "inline-block", fontSize: 10.5, fontWeight: 800, letterSpacing: ".04em",
      padding: "3px 9px", borderRadius: 999, whiteSpace: "nowrap",
      background: s.bg, color: s.fg, border: `1px solid ${s.br}` }}>{v}</span>
  );
};

const Section = ({ title, sub, barColor = C.accent, children }) => (
  <section style={{ margin: "30px 0" }}>
    <h2 style={{ fontSize: 17, fontWeight: 700, margin: "0 0 4px", display: "flex", alignItems: "center", gap: 9 }}>
      <span style={{ width: 3, height: 17, borderRadius: 2, background: barColor }} />{title}
    </h2>
    {sub && <p style={{ color: C.dim, fontSize: 12.5, margin: "0 0 14px 12px" }}>{sub}</p>}
    {children}
  </section>
);

const th = { textAlign: "left", fontSize: 11, letterSpacing: ".06em", textTransform: "uppercase",
  color: C.dim, padding: "10px 13px", background: C.panel2, borderBottom: `1px solid ${C.line}` };
const td = { padding: "10px 13px", borderBottom: `1px solid ${C.line}`, verticalAlign: "top", color: C.mut };
const tableStyle = { width: "100%", borderCollapse: "separate", borderSpacing: 0, fontSize: 13,
  background: C.panel, border: `1px solid ${C.line}`, borderRadius: 12, overflow: "hidden" };

export default function SC3403RereviewSummary() {
  return (
    <div style={{ background: `radial-gradient(1200px 600px at 70% -10%, #16203a 0%, ${C.bg} 55%)`,
      color: C.ink, font: '15px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,sans-serif',
      padding: "32px 18px 80px", minHeight: "100vh" }}>
      <div style={{ maxWidth: 1080, margin: "0 auto" }}>

        {/* Header */}
        <div style={{ letterSpacing: ".18em", textTransform: "uppercase", fontSize: 11, color: C.dim, fontWeight: 700 }}>
          Peer Review · SC-3403 · Revenue Cloud Advanced / RLM · FortraUAT
        </div>
        <h1 style={{ fontSize: 30, margin: "6px 0 4px", lineHeight: 1.15, fontWeight: 800 }}>
          SC-3346 — Maintenance (Derived) Pricing
        </h1>
        <div style={{ color: C.mut, fontSize: 14 }}>
          Production-readiness <b>re-review</b> · 61-agent read-only workflow vs live FortraUAT · 2026-06-26
        </div>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 8, marginTop: 14 }}>
          {[["Build", "SC-3346"], ["Peer review", "SC-3403"], ["Owner", "Nir Kailash"],
            ["Reviewer", "Liam Jeong"], ["Active proc", "V16"], ["Priority", "Blocker"],
            ["Method", "read-only · no org changes"]].map(([k, v]) => (
            <span key={k} style={{ background: C.panel2, border: `1px solid ${C.line}`, borderRadius: 999,
              padding: "4px 11px", fontSize: 12, color: C.mut }}>{k} <b style={{ color: C.ink }}>{v}</b></span>
          ))}
        </div>

        {/* Verdict hero */}
        <div style={{ margin: "22px 0", borderRadius: 18, padding: "22px 24px", border: `1px solid ${C.partBr}`,
          background: `linear-gradient(135deg, ${C.partBg}, #161b27 70%)`, position: "relative", overflow: "hidden" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 16, flexWrap: "wrap" }}>
            <div style={{ fontSize: 13, fontWeight: 800, letterSpacing: ".08em", padding: "9px 16px", borderRadius: 10,
              background: C.part, color: "#1a1300", border: "1px solid #f4c244", whiteSpace: "nowrap" }}>🟡 CONDITIONAL-GO</div>
            <div style={{ fontSize: 18, fontWeight: 700, lineHeight: 1.35, flex: 1, minWidth: 260 }}>
              UAT BoKS maintenance pricing logic is correct and demonstrably works — production deployment is a hard NO-GO.
            </div>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12, marginTop: 18 }}>
            <div style={{ borderRadius: 12, padding: "13px 15px", border: `1px solid ${C.passBr}`,
              background: `linear-gradient(180deg, ${C.passBg}, rgba(20,25,37,.6))` }}>
              <div style={{ fontSize: 11, letterSpacing: ".12em", textTransform: "uppercase", color: C.dim, fontWeight: 700, marginBottom: 6 }}>✅ Works in UAT (BoKS sanctioned scope)</div>
              <div style={{ fontSize: 13.5 }}>New-business reproduced live: <b>Base $355 → Net $71</b> (×0.20), Premier → <b>$106.50</b>. V16 encodes all <b>7 tiers</b>; SC-3404 native-pull override fixed; <b>302/302</b> tests green.</div>
            </div>
            <div style={{ borderRadius: 12, padding: "13px 15px", border: `1px solid ${C.failBr}`,
              background: `linear-gradient(180deg, ${C.failBg}, rgba(20,25,37,.6))` }}>
              <div style={{ fontSize: 11, letterSpacing: ".12em", textTransform: "uppercase", color: C.dim, fontWeight: 700, marginBottom: 6 }}>🔴 Not production-deployable</div>
              <div style={{ fontSize: 13.5 }}>From-zero packaging (PROD has <b>3 of 11</b> classes, proc <b>V1 vs V16</b>); two classes <b>&lt;75%</b> coverage; the renewal commit is <b>unproven E2E</b> on V16.</div>
            </div>
          </div>
        </div>

        {/* KPIs */}
        <div style={{ display: "grid", gridTemplateColumns: "repeat(4,1fr)", gap: 12, margin: "22px 0" }}>
          {KPIS.map((k) => (
            <div key={k.l} style={{ background: C.panel, border: `1px solid ${C.line}`, borderRadius: 14, padding: "14px 15px" }}>
              <div style={{ fontSize: 26, fontWeight: 800, letterSpacing: "-.02em", color: k.c }}>{k.n}</div>
              <div style={{ fontSize: 11.5, color: C.mut, marginTop: 3 }}>{k.l}</div>
              <div style={{ fontSize: 11, color: C.dim, marginTop: 2 }}>{k.s}</div>
            </div>
          ))}
        </div>

        {/* What changed */}
        <Section title="What changed since the last review (06-11 / 06-13)">
          <div style={{ display: "grid", gap: 9 }}>
            {CHANGES.map((c, i) => (
              <div key={i} style={{ display: "flex", gap: 11, alignItems: "flex-start", background: C.panel,
                border: `1px solid ${C.line}`, borderLeft: `3px solid ${c.warn ? C.part : C.pass}`, borderRadius: 10, padding: "11px 14px" }}>
                <div style={{ fontSize: 15 }}>{c.warn ? "🟠" : "🟢"}</div>
                <div style={{ fontSize: 13.5 }}><b>{c.t}</b> {c.d}</div>
              </div>
            ))}
          </div>
        </Section>

        {/* Acceptance criteria */}
        <Section title="Acceptance criteria" sub="13 PASS · 2 FAIL">
          <table style={tableStyle}><thead><tr>
            <th style={{ ...th, width: 64 }}>AC</th><th style={th}>Criterion</th>
            <th style={{ ...th, width: 120 }}>Verdict</th><th style={th}>Evidence</th>
          </tr></thead><tbody>
            {ACS.map(([id, crit, v, ev]) => (
              <tr key={id}>
                <td style={{ ...td, color: C.ink, fontWeight: 700, fontFamily: "ui-monospace,Menlo,monospace", fontSize: 12, whiteSpace: "nowrap" }}>{id}</td>
                <td style={{ ...td, color: C.ink }}>{crit}</td>
                <td style={td}><Pill v={v} /></td>
                <td style={td}>{ev}</td>
              </tr>
            ))}
          </tbody></table>
        </Section>

        {/* Prior findings */}
        <Section title="Prior findings reconciled to today" sub="7 PASS · 2 PARTIAL · 3 FAIL · 2 OUT-OF-SCOPE" barColor={C.accent2}>
          <table style={tableStyle}><thead><tr>
            <th style={{ ...th, width: 130 }}>Finding</th><th style={{ ...th, width: 130 }}>Verdict</th><th style={th}>Note</th>
          </tr></thead><tbody>
            {FINDINGS.map(([id, v, note]) => (
              <tr key={id}>
                <td style={{ ...td, color: C.ink, fontWeight: 700, fontFamily: "ui-monospace,Menlo,monospace", fontSize: 12, whiteSpace: "nowrap" }}>{id}</td>
                <td style={td}><Pill v={v} /></td>
                <td style={td}>{note}</td>
              </tr>
            ))}
          </tbody></table>
        </Section>

        {/* Blockers */}
        <Section title="Production blockers" sub="each independently prevents a prod deploy" barColor={C.fail}>
          <div style={{ display: "grid", gap: 11 }}>
            {BLOCKERS.map((b, i) => (
              <div key={i} style={{ background: `linear-gradient(180deg, ${C.failBg}, ${C.panel})`,
                border: `1px solid ${C.failBr}`, borderRadius: 12, padding: "14px 16px" }}>
                <div style={{ fontWeight: 700, color: "#ff8d90", fontSize: 14, marginBottom: 4 }}>🔴 {b.h}</div>
                <div style={{ fontSize: 13, color: C.mut }}>{b.d}</div>
              </div>
            ))}
          </div>
        </Section>

        {/* Open items */}
        <Section title="Open items & follow-ups" barColor={C.part}>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 9 }}>
            {OPEN.map(([t, d], i) => (
              <div key={i} style={{ background: C.panel, border: `1px solid ${C.line}`, borderRadius: 10, padding: "10px 13px", fontSize: 12.5, color: C.mut }}>
                <b style={{ color: C.ink }}>{t}</b> — {d}
              </div>
            ))}
          </div>
        </Section>

        {/* Ticket comment */}
        <Section title="Ready-to-post ticket comment" barColor={C.accent}>
          <div style={{ background: C.panel, border: `1px solid ${C.line}`, borderRadius: 12, overflow: "hidden" }}>
            <div style={{ display: "flex", alignItems: "center", gap: 9, padding: "11px 15px", background: C.panel2,
              borderBottom: `1px solid ${C.line}`, fontSize: 12.5, color: C.mut }}>
              <span style={{ width: 22, height: 22, borderRadius: "50%", background: `linear-gradient(135deg, ${C.accent}, ${C.accent2})`,
                display: "grid", placeItems: "center", fontSize: 11, fontWeight: 800, color: "#fff" }}>LJ</span>
              Liam Jeong → Nir Kailash · SC-3403
            </div>
            <div style={{ padding: "15px 17px", fontSize: 13, color: "#cdd9ea", lineHeight: 1.6, whiteSpace: "pre-wrap" }}>{TICKET_COMMENT}</div>
          </div>
        </Section>

        {/* Legend + footer */}
        <div style={{ display: "flex", gap: 14, flexWrap: "wrap", margin: "6px 0 0", fontSize: 11.5, color: C.dim }}>
          {[["PASS", C.pass], ["PARTIAL", C.part], ["FAIL", C.fail], ["OUT-OF-SCOPE", C.oos]].map(([k, c]) => (
            <span key={k} style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
              <span style={{ width: 9, height: 9, borderRadius: "50%", background: c, display: "inline-block" }} />{k}
            </span>
          ))}
        </div>
        <div style={{ marginTop: 34, paddingTop: 16, borderTop: `1px solid ${C.line}`, color: C.dim, fontSize: 11.5, textAlign: "center" }}>
          61-agent read-only workflow · 47 verdicts adversarially verified (10 overturned) · Active proc Rev_Mgmt_Default_Pricing V16 · No org changes · Evidence: Data/sc3403/retrieve/V16.xml
        </div>

      </div>
    </div>
  );
}
