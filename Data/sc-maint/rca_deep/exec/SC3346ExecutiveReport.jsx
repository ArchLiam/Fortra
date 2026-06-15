/**
 * SC-3346 — Renewal-Maintenance Pricing: Root Cause & Fix (Executive Report)
 * High-visibility React mirror of SC3346_EXECUTIVE_REPORT.html.
 * Self-contained: inline styles, no external CSS/deps. Default-exported.
 *
 *   <SC3346ExecutiveReport />
 */
import React from "react";

const C = {
  bg: "#0d1117", card: "#161b22", line: "#30363d", line2: "#21262d",
  text: "#e6edf3", mut: "#9aa4af", mut2: "#7d8590",
  green: "#3fb950", greenL: "#7ee787", blue: "#79c0ff", orange: "#db6d28",
  red: "#ff7b72", amber: "#e3b341",
};

const KPI = ({ n, l, color }) => (
  <div style={{ flex: 1, minWidth: 150, background: C.card, border: `1px solid ${C.line}`,
    borderRadius: 13, padding: 18, textAlign: "center" }}>
    <div style={{ fontSize: 34, fontWeight: 850, lineHeight: 1.05, color }}>{n}</div>
    <div style={{ fontSize: 11.5, letterSpacing: ".8px", textTransform: "uppercase",
      color: C.mut2, marginTop: 8, fontWeight: 600 }}>{l}</div>
  </div>
);

const SecH = ({ children }) => (
  <div style={{ fontSize: 13, letterSpacing: "2px", textTransform: "uppercase",
    color: C.mut2, fontWeight: 800, margin: "40px 0 14px" }}>{children}</div>
);

const Card = ({ title, children }) => (
  <div style={{ background: C.card, border: `1px solid ${C.line}`, borderRadius: 14, padding: "22px 24px" }}>
    {title && <h3 style={{ fontSize: 17, marginBottom: 10, color: "#fff" }}>{title}</h3>}
    <div style={{ fontSize: 14.5, color: "#adbac7" }}>{children}</div>
  </div>
);

const Pill = ({ kind, children }) => {
  const m = {
    ok: { color: C.green, background: "#0e2a18" },
    bad: { color: C.red, background: "#2a1416" },
    warn: { color: C.amber, background: "#2d2606" },
  }[kind];
  return <span style={{ display: "inline-block", fontSize: 11, fontWeight: 800,
    padding: "2px 9px", borderRadius: 20, ...m }}>{children}</span>;
};

const Row = ({ cells }) => (
  <tr>{cells.map((c, i) => (
    <td key={i} style={{ padding: "10px 12px", borderBottom: `1px solid ${C.line2}`,
      verticalAlign: "top", color: "#c9d1d9", fontSize: 14 }}>{c}</td>
  ))}</tr>
);

const Table = ({ head, rows }) => (
  <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 14, marginTop: 4 }}>
    <thead><tr>{head.map((h, i) => (
      <th key={i} style={{ textAlign: "left", padding: "9px 12px", fontSize: 11,
        letterSpacing: "1px", textTransform: "uppercase", color: C.mut2,
        borderBottom: `2px solid ${C.line}` }}>{h}</th>
    ))}</tr></thead>
    <tbody>{rows.map((r, i) => <Row key={i} cells={r} />)}</tbody>
  </table>
);

const ChainStep = ({ n, fix, children }) => (
  <li style={{ position: "relative", padding: "10px 0 10px 42px", fontSize: 14.5,
    color: "#c9d1d9", borderLeft: `2px solid ${C.line}`, marginLeft: 14, listStyle: "none" }}>
    <span style={{ position: "absolute", left: -15, top: 9, width: 28, height: 28, borderRadius: "50%",
      background: fix ? C.green : C.orange, color: "#fff", fontWeight: 800, fontSize: 13,
      display: "flex", alignItems: "center", justifyContent: "center" }}>{n}</span>
    {children}
  </li>
);

const Mono = ({ children }) => (
  <span style={{ fontFamily: "ui-monospace,Menlo,monospace", fontSize: 12.5, color: C.blue }}>{children}</span>
);
const Code = ({ children }) => (
  <code style={{ fontFamily: "ui-monospace,Menlo,monospace", fontSize: 12.5,
    background: "#21262d", padding: "1px 5px", borderRadius: 5, color: C.amber }}>{children}</code>
);

export default function SC3346ExecutiveReport() {
  return (
    <div style={{ fontFamily: '-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif',
      background: C.bg, color: C.text, lineHeight: 1.55, padding: "44px 26px 80px", minHeight: "100vh" }}>
      <div style={{ maxWidth: 1180, margin: "0 auto" }}>

        <div style={{ fontSize: 13, letterSpacing: "2.5px", textTransform: "uppercase",
          color: C.mut2, fontWeight: 700 }}>
          Executive Report · Revenue Cloud / RLM · FortraUAT · 2026-06-14
        </div>
        <h1 style={{ fontSize: 38, fontWeight: 850, margin: "6px 0 6px", lineHeight: 1.08 }}>
          SC-3346 — Renewal-Maintenance Pricing
        </h1>
        <div style={{ fontSize: 15, color: C.mut }}>
          Root cause &amp; fix for renewal-maintenance lines committing the wrong price.
          Powertech IAM (BoKS) — the Fortra-sanctioned DPP product.
        </div>

        <div style={{ margin: "26px 0", padding: "24px 28px", borderRadius: 16,
          background: "linear-gradient(135deg,#0e2a18,#0a1f12)", border: `1px solid #2ea043` }}>
          <div style={{ fontSize: 12, letterSpacing: "2px", textTransform: "uppercase",
            color: C.green, fontWeight: 800 }}>Verdict</div>
          <div style={{ fontSize: 23, fontWeight: 750, marginTop: 7, color: "#fff" }}>
            <b style={{ color: C.greenL }}>FIXED.</b> Root cause found, fix built, deployed, and proven
            end-to-end — a renewal now commits the correct COLA net{" "}
            <b style={{ color: C.greenL }}>$67.38</b> instead of the frozen{" "}
            <b style={{ color: C.greenL }}>$60.64 / $0</b>. One Setup-UI toggle remains to switch it on in production.
          </div>
        </div>

        <div style={{ display: "flex", gap: 13, flexWrap: "wrap", margin: "22px 0" }}>
          <KPI n="$67.38" l="Now commits (was $60.64/$0)" color={C.green} />
          <KPI n="2" l="Components deployed" color={C.blue} />
          <KPI n="4/4" l="Unit tests pass" color={C.green} />
          <KPI n="6+" l="Dead-ends ruled out" color={C.amber} />
          <KPI n="1" l="UI step to activate" color={C.amber} />
        </div>

        <SecH>The defect — in business terms</SecH>
        <Card>
          When a customer renews their maintenance, the renewal line was pricing at the <b>wrong amount</b> —
          a stale <b>$60.64</b> (or <b>$0</b>) instead of the correct cost-of-living-adjusted renewal of{" "}
          <b>$67.38</b> (last year&rsquo;s net $62.48 × 7.85% COLA). The pricing math was always right; the value
          simply never <i>committed</i> to the line. Multiple prior attempts to patch it had failed because they
          all worked at the wrong layer.
        </Card>

        <SecH>Root cause — a selling-model mismatch (found via end-to-end debug)</SecH>
        <ol style={{ counterReset: "step", padding: 0 }}>
          <ChainStep n="1">
            New-business maintenance is sold as a <b>One-Time</b> product, so the asset the customer owns is
            One-Time — <b>not a renewable subscription</b>.
          </ChainStep>
          <ChainStep n="2">
            The platform&rsquo;s renewal therefore tags that asset as <b>&ldquo;No Change&rdquo; / quantity&nbsp;0</b> —
            it never enters the COLA renewal-pricing path (which only fires on a <Code>Renew</Code> action).
          </ChainStep>
          <ChainStep n="3">
            The legacy design then <b>deleted</b> that owned-asset line and substituted a separate
            &ldquo;Renewal Maintenance&rdquo; line that has <b>no asset to price against</b> — so it froze at the
            wrong value or $0.
          </ChainStep>
          <ChainStep n="4" fix>
            <b>The fix:</b> stop discarding the owned line — <b>flip it to <Code>Renew</Code></b> and let the
            native engine apply the COLA uplift to last year&rsquo;s net. No new pricing logic, no catalog change.
          </ChainStep>
        </ol>

        <SecH>The fix — what was built &amp; deployed</SecH>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 18 }}>
          <Card title={<>1 · Apex: <Mono>RenewalMaintenanceFlip</Mono></>}>
            Flips the owned-maintenance renewal line from <Code>No Change → Renew</Code> and sets the renew
            quantity. ~120 lines, bulk-safe, <b>4/4 unit tests pass</b>. Deployed to UAT.
          </Card>
          <Card title={<>2 · Flow: <Mono>Fortra_Create_Renewal_Quote</Mono></>}>
            Wired so every renewal automatically runs <b>flip → reprice</b>:
            <div style={{ fontFamily: "ui-monospace,Menlo,monospace", fontSize: 13, background: C.bg,
              border: `1px solid ${C.line}`, borderRadius: 10, padding: "12px 14px", marginTop: 8 }}>
              initiate renewal <span style={{ color: C.mut2 }}>→</span>{" "}
              <span style={{ color: C.amber }}>Flip Maintenance</span> <span style={{ color: C.mut2 }}>→</span>{" "}
              <span style={{ color: C.amber }}>Reprice</span> <span style={{ color: C.mut2 }}>→</span>{" "}
              <span style={{ color: C.green }}>$67.38 committed</span>
            </div>
          </Card>
        </div>

        <SecH>Validation — end-to-end, on a real owned asset</SecH>
        <Table head={["Check", "Result"]} rows={[
          [<>Renewal flips owned maintenance to <Code>Renew</Code></>, <><Pill kind="ok">PASS</Pill> qty 1, action = Renew</>],
          ["Commits the correct COLA net", <><Pill kind="ok">PASS</Pill> NetUnitPrice = <b>$67.38</b> (= $62.48 × 1.0785)</>],
          ["No double partner-discount", <><Pill kind="ok">PASS</Pill> COLA applied to the partner-net LTP</>],
          ["Line survives the renewal cleanup", <><Pill kind="ok">PASS</Pill> 1 line, $67.38, no stray $0 line</>],
          ["Unit tests", <><Pill kind="ok">PASS</Pill> 4 / 4</>],
          ["Downstream (Workday line-type, billing, ARR)", <><Pill kind="ok">SAFE</Pill> independent of the maintenance-type split</>],
        ]} />

        <SecH>Why earlier attempts failed — the wrong layer (ruled out, so they need never be tried again)</SecH>
        <Table head={["Attempted lever", "Why it can't work"]} rows={[
          [<>Write <Code>NetUnitPrice</Code> directly</>, <><Pill kind="bad">DEAD</Pill> engine-owned, read-only on insert</>],
          ["Posthook / procedure committer / RMPS", <><Pill kind="bad">DEAD</Pill> reprice-time writes no-op on a settled derived line (proven 3×)</>],
          ["Map the owned product as a price contributor (PBEDP)", <><Pill kind="bad">DEAD</Pill> platform-blocked — it&rsquo;s a derived product</>],
          ["Hand-attach a renewal QuoteAction", <><Pill kind="bad">DEAD</Pill> doesn&rsquo;t resolve the contributor; only the real renewal does</>],
          ["Re-model the catalog (merge products)", <><Pill kind="warn">UNNEEDED</Pill> higher blast radius; the flip achieves the same outcome</>],
        ]} />

        <SecH>To switch on in production</SecH>
        <Card>
          <b>One Setup-UI step (owner):</b> deactivate the Year-2 AutoAdd rule <Mono>14OWC0000022Eyb2AE</Mono> so
          the asset-less &ldquo;Renewal Maintenance&rdquo; line is no longer added (it&rsquo;s Configuration-Rule
          metadata, only togglable in Setup). With it off, the flipped line is the sole, correctly-priced
          maintenance line. Then: one production renewal smoke-test, and resolve the pre-existing{" "}
          <Code>COLAUpliftTest</Code> coverage drift before prod promotion.
        </Card>

        <div style={{ marginTop: 32, color: "#6e7681", fontSize: 12.5, textAlign: "center" }}>
          Deployed to FortraUAT · mechanism proven on owned RNM asset 02iWC000008DmS1YAK · test data cleaned,
          canary baseline intact · no Orders activated, no Workday events · full technical detail in the companion MD
        </div>

      </div>
    </div>
  );
}
