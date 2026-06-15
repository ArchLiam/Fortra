import React from "react";

// SC-3346 — Derived Pricing & COLA — Status & Decisions Needed (high-visibility meeting briefing)
// FortraUAT · 3rd E2E re-test · 2026-06-14 · functional pricing scope.

const KPIS = [
  { n: "15", l: "Scenarios pass", c: "#3fb950" },
  { n: "5", l: "Functional fails", c: "#ff7b72" },
  { n: "2", l: "Narrow defect areas", c: "#e3b341" },
  { n: "3", l: "Decisions to unblock", c: "#79c0ff" },
];
const WORKS = [
  "New-business maintenance pricing",
  "Renewal COLA math (67.38 exact)",
  "License & subscription renewals",
  "Order decomposition & carry-forward",
  "Partner-rate selection, null-guards",
];
const LEFT = [
  "Renewal maintenance commits the wrong / $0 price on auto-generated lines",
  "A few product tiers price at $0 (no rate defined)",
];
const REASONS = [
  { ico: "🏗️", t: "1 · Wrong layer", p: 'Maintenance is a "derived" line — the engine locks its price at creation. 5 code routes proven dead (prehook, posthook, formula, config). Can\'t be patched on reprice.', tag: "Fix = price at creation, or de-derive" },
  { ico: "🧭", t: "2 · Decisions, not code", p: "3 pricing-policy questions are pending (partner double-discount, tier rates, rate grain). Engineering can't pick these. Until ruled, every re-test shows the same gap.", tag: "Needs a business / owner ruling" },
  { ico: "🧪", t: "3 · Safety net down", p: "A code-quality test guardrail is currently broken, so fixes can regress silently. Quick to restore — but it's been masking the churn.", tag: "Fast to fix" },
];
const DECISIONS = [
  { q: "Partner discount — applied once or twice on renewal maintenance?", d: "The renewal price already includes last year's partner discount; some lines apply it again → 60.64 instead of 67.38. One quote was already accepted at the disputed number.", owner: "Owner: Business / Nir / Marc" },
  { q: "Tier rates — what % for Basic / Premium / Express / Expert?", d: 'Only 3 of 7 tiers have a rate; the rest price at $0. Need the uplift policy (and what "platinum" should be).', owner: "Owner: Product / Marc" },
  { q: "Fix approach — price at line creation, or de-derive the product?", d: "The only two routes the engine allows. This sets the build path and the timeline.", owner: "Owner: Nir / Marc (build)" },
];

const S = {
  body: { fontFamily: "-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial,sans-serif", background: "#0d1117", color: "#e6edf3", lineHeight: 1.5, padding: "40px 24px 80px", minHeight: "100vh" },
  wrap: { maxWidth: 1180, margin: "0 auto" },
  eyebrow: { fontSize: 14, letterSpacing: 2, textTransform: "uppercase", color: "#7d8590", fontWeight: 700 },
  h1: { fontSize: 42, fontWeight: 800, margin: "6px 0 8px", lineHeight: 1.1 },
  sub: { fontSize: 16, color: "#9aa4af" },
  verdict: { margin: "28px 0", padding: "24px 28px", borderRadius: 14, background: "linear-gradient(135deg,#3d2c00,#2d2206)", border: "1px solid #9a6700" },
  secH: { fontSize: 13, letterSpacing: 2, textTransform: "uppercase", color: "#7d8590", fontWeight: 800, margin: "38px 0 14px" },
  kpi: { flex: 1, minWidth: 150, background: "#161b22", border: "1px solid #30363d", borderRadius: 12, padding: 18, textAlign: "center" },
  reason: { background: "#161b22", border: "1px solid #30363d", borderLeft: "5px solid #db6d28", borderRadius: 12, padding: 22 },
  tag: { display: "inline-block", marginTop: 12, fontSize: 12, fontWeight: 700, letterSpacing: .5, padding: "3px 10px", borderRadius: 20, background: "#21262d", color: "#e3b341" },
  dec: { display: "flex", gap: 18, alignItems: "flex-start", background: "linear-gradient(135deg,#172554,#0d1b3d)", border: "1px solid #3b82f6", borderRadius: 14, padding: "20px 24px" },
  num: { flex: "0 0 auto", width: 46, height: 46, borderRadius: "50%", background: "#3b82f6", color: "#fff", fontSize: 24, fontWeight: 800, display: "flex", alignItems: "center", justifyContent: "center" },
  owner: { display: "inline-block", marginTop: 10, fontSize: 12, fontWeight: 700, letterSpacing: .5, padding: "4px 12px", borderRadius: 20, background: "#1f6feb33", color: "#79c0ff", border: "1px solid #1f6feb66" },
};

function Panel({ kind, title, items }) {
  const good = kind === "good";
  const box = { borderRadius: 14, padding: "22px 24px", border: "1px solid", background: good ? "#0e2a18" : "#2a1416", borderColor: good ? "#2ea04366" : "#cf222e66" };
  const mark = good ? "✓" : "✕", mc = good ? "#3fb950" : "#ff7b72";
  return (
    <div style={box}>
      <h3 style={{ fontSize: 18, marginBottom: 12, color: mc }}>{good ? "✅" : "❌"} {title}</h3>
      <ul style={{ listStyle: "none", margin: 0, padding: 0 }}>
        {items.map((t, i) => (
          <li key={i} style={{ fontSize: 16, padding: "5px 0 5px 26px", position: "relative" }}>
            <span style={{ position: "absolute", left: 0, color: mc, fontWeight: 800 }}>{mark}</span>{t}
          </li>
        ))}
      </ul>
    </div>
  );
}

export default function SC3346SituationBriefing() {
  return (
    <div style={S.body}><div style={S.wrap}>
      <div style={S.eyebrow}>Status &amp; Decisions Needed · 2pm ET</div>
      <h1 style={S.h1}>SC-3346 — Derived Pricing &amp; COLA</h1>
      <div style={S.sub}>FortraUAT · 3rd end-to-end re-test · 2026-06-14 · functional pricing scope</div>

      <div style={S.verdict}>
        <div style={{ fontSize: 13, letterSpacing: 2, textTransform: "uppercase", color: "#e3b341", fontWeight: 800 }}>Where it stands</div>
        <div style={{ fontSize: 26, fontWeight: 700, marginTop: 6, color: "#fff" }}>
          CONDITIONAL — the core prices correctly; the remaining defects are gated on <span style={{ color: "#e3b341" }}>3 business decisions</span>, not more code.
        </div>
      </div>

      <div style={{ display: "flex", gap: 14, flexWrap: "wrap", margin: "24px 0" }}>
        {KPIS.map((k) => (
          <div key={k.l} style={S.kpi}><div style={{ fontSize: 40, fontWeight: 800, lineHeight: 1, color: k.c }}>{k.n}</div>
            <div style={{ fontSize: 12, letterSpacing: 1, textTransform: "uppercase", color: "#7d8590", marginTop: 8, fontWeight: 600 }}>{k.l}</div></div>
        ))}
      </div>

      <div style={S.secH}>The picture</div>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 18 }}>
        <Panel kind="good" title="What works" items={WORKS} />
        <Panel kind="bad" title="What's left" items={LEFT} />
      </div>

      <div style={S.secH}>Why it keeps failing after 3 rounds — it isn't random bugs</div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(3,1fr)", gap: 18 }}>
        {REASONS.map((r) => (
          <div key={r.t} style={S.reason}>
            <div style={{ fontSize: 30 }}>{r.ico}</div>
            <div style={{ fontSize: 19, fontWeight: 800, margin: "8px 0", color: "#fff" }}>{r.t}</div>
            <p style={{ fontSize: 15, color: "#adbac7" }}>{r.p}</p>
            <span style={S.tag}>{r.tag}</span>
          </div>
        ))}
      </div>

      <div style={S.secH}>3 decisions needed today</div>
      <div style={{ display: "grid", gridTemplateColumns: "1fr", gap: 14 }}>
        {DECISIONS.map((d, i) => (
          <div key={i} style={S.dec}>
            <div style={S.num}>{i + 1}</div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 19, fontWeight: 700, color: "#fff" }}>{d.q}</div>
              <div style={{ fontSize: 15, color: "#9db2d4", marginTop: 4 }}>{d.d}</div>
              <span style={S.owner}>{d.owner}</span>
            </div>
          </div>
        ))}
      </div>

      <div style={{ marginTop: 34, padding: "22px 26px", borderRadius: 14, background: "#161b22", border: "1px solid #30363d", fontSize: 18 }}>
        With these <b style={{ color: "#3fb950" }}>3 decisions today</b>, the remaining work is bounded and I can give a real completion date.
        Without them — <span style={{ color: "#ff7b72" }}>a 4th test shows the same board.</span>
      </div>

      <div style={{ marginTop: 24, color: "#6e7681", fontSize: 13, textAlign: "center" }}>
        Workday/MuleSoft integration out of scope · managed reprice only · no record deletes/activation · Accepted quote 00781068 untouched
      </div>
    </div></div>
  );
}
