// FinalReport.jsx — SC-3346 / SC-3403 Final Remediation Report
// Self-contained React component. No external deps (inline styles). Drop in anywhere:
//   import FinalReport from "./FinalReport";  then  <FinalReport />
import React from "react";

const C = {
  bg: "#0f172a", panel: "#1e293b", panel2: "#172033", ink: "#e2e8f0", muted: "#94a3b8",
  line: "#334155", accent: "#38bdf8", green: "#22c55e", teal: "#2dd4bf",
  amber: "#f59e0b", red: "#ef4444", gray: "#64748b",
};

const BADGE = {
  green: { bg: "#052e1a", fg: "#86efac", bd: "#14532d" },
  teal:  { bg: "#04302b", fg: "#5eead4", bd: "#115e59" },
  amber: { bg: "#3a2a06", fg: "#fcd34d", bd: "#78491c" },
  gray:  { bg: "#1f2937", fg: "#cbd5e1", bd: "#475569" },
  red:   { bg: "#3a0d0d", fg: "#fca5a5", bd: "#7f1d1d" },
};

const FINDINGS = [
  ["B-3", "Partner picks 15% not 12%", "RESOLVED", "green", "Bulk overload falls through to Product2 lookup; test green"],
  ["B-4", "Renewal formula null-guards", "RESOLVED (engine)", "green", "V14 active w/ ISNULL guard; computes 67.38 in-flight (proven in log). Display gated by SC-3404."],
  ["B-5", "Decision-table refresh failing", "CLEARED / DROPPED", "teal", "B1 repro: renewing both assets succeeded, never touched the table. Not on the failing path → no window."],
  ["B-6", "Decomposition inconsistent", "RESOLVED", "green", "persistFromWork unconditional; 0 license-base leaks"],
  ["M-1", '"No prehook" SDD false', "RESOLVED", "green", "Reconciliation note delivered; owner applies the .docx text"],
  ["M-2", "Competing new-biz formulas", "READY (rides w/ SC-3404)", "amber", "Dead-code removal; dossier corrected (uses Source_List_Price__c; MDT is a typo)"],
  ["M-3", "Prod lacks _v2 context", "OUT OF SCOPE", "gray", "Prod item — excluded per UAT-only directive"],
  ["M-4", "Source_List_Price mapping", "RESOLVED", "green", "Live deployed class has mapping active"],
  ["M-5", "2 of 4 derived PBEs uncovered", "RESOLVED", "green", "Nir created the 2 PBEDP rows"],
  ["M-6", "Prod prehook stale", "OUT OF SCOPE", "gray", "Prod item — excluded per UAT-only directive"],
  ["M-7", "Renewal classes untested", "RESOLVED", "green", "Solo runs: 100% / 98% / 92% (review's 15%/36% was a stale aggregate)"],
  ["SC-3404", "NEW: native element zeros the renewal maintenance line", "REMAINING — designed, owner-gated", "red", "The actual cause of $0 renewals — see below"],
];

const STATS = [
  ["8", "Closed", C.green], ["1", "Cleared / dropped", C.teal],
  ["2", "Out of scope (prod)", C.gray], ["1", "Remaining (owner-gated)", C.red],
];

const FACTS = [
  ["Commit-precedence", "last vs first resultIncluded=true writer wins; decides one edit vs two."],
  ["Filter polarity", 'DerivedProductsNonRenewal "keeps non-renewals" yet native commits 31 live renewal lines; retain-vs-exclude is unproven.'],
  ["Formula container Branch B", "(Renewal AND ItemIsDerived, no stamp) is broader than the cohort → flipping resultIncluded commits (0 − priors)×(1+uplift) = 0/negative → mass-misprice."],
];

const Badge = ({ kind, children }) => {
  const b = BADGE[kind];
  return (
    <span style={{ display: "inline-block", padding: "3px 9px", borderRadius: 999, fontSize: 12,
      fontWeight: 700, whiteSpace: "nowrap", background: b.bg, color: b.fg, border: `1px solid ${b.bd}` }}>
      {children}
    </span>
  );
};

const Mono = ({ children }) => (
  <code style={{ background: "#0b1424", border: `1px solid ${C.line}`, borderRadius: 5, padding: "1px 6px",
    fontSize: 13, color: "#7dd3fc", fontFamily: "ui-monospace,SFMono-Regular,Menlo,monospace" }}>{children}</code>
);

const H2 = ({ children }) => (
  <h2 style={{ margin: "38px 0 14px", fontSize: 21, borderLeft: `4px solid ${C.accent}`, paddingLeft: 12 }}>{children}</h2>
);

export default function FinalReport() {
  const card = { background: C.panel, border: `1px solid ${C.line}`, borderRadius: 12, padding: "16px 18px" };
  return (
    <div style={{ background: C.bg, color: C.ink, minHeight: "100vh",
      fontFamily: '-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif',
      lineHeight: 1.6, fontSize: 16 }}>
      <div style={{ maxWidth: 1040, margin: "0 auto", padding: "32px 20px 64px" }}>

        {/* Hero */}
        <header style={{ borderRadius: 16, padding: "28px 30px", border: `1px solid ${C.line}`,
          background: "linear-gradient(135deg,#0b3a5e 0%,#10243f 70%)" }}>
          <div style={{ color: C.accent, fontWeight: 700, letterSpacing: ".08em", textTransform: "uppercase", fontSize: 12 }}>
            Final Remediation Report · 2026-06-13
          </div>
          <h1 style={{ margin: "6px 0 4px", fontSize: 30, lineHeight: 1.2 }}>SC-3346 / SC-3403 — Maintenance (Derived) Pricing</h1>
          <div style={{ color: C.muted, fontSize: 15 }}>
            Re-verify &amp; remediate the 11 peer-review findings · <b>FortraUAT only</b> (no prod changes) · Remediation: Liam · Build: Nir/Marc
          </div>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 12, marginTop: 22 }}>
            {STATS.map(([n, l, col]) => (
              <div key={l} style={{ flex: "1 1 150px", ...card }}>
                <div style={{ fontSize: 30, fontWeight: 800, lineHeight: 1, color: col }}>{n}</div>
                <div style={{ color: C.muted, fontSize: 12.5, marginTop: 6, textTransform: "uppercase", letterSpacing: ".04em" }}>{l}</div>
              </div>
            ))}
          </div>
        </header>

        {/* Verdict */}
        <div style={{ margin: "22px 0", padding: "16px 20px", borderRadius: 12, background: BADGE.red.bg,
          border: "1px solid #7f1d1d", fontSize: 15.5 }}>
          Opened at <b style={{ color: "#fca5a5" }}>NO-GO</b> (4 resolved / 3 partial / 4 not resolved). Now:{" "}
          <b style={{ color: "#fca5a5" }}>8 closed · 1 cleared · 2 out-of-scope · 1 remaining</b>. The renewal <i>engine</i> fix
          is live and proven correct — the only thing between here and renewals pricing end-to-end is <b style={{ color: "#fca5a5" }}>SC-3404</b>,
          fully designed but <b>not safely executable without owner confirmation or a clone test</b>.
        </div>

        {/* Scorecard */}
        <H2>Scorecard — all 11 findings</H2>
        <table style={{ width: "100%", borderCollapse: "collapse", background: C.panel, borderRadius: 12,
          overflow: "hidden", border: `1px solid ${C.line}`, fontSize: 14.5 }}>
          <thead>
            <tr>{["#", "Finding", "State", "Evidence"].map((h) => (
              <th key={h} style={{ background: C.panel2, textAlign: "left", padding: "11px 13px", color: C.muted,
                fontSize: 12, textTransform: "uppercase", letterSpacing: ".05em", borderBottom: `1px solid ${C.line}` }}>{h}</th>
            ))}</tr>
          </thead>
          <tbody>
            {FINDINGS.map(([id, finding, status, kind, ev], i) => {
              const blk = id === "SC-3404";
              const td = { padding: "11px 13px", borderBottom: i === FINDINGS.length - 1 ? "none" : `1px solid ${C.line}`,
                verticalAlign: "top", background: blk ? "#2a0d0d" : "transparent" };
              return (
                <tr key={id}>
                  <td style={{ ...td, fontWeight: 700, whiteSpace: "nowrap" }}>{id}</td>
                  <td style={td}>{blk ? <b>{finding}</b> : finding}</td>
                  <td style={td}><Badge kind={kind}>{status}</Badge></td>
                  <td style={{ ...td, color: "#cbd5e1" }}>{ev}</td>
                </tr>
              );
            })}
          </tbody>
        </table>

        {/* Fixed this session */}
        <H2>Fixed this session</H2>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(260px,1fr))", gap: 14 }}>
          {[
            ["B-4 — renewal formula", <>Cloned V14 with the <b>ISNULL</b> guard (corrected from the review's invalid <Mono>BLANKVALUE</Mono>), deployed, activated (recovered an 8-versions-active LWC corruption via per-row Activate), reprice clean. Computes the correct 67.38 in-flight.</>],
            ["M-7 — test coverage", <>Existing dedicated tests already deliver ≥75% on solo runs (100% / 98% / 92%). No new code — the review read a stale partial aggregate.</>],
            ["M-1 — SDD reconciliation", <>Exact corrections written: the SignalingApexProcessor prehook stack is real and necessary; "no prehook" holds only for the new-business derived path.</>],
          ].map(([t, body]) => (
            <div key={t} style={card}>
              <h3 style={{ margin: "0 0 6px", fontSize: 15, color: C.accent }}>{t}</h3>
              <p style={{ margin: 0, color: "#cbd5e1", fontSize: 14 }}>{body}</p>
            </div>
          ))}
        </div>

        {/* B-5 */}
        <H2>B-5 — cleared by repro (key win)</H2>
        <div style={{ borderRadius: 12, padding: "18px 20px", border: "1px solid #14532d", background: "#06281a" }}>
          <h3 style={{ margin: "0 0 8px", fontSize: 17 }}>✅ Not on the renewal failing path — disruptive window removed</h3>
          <p style={{ margin: 0, color: "#cbd5e1" }}>
            Native "renew both assets" on the BoKS test contract (#00069255) <b>succeeded</b>: a 2-line renewal quote was created,{" "}
            <Mono>ValidationResult=None</Mono>, and the FINEST log had <b>zero</b> hits for the AssetActionSource table / "Hash Key Group" /
            "MissingContributor". The table has been unsynced ~12 months while renewals work via Q2O carry-forward.{" "}
            <b>B-5 dropped from SC-3346 — the org-wide-discovery-offline window is off the table.</b>
          </p>
        </div>

        {/* SC-3404 */}
        <H2>SC-3404 — the real renewal blocker <span style={{ color: C.red }}>(designed, NOT executed)</span></H2>
        <div style={{ borderRadius: 12, padding: "18px 20px", border: "1px solid #7f1d1d", background: BADGE.red.bg }}>
          <h3 style={{ margin: "0 0 8px", fontSize: 17 }}>What it is</h3>
          <p style={{ margin: 0, color: "#cbd5e1" }}>
            In active V14, the native <Mono>DerivedProductsRenewals</Mono> element (<Mono>resultIncluded=true</Mono>, authoritative){" "}
            <b>overwrites B-4's correct 67.38 with the native value ($0)</b> for the maintenance line. Proven twice in live FINEST logs.
            This — not B-4 — is why renewal maintenance shows $0.
          </p>
          <h3 style={{ margin: "14px 0 8px", fontSize: 17 }}>Design is ready</h3>
          <p style={{ margin: 0, color: "#cbd5e1" }}>
            Make the native element non-authoritative <b>only</b> for the stamped cohort (<b>5 lines</b>) while it stays authoritative
            for the <b>536,195</b> native-priced lines. Two drafted edits: amend the <Mono>DerivedProductsNonRenewal</Mono> filter, and set{" "}
            <Mono>DerivedPricingRenewals resultIncluded=true</Mono>.
          </p>
          <h3 style={{ margin: "14px 0 8px", fontSize: 17 }}>Why it was NOT executed — 3 facts unknowable read-only; any one wrong silently zeros ~536K lines</h3>
          <div>
            {FACTS.map(([t, body], i) => (
              <div key={t} style={{ position: "relative", padding: "10px 12px 10px 46px", margin: "8px 0",
                background: "#240a0a", border: "1px solid #7f1d1d", borderRadius: 10 }}>
                <span style={{ position: "absolute", left: 12, top: 10, width: 24, height: 24, borderRadius: "50%",
                  background: C.red, color: "#fff", fontWeight: 800, display: "flex", alignItems: "center",
                  justifyContent: "center", fontSize: 13 }}>{i + 1}</span>
                <b>{t}</b> — <span style={{ color: "#cbd5e1" }}>{body}</span>
              </div>
            ))}
          </div>
          <p style={{ marginTop: 10, color: "#cbd5e1" }}>
            In-place V14 (no clone) + <Mono>ExpressionSetVersion</Mono> delete platform-blocked = no safety net. Also Nir's SC-3346 build
            (peer-review NO-GO) overlapping Marc's same-day rework on the same V14.
          </p>
          <h3 style={{ margin: "14px 0 8px", fontSize: 17 }}>Path to GO — pick one</h3>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(280px,1fr))", gap: 12 }}>
            {[
              ["(a) Owner confirms", "Nir/Marc confirm commit-precedence + filter polarity → apply the verified edits in-place with the FIM-462 regression gate + context resync + V14 backup."],
              ["(b) Clone test", 'Validate on a V14 clone with an authorized reprice (67.38 positive + FIM-462 native-preserve + Branch-B no-zero). Requires relaxing "no new versions" for the test.'],
            ].map(([tag, body]) => (
              <div key={tag} style={{ background: "#06281a", border: "1px solid #14532d", borderRadius: 10, padding: "14px 16px" }}>
                <span style={{ fontWeight: 800, color: C.green, fontSize: 13 }}>{tag}</span>
                <p style={{ margin: "6px 0 0", color: "#cbd5e1", fontSize: 14 }}>{body}</p>
              </div>
            ))}
          </div>
        </div>

        {/* Live state */}
        <H2>Current UAT live state</H2>
        <div style={{ display: "flex", gap: 10, alignItems: "flex-start", background: "#06281a",
          border: "1px solid #14532d", borderRadius: 12, padding: "16px 18px" }}>
          <div style={{ width: 11, height: 11, borderRadius: "50%", background: C.green, marginTop: 7, flex: "none",
            boxShadow: "0 0 0 4px rgba(34,197,94,.18)" }} />
          <div>
            <b>Healthy.</b> Pricing procedure <b>V14 active</b> (sole) — carries B-4's ISNULL renewal fix; new-business &amp;
            non-renewal pricing clean (no gack, healthy limits). Renewal maintenance <b>still displays $0</b> pending SC-3404.
            Nothing half-applied; V14 is reversible (re-activate V13 + resync).
          </div>
        </div>

        {/* Out of scope */}
        <H2>Out of scope · per "UAT only — no prod changes"</H2>
        <div style={{ ...card, borderColor: "#475569" }}>
          <p style={{ margin: 0 }}>
            <Badge kind="gray">M-3</Badge> &nbsp; <Badge kind="gray">M-6</Badge> &nbsp; Prod context + prod prehook — not prepared or touched.
            A prod-cutover manifest exists in <Mono>09_REMAINING_EXECUTION_PLAN.md</Mono> for whenever a prod cutover is separately authorized.
          </p>
        </div>

        {/* Next steps */}
        <H2>Recommended next steps (owner)</H2>
        <ol style={{ margin: "10px 0", paddingLeft: 22 }}>
          <li style={{ margin: "6px 0" }}><b>SC-3404</b> — get Nir/Marc to confirm the engine semantics (a) or authorize a clone test (b); then execute the verified edit (M-2 rides along). Closes renewal end-to-end.</li>
          <li style={{ margin: "6px 0" }}>Apply the M-1 SDD text edits (doc owner).</li>
          <li style={{ margin: "6px 0" }}>Treat B-5 as a latent platform item — no action for SC-3346.</li>
          <li style={{ margin: "6px 0" }}>Prod cutover (M-3 / M-6 + the validated V14) — separate, explicitly-authorized engagement.</li>
        </ol>

        <footer style={{ marginTop: 40, color: C.muted, fontSize: 13, borderTop: `1px solid ${C.line}`, paddingTop: 16 }}>
          <b>Dossier:</b>{" "}
          {["02 blockers", "05 re-verification", "06 B-5", "07 B-4", "08 M-1", "09 remaining plan", "10 B-5 runbook", "FINAL_REPORT"].map((p) => (
            <span key={p} style={{ display: "inline-block", background: C.panel, border: `1px solid ${C.line}`,
              borderRadius: 6, padding: "2px 8px", margin: "3px 4px 0 0", fontSize: 12.5, color: "#cbd5e1" }}>{p}</span>
          ))}
          <div style={{ marginTop: 8 }}>
            Artifacts: <Mono>Data/sc-maint/reverify/</Mono> · <Mono>Data/sc-maint/sc3346_b4/</Mono> · <Mono>Data/sc-maint/sc3404/</Mono>
          </div>
        </footer>

      </div>
    </div>
  );
}
