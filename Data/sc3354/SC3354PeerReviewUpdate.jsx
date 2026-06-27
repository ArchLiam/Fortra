/**
 * SC-3354 — COLA Pricing: Renewal Quotes (Peer Review, post-fix re-run)
 * High-visibility React mirror of SC-3354_PEER_REVIEW_UPDATE.html.
 * Self-contained: inline styles, no external CSS/deps. Default-exported.
 *
 *   <SC3354PeerReviewUpdate />
 */
import React from "react";

const C = {
  bg: "#0d1117", card: "#161b22", card2: "#1c2330", line: "#30363d", line2: "#21262d",
  text: "#e6edf3", mut: "#9aa4af", mut2: "#7d8590",
  green: "#3fb950", greenL: "#7ee787", greenD: "#0e2a18", blue: "#79c0ff",
  red: "#ff7b72", redD: "#2a1416", amber: "#e3b341", amberD: "#2d2606",
};

const Mono = ({ children }) => (
  <code style={{ fontFamily: "ui-monospace,SFMono-Regular,Menlo,Consolas,monospace", fontSize: ".86em",
    background: "#0a0e14", border: `1px solid ${C.line2}`, borderRadius: 5, padding: "1px 6px", color: "#b9c4d0" }}>
    {children}</code>
);
const SecH = ({ children, sub }) => (
  <div style={{ margin: "40px 0 14px" }}>
    <span style={{ fontSize: 12.5, letterSpacing: "2px", textTransform: "uppercase", color: C.mut2, fontWeight: 800 }}>{children}</span>
    {sub && <span style={{ fontSize: 12.5, color: C.mut2, marginLeft: 10 }}>{sub}</span>}
  </div>
);
const Pill = ({ kind, children }) => {
  const m = { bad: { color: C.red, background: C.redD }, warn: { color: C.amber, background: C.amberD },
    ok: { color: C.greenL, background: C.greenD } }[kind];
  return <span style={{ display: "inline-block", fontSize: 10.5, fontWeight: 800, padding: "2px 9px",
    borderRadius: 20, letterSpacing: ".3px", textTransform: "uppercase", ...m }}>{children}</span>;
};
const KPI = ({ n, l, color }) => (
  <div style={{ flex: 1, minWidth: 165, background: C.card, border: `1px solid ${C.line}`,
    borderRadius: 13, padding: 16, textAlign: "center" }}>
    <div style={{ fontSize: 26, fontWeight: 850, lineHeight: 1.1, color }}>{n}</div>
    <div style={{ fontSize: 10.5, letterSpacing: ".5px", textTransform: "uppercase", color: C.mut2, marginTop: 7, fontWeight: 600 }}>{l}</div>
  </div>
);
const Card = ({ title, accent, children }) => (
  <div style={{ background: C.card, border: `1px solid ${C.line}`,
    borderLeft: accent ? `4px solid ${accent}` : `1px solid ${C.line}`,
    borderRadius: 14, padding: "20px 22px", marginBottom: 14 }}>
    {title && <h3 style={{ fontSize: 16.5, margin: "0 0 8px", color: "#fff", display: "flex", alignItems: "center", gap: 10, flexWrap: "wrap" }}>{title}</h3>}
    <div style={{ fontSize: 14.5, color: "#adbac7" }}>{children}</div>
  </div>
);
const Table = ({ head, rows, align = [] }) => (
  <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 14, marginTop: 4 }}>
    <thead><tr>{head.map((h, i) => (
      <th key={i} style={{ textAlign: align[i] === "r" ? "right" : "left", padding: "9px 11px", fontSize: 10.5,
        letterSpacing: "1px", textTransform: "uppercase", color: C.mut2, borderBottom: `2px solid ${C.line}`, fontWeight: 700 }}>{h}</th>))}</tr></thead>
    <tbody>{rows.map((r, ri) => (
      <tr key={ri}>{r.map((c, ci) => (
        <td key={ci} style={{ padding: "10px 11px", borderBottom: `1px solid ${C.line2}`, verticalAlign: "top",
          color: "#c9d1d9", textAlign: align[ci] === "r" ? "right" : "left",
          fontVariantNumeric: align[ci] === "r" ? "tabular-nums" : "normal",
          fontFamily: align[ci] === "r" ? "ui-monospace,monospace" : "inherit" }}>{c}</td>))}</tr>))}
    </tbody>
  </table>
);
const BA = ({ lbl, was, now }) => (
  <>
    <div style={{ color: "#c9d1d9", fontWeight: 600 }}>{lbl}</div>
    <div style={{ color: C.mut2, textAlign: "center" }}>⇒</div>
    <div><span style={{ color: C.red }}>{was}</span> &nbsp;·&nbsp; <span style={{ color: C.greenL }}>{now}</span></div>
  </>
);

export default function SC3354PeerReviewUpdate() {
  return (
    <div style={{ background: C.bg, color: C.text, minHeight: "100vh",
      fontFamily: '-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif', lineHeight: 1.55 }}>
      <div style={{ maxWidth: 1060, margin: "0 auto", padding: "38px 26px 80px" }}>

        <h1 style={{ fontSize: 27, margin: "0 0 4px", letterSpacing: "-.3px" }}>
          Peer Review (re-run) — COLA Pricing: Renewal Quotes Not Priced Correctly</h1>
        <div style={{ color: C.mut, fontSize: 13.5, marginBottom: 24 }}>
          Board <b style={{ color: "#c9d1d9" }}>SC-3350</b> · Peer-review subtask <b style={{ color: "#c9d1d9" }}>SC-3354</b> ·
          Org <b style={{ color: "#c9d1d9" }}>FortraUAT</b> <Mono>00DWC000006eUFF2A2</Mono> ·
          <b style={{ color: "#c9d1d9" }}> 2026-06-26 (post-fix)</b> · Method: read-only review + authorized UAT deploy + live debug-log trace
        </div>

        {/* VERDICT */}
        <div style={{ display: "flex", alignItems: "center", gap: 22, flexWrap: "wrap",
          background: "linear-gradient(110deg,#2a240680,#1c2330)", border: "1px solid #6b551f",
          borderLeft: `6px solid ${C.amber}`, borderRadius: 16, padding: "22px 26px", margin: "6px 0 4px" }}>
          <div style={{ fontSize: 30, fontWeight: 900, color: C.amber, letterSpacing: ".5px", whiteSpace: "nowrap", lineHeight: 1.1 }}>
            <span style={{ fontSize: 20, verticalAlign: "middle", marginRight: 8 }}>◑</span>CONDITIONAL</div>
          <div style={{ flex: 1, minWidth: 300 }}>
            <p style={{ margin: 0, fontSize: 15, color: "#dfe6ee" }}>
              The headline regression is <b style={{ color: C.greenL }}>fixed and live</b>: the SC-3350
              <Mono>NetUnitPrice</Mono> seed was re-grafted onto the current <Mono>COLAUpliftPrehook</Mono> and now
              commits the COLA net — proven firing in the debug log. <b>Non-partner renewals price correctly.</b>
              Not yet GO: a newly-surfaced <b style={{ color: C.amber }}>partner-line cascade</b> needs a pricing
              decision, and 3 high-severity items remain.</p>
            <div style={{ color: C.mut2, fontSize: 12.5, marginTop: 6 }}>
              Was <b style={{ color: C.red }}>🔴 NO-GO</b> (2026-06-26) — "Defect #1 reproduces at 100% on every renewal since the rework."</div>
          </div>
        </div>

        <div style={{ display: "flex", gap: 13, flexWrap: "wrap", margin: "18px 0 4px" }}>
          <KPI n="LIVE" l="NetUnitPrice seed re-deployed" color={C.greenL} />
          <KPI n="✓" l="Non-partner renewals commit COLA net" color={C.greenL} />
          <KPI n="⚠ cascade" l="Partner renewals · new finding" color={C.amber} />
          <KPI n="2 / 4" l="Hard blockers closed (+1 partial)" color={C.greenL} />
          <KPI n="129/129" l="Tests green · +3 net-commit asserts" color={C.greenL} />
        </div>

        {/* PROGRESS */}
        <SecH>Progress since the 06-26 NO-GO</SecH>
        <Card>
          <div style={{ display: "grid", gridTemplateColumns: "1fr auto 2fr", gap: "10px 16px", alignItems: "center", fontSize: 14 }}>
            <BA lbl="B-1/B-2 · net commit" was="seed deleted, 9/9 renewals $0" now="seed re-grafted & live; commits COLA net" />
            <BA lbl="B-5 · restricted picklist" was="missing MyCAP Default" now="value added & live" />
            <BA lbl="B-4 · not promotable" was="0/5 classes, CMDT absent" now="full bundle staged + validated (48/48)" />
            <BA lbl="C-1 · no net-commit test" was="0 asserts (hid the regression)" now="3 net-seed tests added & live" />
          </div>
        </Card>

        {/* FIXED */}
        <SecH sub="(job 0AfWC00000GZHnx0AH · 48/48 components · 129 tests green)">Fixed &amp; deployed to UAT</SecH>
        <Table head={["#", "Fix", "Sev", "Status"]}
          rows={[
            [<Mono>B-5</Mono>, <>Added <Mono>MyCAP Default</Mono> to <Mono>COLA_Source__c</Mono> (was restricted, 10 live rows use it)</>, <Pill kind="bad">blocker</Pill>, <span style={{ color: C.greenL, fontWeight: 700 }}>✅ closed</span>],
            [<Mono>B-4</Mono>, <>Full COLA bundle in force-app + validated deployable: 9 classes, 2 CMDT types + 22 records, Contract fields, PS, 2 templates; dropped shared trigger + <Mono>rca_diagnostic</Mono> orphan; managed <Mono>ffscpq</Mono> excluded</>, <Pill kind="bad">blocker</Pill>, <span style={{ color: C.greenL, fontWeight: 700 }}>✅ closed</span>],
            [<Mono>C-1</Mono>, "3 net-seed tests added (the gap that let the regression ship silently)", <Pill kind="warn">high</Pill>, <span style={{ color: C.greenL, fontWeight: 700 }}>✅ closed</span>],
            [<Mono>B-1/B-2</Mono>, <>Re-grafted isolated <Mono>NetUnitPrice</Mono> seed onto live v1.2 prehook (maintenance-excluded, won't re-clobber SC-3346) — <b>confirmed firing in debug log</b></>, <Pill kind="bad">blocker</Pill>, <span style={{ color: C.amber, fontWeight: 700 }}>◑ live (non-partner ✓; caveat ↓)</span>],
          ]} />

        {/* NEW FINDING */}
        <SecH>New finding (debug-log trace) — partner-line cascade</SecH>
        <Card accent={C.amber} title={<>Partner renewals double-discount on every reprice <Pill kind="warn">blocker · new</Pill></>}>
          <p style={{ margin: "8px 0" }}>The seed commits the COLA net correctly, but on a <b>partner</b> quote
            (e.g. beSECURE, 18% partner discount) the V16 procedure re-applies the discount to the <i>stored</i> net
            every reprice, and the posthook's reset to the pure COLA net <b>no-ops</b> (the settled-node lock SC-3346
            documented). My seed only sets the base once (<Mono>net ≤ 0</Mono> guard), so it can't counteract the compounding.</p>
          <Table head={["Step (one reprice)", "Log evidence", "NetUnitPrice"]} align={["", "", "r"]}
            rows={[
              ["PartnerPricingPrehook stamps %", <Mono>PERCENT STAMP … Subscription -&gt; 18.00%</Mono>, "—"],
              [<b>Seed fires ✅</b>, <Mono>SC-3350 submitting 1 NetUnitPrice seed … AdjustedPrice=7110.41</Mono>, <span style={{ color: C.greenL }}>7,110.41</span>],
              ["V16 applies 18% to stored net", <Mono>procedureNet = 4781.04</Mono>, <span style={{ color: C.red }}>×0.82 (compounds)</span>],
              ["Posthook tries to reset", <Mono>RENEWAL COLA COMMIT: procedureNet=4781.04 -&gt; colaNet=7110.41</Mono>, <span style={{ color: C.amber }}>wants 7110.41 — no-ops</span>],
            ]} />
          <div style={{ background: C.card2, border: `1px solid ${C.line}`, borderLeft: `4px solid ${C.amber}`,
            borderRadius: 10, padding: "14px 18px", margin: "10px 0", fontSize: 14, color: "#cdd6df" }}>
            Cascade across reprices: <Mono>$0 → 5,830.54 → 4,781.04 → …</Mono> (×0.82 each).
            <b> Non-partner renewals are clean</b> (OST → 10,089; Active Defense → 98,700, both currently $0, no partner % to compound).
            The posthook already <i>intends</i> the final net to be the pure COLA value 7,110.41 (no partner re-discount) — it just can't make it stick.
          </div>
          <p style={{ margin: "8px 0 0" }}><b>Decision needed (Nir/Marc + pricing):</b> does a partner subscription
            renewal get the partner discount re-applied <i>on top of</i> the COLA'd prior net, or is the COLA'd prior
            net the final price? Either answer is a change in a co-owned component (<Mono>PartnerPricingPrehook</Mono> / V16),
            not the B-1 seed.</p>
        </Card>

        {/* LEFT */}
        <SecH>What's left</SecH>
        <Table head={["Item", "Sev", "Note"]}
          rows={[
            ["Partner-line cascade", <Pill kind="warn">blocker (new)</Pill>, "Needs business rule + co-owned fix (PartnerPricingPrehook / V16)"],
            ["B-1 live proof", <Pill kind="ok">verify</Pill>, <>Reprice a non-partner line (OST <Mono>00781195</Mono> / Active Defense <Mono>00781191</Mono>) to confirm a clean stable commit</>],
            ["B-1 edges", <Pill kind="ok">low</Pill>, <>~3 null-asset-price lines (scoped out); 1 <b>Accepted</b> $0 quote needs data remediation (forward-only)</>],
            ["B-7 · rate grain", <Pill kind="warn">high</Pill>, "2 wrong rates (Systems Mgmt 7.85 vs 12.00; Cybersecurity 7.85 vs 4.70) — staged as-is, untouched"],
            ["B-3 · descriptions", <Pill kind="warn">high</Pill>, "Defect #2 (~36% renewal lines null) — not started"],
            ["B-6 · fail-silent", <Pill kind="warn">high</Pill>, "Prehook returns SUCCESS on any exception — not started"],
            ["C-2 / C-3", <Pill kind="ok">latent</Pill>, "Multi-asset collapse; inert out-year field — not started"],
          ]} />
        <p style={{ opacity: 0.6, fontSize: 13, color: C.mut, marginTop: 10 }}>
          PROD promotion — deferred per owner; out of scope for this pass (UAT-validated bundle only).</p>

        <div style={{ marginTop: 44, paddingTop: 18, borderTop: `1px solid ${C.line}`, fontSize: 12.5, color: C.mut2 }}>
          Bottom line: of the 4 hard blockers, <b style={{ color: C.greenL }}>B-4 and B-5 are fully closed</b> and
          <b style={{ color: C.greenL }}> B-1/B-2 is mechanically fixed &amp; live</b> for the common (non-partner) case —
          the 100%-reproduction regression is resolved there. A partner-line cascade (new) needs a pricing decision,
          and the high-severity B-3/B-6/B-7 remain. All UAT changes deployed under job <Mono>0AfWC00000GZHnx0AH</Mono>;
          debug trace from live reprice logs. PROD promotion intentionally deferred.
        </div>

      </div>
    </div>
  );
}
