/**
 * SC-3354 — Peer Review Comment (high-visibility)
 * React mirror of SC-3354_jira_comment.html. Self-contained, inline styles, default-exported.
 *
 *   <SC3354JiraComment />
 */
import React from "react";

const C = {
  bg: "#0d1117", card: "#161b22", card2: "#1c2330", line: "#30363d", line2: "#21262d",
  text: "#e6edf3", mut: "#9aa4af", mut2: "#7d8590",
  green: "#3fb950", greenL: "#7ee787", greenD: "#0e2a18",
  red: "#ff7b72", redD: "#2a1416", amber: "#e3b341", amberD: "#2d2606",
};

const Mono = ({ children }) => (
  <code style={{ fontFamily: "ui-monospace,SFMono-Regular,Menlo,Consolas,monospace", fontSize: ".85em",
    background: "#0a0e14", border: `1px solid ${C.line2}`, borderRadius: 5, padding: "1px 6px", color: "#b9c4d0" }}>{children}</code>
);
const SecH = ({ children }) => (
  <div style={{ fontSize: 12, letterSpacing: "1.8px", textTransform: "uppercase", color: C.mut2, fontWeight: 800, margin: "30px 0 12px" }}>{children}</div>
);
const Pill = ({ kind, children }) => {
  const m = { bad: { color: C.red, background: C.redD }, warn: { color: C.amber, background: C.amberD }, ok: { color: C.greenL, background: C.greenD } }[kind];
  return <span style={{ display: "inline-block", fontSize: 10, fontWeight: 800, padding: "2px 8px", borderRadius: 20,
    textTransform: "uppercase", letterSpacing: ".3px", whiteSpace: "nowrap", ...m }}>{children}</span>;
};
const Table = ({ head, rows }) => (
  <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13.5 }}>
    <thead><tr>{head.map((h, i) => (
      <th key={i} style={{ textAlign: "left", padding: "8px 10px", fontSize: 10, letterSpacing: ".8px", textTransform: "uppercase", color: C.mut2, borderBottom: `2px solid ${C.line}`, fontWeight: 700 }}>{h}</th>))}</tr></thead>
    <tbody>{rows.map((r, ri) => (
      <tr key={ri}>{r.map((c, ci) => (
        <td key={ci} style={{ padding: "9px 10px", borderBottom: `1px solid ${C.line2}`, verticalAlign: "top", color: "#c9d1d9" }}>{c}</td>))}</tr>))}
    </tbody>
  </table>
);
const ok = (t) => <span style={{ color: C.greenL, fontWeight: 700 }}>{t}</span>;
const bad = (t) => <span style={{ color: C.red, fontWeight: 700 }}>{t}</span>;
const warn = (t) => <span style={{ color: C.amber, fontWeight: 700 }}>{t}</span>;

const TraceLi = ({ label, v, vcolor, last }) => (
  <li style={{ padding: "5px 0", fontSize: 13.5, color: "#c9d1d9", borderBottom: last ? "none" : `1px dashed ${C.line2}`, overflow: "hidden" }}>
    {label}<span style={{ float: "right", fontFamily: "ui-monospace,monospace", color: vcolor }}>{v}</span>
  </li>
);

export default function SC3354JiraComment() {
  return (
    <div style={{ background: C.bg, color: C.text, minHeight: "100vh",
      fontFamily: '-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif', lineHeight: 1.55 }}>
      <div style={{ maxWidth: 920, margin: "0 auto", padding: "34px 24px 70px" }}>

        <h1 style={{ fontSize: 23, margin: "0 0 4px", letterSpacing: "-.2px" }}>Peer Review (re-run) — COLA Renewal Pricing</h1>
        <div style={{ color: C.mut, fontSize: 13, marginBottom: 22 }}>
          Board <b style={{ color: "#c9d1d9" }}>SC-3350</b> · Peer-review subtask <b style={{ color: "#c9d1d9" }}>SC-3354</b> ·
          Org <b style={{ color: "#c9d1d9" }}>FortraUAT</b> · <b style={{ color: "#c9d1d9" }}>2026-06-26</b> · PROD promotion deferred
        </div>

        <div style={{ display: "flex", alignItems: "center", gap: 14, flexWrap: "wrap",
          background: "linear-gradient(110deg,#2a240680,#1c2330)", border: "1px solid #6b551f",
          borderLeft: `5px solid ${C.amber}`, borderRadius: 13, padding: "16px 20px" }}>
          <span style={{ fontSize: 15, fontWeight: 800, color: C.red, textDecoration: "line-through", opacity: .8 }}>NO-GO</span>
          <span style={{ color: C.mut2, fontSize: 18 }}>→</span>
          <span style={{ fontSize: 22, fontWeight: 900, color: C.amber, letterSpacing: ".4px" }}>◑ CONDITIONAL</span>
          <span style={{ flex: 1, minWidth: 240, fontSize: 13.5, color: "#cdd6df" }}>
            Headline regression fixed &amp; live for non-partner renewals. Not yet GO: a new partner-line cascade needs a pricing decision + 3 high-severity items remain.</span>
        </div>
        <div style={{ marginTop: 10 }}>
          <span style={{ display: "inline-block", fontFamily: "ui-monospace,monospace", fontSize: 11.5, background: "#0a0e14",
            border: `1px solid ${C.line}`, borderRadius: 6, padding: "3px 9px", color: "#9fb4c9" }}>deploy 0AfWC00000GZHnx0AH · 48/48 components · 129/129 tests green</span>
        </div>

        <SecH>Root cause (recap)</SecH>
        <div style={{ background: C.card, border: `1px solid ${C.line}`, borderRadius: 13, padding: "16px 20px", marginBottom: 12 }}>
          <p style={{ margin: "7px 0", fontSize: 14, color: "#adbac7" }}>
            The original SC-3350 fix — a <Mono>COLAUpliftPrehook</Mono> isolated <Mono>NetUnitPrice</Mono> seed, the only mechanism proven to
            commit the COLA net for non-derived renewal lines — was <b>deleted</b> when the co-owned class was reworked for <b>SC-3346</b> on
            06-13/14. Defect #1 then reproduced at {bad("100%")} (9/9 fresh renewals at <Mono>NetUnitPrice = 0</Mono>; one Accepted at GrandTotal
            $0). Green tests missed it — <b>no test asserted a committed net</b>.
          </p>
        </div>

        <SecH>Fixed &amp; deployed to UAT</SecH>
        <Table head={["#", "Item", "Sev", "Status"]}
          rows={[
            [<Mono>B-1/B-2</Mono>, <>Re-grafted the isolated <Mono>NetUnitPrice</Mono> seed onto the <b>current</b> v1.2 prehook (maintenance-excluded — can't re-clobber SC-3346). Confirmed firing in the live debug log; commits the COLA net.</>, <Pill kind="bad">blocker</Pill>, ok("✅ fixed (non-partner)")],
            [<Mono>B-4</Mono>, <>Full COLA bundle staged in <Mono>force-app</Mono> + validated deployable. Dropped shared trigger + <Mono>rca_diagnostic</Mono> orphan; managed <Mono>ffscpq</Mono> excluded.</>, <Pill kind="bad">blocker</Pill>, ok("✅ closed")],
            [<Mono>B-5</Mono>, <>Added <Mono>MyCAP Default</Mono> to <Mono>COLA_Source__c</Mono> — removes the restricted-picklist deploy trap.</>, <Pill kind="bad">blocker</Pill>, ok("✅ closed")],
            [<Mono>C-1</Mono>, "Added 3 net-seed tests (the gap that let the regression ship silently).", <Pill kind="warn">high</Pill>, ok("✅ closed")],
          ]} />

        <SecH>New finding — partner-line cascade (blocker)</SecH>
        <div style={{ background: C.card, border: `1px solid ${C.line}`, borderLeft: `4px solid ${C.amber}`, borderRadius: 13, padding: "16px 20px", marginBottom: 12 }}>
          <p style={{ margin: "7px 0", fontSize: 14, color: "#adbac7" }}>
            Repricing a <b>partner</b> renewal (beSECURE, 18% partner discount) surfaced a defect the $0 had masked. Debug-log trace of one reprice:</p>
          <ul style={{ listStyle: "none", margin: "6px 0", padding: 0 }}>
            <TraceLi label={<><Mono>PartnerPricingPrehook</Mono> stamps the partner %</>} v="18.00%" vcolor="#c9d1d9" />
            <TraceLi label="COLA seed fires ✅" v="7,110.41" vcolor={C.greenL} />
            <TraceLi label="V16 procedure re-applies 18% to the stored net" v="→ 4,781.04" vcolor={C.red} />
            <TraceLi label="Posthook tries to reset — write no-ops" v="wants 7,110.41" vcolor={C.amber} last />
          </ul>
          <p style={{ margin: "7px 0", fontSize: 14, color: "#adbac7" }}>
            Net cascades every reprice: <span style={{ fontFamily: "ui-monospace,monospace", color: C.red }}>$0 → 5,830.54 → 4,781.04 → …</span> (×0.82 each). Non-partner renewals are unaffected.</p>
          <div style={{ background: C.card2, border: `1px solid ${C.line}`, borderLeft: `4px solid ${C.amber}`, borderRadius: 10, padding: "13px 16px", margin: "8px 0", fontSize: 13.5, color: "#cdd6df" }}>
            <b>Open decision (business rule, revenue-impacting — Nir/Marc):</b> does a partner subscription renewal get the partner discount re-applied <i>on top of</i> the COLA'd prior net, or is the COLA'd prior net the final price?
            <div style={{ margin: "6px 0" }}><span style={{ color: C.greenL, fontWeight: 700 }}>▸ Recommended: COLA net final = 7,110.41</span> — no re-discount (asset price is the prior net, already partner-discounted, like SC-3346's 62.48; posthook already intends this).</div>
            <div style={{ margin: "6px 0" }}>▸ Alternative: partner discount once = 5,830.54 (if asset price is a list/pre-partner figure).</div>
            Either answer is a co-owned fix (<Mono>PartnerPricingPrehook</Mono> / V16), not the B-1 seed. <b>Holding for the decision.</b>
          </div>
        </div>

        <SecH>Still open</SecH>
        <Table head={["Item", "Sev", "Note"]}
          rows={[
            ["Partner-line cascade", <Pill kind="warn">blocker (new)</Pill>, "Needs the business-rule decision above + co-owned fix"],
            ["Defect #2 — descriptions (B-3)", <Pill kind="warn">high</Pill>, "~36% of attribute-bearing renewal lines still null; not started"],
            ["Prehook fail-silent (B-6)", <Pill kind="warn">high</Pill>, "Catch returns SUCCESS on any exception; not started"],
            ["Rate grain (B-7)", <Pill kind="warn">high</Pill>, "Systems Mgmt 7.85 vs 12.00; Cybersecurity 7.85 vs 4.70 — staged as-is"],
            ["B-1 live proof", <Pill kind="ok">verify</Pill>, "Reprice a non-partner line (OST / Active Defense) to confirm a clean, stable commit"],
            ["B-1 edges", <Pill kind="ok">low</Pill>, "~3 null-asset-price lines (scoped out); 1 Accepted $0 quote needs forward-only remediation"],
          ]} />

        <div style={{ marginTop: 36, paddingTop: 16, borderTop: `1px solid ${C.line}`, fontSize: 13, color: "#adbac7" }}>
          <b>Verdict:</b> of the 4 hard blockers, {ok("B-4 and B-5 are fully closed")} and {ok("B-1/B-2 is fixed & live")} for the common
          (non-partner) case — the 100%-reproduction regression is resolved there. A partner-line cascade (new) needs a pricing decision, and
          high-severity B-3/B-6/B-7 remain. <b>Not yet go-live.</b>
        </div>

      </div>
    </div>
  );
}
