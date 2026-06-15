/**
 * SC-3346 — Maintenance (Derived) Pricing + COLA: Full Root-Cause Analysis
 * High-visibility React mirror of SC3346_FULL_RCA.html. Self-contained, inline styles, default-exported.
 *
 *   <SC3346FullRCA />
 *
 * All figures are live-verified (FortraUAT, 2026-06-14): tests 4/4 + 100% class coverage;
 * E2E all-lines + header-rollup proof; canary asset 02iWC000008DmS1YAK.
 */
import React from "react";

const C = {
  bg: "#0d1117", card: "#161b22", line: "#30363d", line2: "#21262d",
  text: "#e6edf3", mut: "#9aa4af", mut2: "#7d8590", blue: "#58a6ff", blue2: "#79c0ff",
  green: "#3fb950", greenL: "#7ee787", orange: "#db6d28", red: "#ff7b72", amber: "#e3b341",
};

const KPI = ({ n, l, color }) => (
  <div style={{ flex: 1, minWidth: 140, background: C.card, border: `1px solid ${C.line}`,
    borderRadius: 13, padding: 16, textAlign: "center" }}>
    <div style={{ fontSize: 30, fontWeight: 850, lineHeight: 1.05, color }}>{n}</div>
    <div style={{ fontSize: 11, letterSpacing: ".6px", textTransform: "uppercase",
      color: C.mut2, marginTop: 7, fontWeight: 600 }}>{l}</div>
  </div>
);

const SecH = ({ children }) => (
  <div style={{ fontSize: 13, letterSpacing: "2px", textTransform: "uppercase", color: C.blue,
    fontWeight: 800, margin: "38px 0 14px", paddingBottom: 7, borderBottom: `1px solid ${C.line2}` }}>{children}</div>
);

const Card = ({ title, children, style }) => (
  <div style={{ background: C.card, border: `1px solid ${C.line}`, borderRadius: 14, padding: "20px 22px", ...style }}>
    {title && <h3 style={{ fontSize: 16, marginBottom: 9, color: "#fff" }}>{title}</h3>}
    <div style={{ fontSize: 14, color: "#adbac7" }}>{children}</div>
  </div>
);

const Pill = ({ kind, children }) => {
  const m = {
    ok: { color: C.green, background: "#0e2a18" }, bad: { color: C.red, background: "#2a1416" },
    warn: { color: C.amber, background: "#2d2606" }, info: { color: C.blue, background: "#0d2440" },
  }[kind];
  return <span style={{ display: "inline-block", fontSize: 10.5, fontWeight: 800, padding: "2px 8px",
    borderRadius: 20, whiteSpace: "nowrap", ...m }}>{children}</span>;
};

const Table = ({ head, rows }) => (
  <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13.5, marginTop: 4 }}>
    <thead><tr>{head.map((h, i) => (
      <th key={i} style={{ textAlign: "left", padding: "8px 11px", fontSize: 10.5, letterSpacing: ".8px",
        textTransform: "uppercase", color: C.mut2, borderBottom: `2px solid ${C.line}` }}>{h}</th>
    ))}</tr></thead>
    <tbody>{rows.map((r, i) => (
      <tr key={i}>{r.map((c, j) => (
        <td key={j} style={{ padding: "9px 11px", borderBottom: `1px solid ${C.line2}`,
          verticalAlign: "top", color: "#c9d1d9" }}>{c}</td>
      ))}</tr>
    ))}</tbody>
  </table>
);

const Mono = ({ children }) => (
  <span style={{ fontFamily: "ui-monospace,Menlo,monospace", fontSize: 12, color: C.blue2 }}>{children}</span>
);
const Code = ({ children }) => (
  <code style={{ fontFamily: "ui-monospace,Menlo,monospace", fontSize: 12, background: "#21262d",
    padding: "1px 5px", borderRadius: 5, color: C.amber }}>{children}</code>
);
const G = ({ children }) => <b style={{ color: C.greenL }}>{children}</b>;

const ChainStep = ({ n, fix, children }) => (
  <li style={{ position: "relative", padding: "9px 0 9px 42px", fontSize: 14.5, color: "#c9d1d9",
    borderLeft: `2px solid ${C.line}`, marginLeft: 14, listStyle: "none" }}>
    <span style={{ position: "absolute", left: -15, top: 8, width: 28, height: 28, borderRadius: "50%",
      background: fix ? C.green : C.orange, color: "#fff", fontWeight: 800, fontSize: 13,
      display: "flex", alignItems: "center", justifyContent: "center" }}>{n}</span>
    {children}
  </li>
);

const Phase = ({ n, win, h, d }) => (
  <li style={{ position: "relative", padding: "11px 0 11px 46px", borderLeft: `2px solid ${C.line}`,
    marginLeft: 16, listStyle: "none" }}>
    <span style={{ position: "absolute", left: -19, top: 9, width: 36, height: 24, borderRadius: 12,
      background: win ? "#0e2a18" : "#1f2937", border: `1px solid ${win ? "#2ea043" : C.line}`,
      color: win ? C.green : C.blue, fontWeight: 800, fontSize: 11,
      display: "flex", alignItems: "center", justifyContent: "center" }}>{"P" + n}</span>
    <div style={{ fontSize: 14.5, fontWeight: 700, color: C.text }}>{h}</div>
    <div style={{ fontSize: 13.5, color: C.mut, marginTop: 2 }}>{d}</div>
  </li>
);

const Note = ({ children }) => (
  <div style={{ background: "#13202e", border: "1px solid #1f4060", borderLeft: `3px solid ${C.blue}`,
    borderRadius: 8, padding: "12px 15px", fontSize: 13.5, color: "#adbac7", marginTop: 10 }}>{children}</div>
);

export default function SC3346FullRCA() {
  return (
    <div style={{ fontFamily: '-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif',
      background: C.bg, color: C.text, lineHeight: 1.55, padding: "44px 26px 70px", minHeight: "100vh" }}>
      <div style={{ maxWidth: 1200, margin: "0 auto" }}>

        <div style={{ fontSize: 13, letterSpacing: "2.5px", textTransform: "uppercase", color: C.mut2, fontWeight: 700 }}>
          Root-Cause Analysis · Revenue Cloud Advanced / RLM · FortraUAT · 2026-06-14
        </div>
        <h1 style={{ fontSize: 37, fontWeight: 850, margin: "6px 0 6px", lineHeight: 1.08 }}>
          SC-3346 — Maintenance (Derived) Pricing + COLA
        </h1>
        <div style={{ fontSize: 15, color: C.mut, maxWidth: 880 }}>
          Full investigation, root cause, fix, and live end-to-end validation for renewal-maintenance lines
          committing the wrong COLA price. Product in scope: Powertech Identity &amp; Access Manager (BoKS).
        </div>

        <div style={{ margin: "24px 0", padding: "22px 26px", borderRadius: 16,
          background: "linear-gradient(135deg,#0e2a18,#0a1f12)", border: "1px solid #2ea043" }}>
          <div style={{ fontSize: 12, letterSpacing: "2px", textTransform: "uppercase", color: C.green, fontWeight: 800 }}>Verdict</div>
          <div style={{ fontSize: 22, fontWeight: 740, marginTop: 7, color: "#fff" }}>
            <G>FIXED — deployed and end-to-end proven on live data.</G> A maintenance renewal now commits the correct
            COLA net <G>$67.38</G> (= 62.48 × 1.0785) instead of the frozen <G>$60.64 / $0</G> — the native engine
            applies the COLA uplift once the owned line renews as <b>Renew</b>.
          </div>
        </div>

        <div style={{ display: "flex", gap: 12, flexWrap: "wrap", margin: "20px 0" }}>
          <KPI n="$67.38" l="Now commits (was $60.64/$0)" color={C.green} />
          <KPI n="4/4" l="Unit tests · 100% class cov" color={C.green} />
          <KPI n="1 / 0" l="Lines total / stray RRM" color={C.blue2} />
          <KPI n="$67.38" l="Quote rollup (not stale)" color={C.green} />
          <KPI n="6" l="Dead-ends ruled out" color={C.amber} />
          <KPI n="0" l="Catalog / model changes" color={C.green} />
        </div>

        <SecH>1 · The defect — in business terms</SecH>
        <Card>
          When a customer renews their BoKS maintenance, the renewal line priced at the <b>wrong amount</b> — a stale{" "}
          <b>$60.64</b> (a one-period double-discounted fossil, = 67.38 × 0.90) or <b>$0</b> — instead of the correct
          cost-of-living-adjusted renewal of <b>$67.38</b> (last year’s net $62.48 × 7.85% COLA). The COLA arithmetic was
          never wrong; the value simply <b>never committed</b> to the line. Several prior remediation attempts failed
          because every one tried to <i>write the price</i> at reprice time — the wrong layer entirely.
        </Card>

        <SecH>2 · Root cause — a selling-model mismatch (found via end-to-end debug)</SecH>
        <ol style={{ counterReset: "step", padding: 0 }}>
          <ChainStep n="1">
            New-business maintenance (<Mono>PIA-PIA-RNM-PIAMBK</Mono>) is sold under a <b>One-Time</b> selling model, so
            the asset the customer owns is One-Time — <b>not a renewable subscription</b>.
          </ChainStep>
          <ChainStep n="2">
            The platform’s <Code>initiateRenewal</Code> therefore tags that asset’s renewal as{" "}
            <b>QuoteAction.Type = “No Change”, Quantity 0</b> — which never enters the <Code>Renew</Code>-gated COLA path
            (<Mono>COLAUpliftonRenewalNet</Mono>). Term-Based subscriptions (beSECURE) renew as <Code>Renew</Code> and price correctly.
          </ChainStep>
          <ChainStep n="3">
            The legacy Year-2 AutoAdd rule then <b>deletes</b> that owned-asset line and substitutes an asset-less{" "}
            <b>Renewal-Maintenance</b> line (<Mono>PIA-PIA-RRM-PIAM</Mono>) with <b>no contributor</b> — the native{" "}
            <Mono>DerivedProductsRenewals</Mono> committer skips it, so its price freezes at the fossil or $0.
          </ChainStep>
          <ChainStep n="4" fix>
            <b>The fix:</b> stop discarding the owned line — <b>flip it to <Code>Renew</Code></b> and let the native engine
            apply the COLA uplift to last year’s net. No new pricing logic, no catalog change, no selling-model change.
          </ChainStep>
        </ol>

        <SecH>3 · The investigation — phase by phase</SecH>
        <ul style={{ counterReset: "ph", padding: 0 }}>
          <Phase n="1" h="Symptom triage & scope" d="Renewal-maintenance committing $60.64 / $0 vs the COLA-correct $67.38. COLA math verified correct; the value was not persisting to the line." />
          <Phase n="2" h="Two mechanisms separated" d="A1 (partner double-discount, posthook-version dependent) vs A2 (no priced node at all) — sequential, not competing. The earlier qty-based framing was tested and set aside." />
          <Phase n="3" h="Contributor model established" d="A derived renewal prices only from a contributor: the prior owned Asset surfaced via QuoteAction(Type=Renew).SourceAsset, matched by product. No contributor → the committer skips the line." />
          <Phase n="4" h="Reprice-time writes refuted (×3)" d="Direct NetUnitPrice write (read-only on insert), PartnerNetPricePosthook, and a procedure committer all returned success yet no-oped on a settled derived node." />
          <Phase n="5" h="Self-healing candidate rejected" d="The 'lever-d' procedure-commit change could self-heal existing fossils, but could not be proven to fire (the $67.38 in those logs was prehook-sourced, byte-identical across runs) → rejected as unproven/unsafe." />
          <Phase n="6" h="Born-net & PBEDP dead-ends" d="Hand-stamping a Renew QuoteAction after insert was too late (line settles at $0). Mapping the owned product as a price contributor (PBEDP) is platform-blocked — it is itself a derived product." />
          <Phase n="7" win h="Decisive E2E debug — root cause exposed" d="Running the real initiateRenewal with debug logging showed it emitting No Change / qty 0 for the One-Time maintenance asset — the line that never enters the COLA path. The fix writes itself: flip to Renew." />
        </ul>

        <SecH>4 · Why earlier fixes could not work — the dead-end ledger</SecH>
        <Table head={["Attempted lever", "Why it cannot work"]} rows={[
          [<>Write <Code>NetUnitPrice</Code> directly</>, <><Pill kind="bad">DEAD</Pill> engine-owned, read-only on insert</>],
          [<><Mono>PartnerNetPricePosthook</Mono> (reprice-time)</>, <><Pill kind="bad">DEAD</Pill> no-ops on a settled derived node</>],
          ["Procedure committer / RMPS (“lever-d”)", <><Pill kind="bad">DEAD</Pill> returns success but could not be proven to fire; value was prehook-sourced</>],
          ["Map owned product as contributor (PBEDP)", <><Pill kind="bad">DEAD</Pill> platform-blocked — it is a derived product</>],
          [<>Hand-attach a <Code>Renew</Code> QuoteAction <i>after</i> insert</>, <><Pill kind="bad">DEAD</Pill> too late; line settles un-priced and locks at $0</>],
          ["Re-model the catalog (merge RNM/RRM)", <><Pill kind="warn">UNNEEDED</Pill> far higher blast radius; the flip achieves the same outcome</>],
        ]} />
        <Note>
          <b>The unifying insight:</b> every dead-end tried to <i>write the price</i>. None supplied the one thing the
          engine needs — a <Code>Renew</Code> line with a contributor. The fix does exactly that and lets the native engine compute and commit.
        </Note>

        <SecH>5 · The fix — design, code & wiring</SecH>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
          <Card title={<>Apex · <Mono>RenewalMaintenanceFlip</Mono></>}>
            Selects renewal-quote lines that are owned-maintenance carryover stuck on <Code>No Change</Code>, and flips them:
            <ul style={{ margin: "6px 0 0 18px" }}>
              <li><Code>QuoteAction.Type</Code> → <Code>Renew</Code></li>
              <li>line <Code>StartQuantity = 0</Code>, <Code>Quantity = SourceAsset.Quantity</Code></li>
              <li>bulk-safe, idempotent, null/empty-safe</li>
              <li><Code>@InvocableMethod</Code> for clean Flow binding</li>
            </ul>
            <p style={{ marginTop: 8 }}><Pill kind="ok">DEPLOYED</Pill> API 64 · <G>4/4 tests pass</G> · <G>100% class coverage</G></p>
          </Card>
          <Card title={<>Flow · <Mono>Fortra_Create_Renewal_Quote</Mono></>}>
            Wired so every renewal automatically runs <b>flip → reprice</b>:
            <div style={{ fontFamily: "ui-monospace,Menlo,monospace", fontSize: 12.5, background: C.bg,
              border: `1px solid ${C.line}`, borderRadius: 10, padding: "11px 13px", marginTop: 8, lineHeight: 1.85 }}>
              initiate renewal <span style={{ color: C.mut2 }}>→</span> populate dates <span style={{ color: C.mut2 }}>→</span><br />
              <span style={{ color: C.amber }}>Flip Maintenance</span> (apex) <span style={{ color: C.mut2 }}>→</span>{" "}
              <span style={{ color: C.amber }}>Reprice</span> (subflow) <span style={{ color: C.mut2 }}>→</span>{" "}
              <span style={{ color: C.green }}>$67.38 committed</span>
            </div>
            <p style={{ marginTop: 9 }}>Reprice = Place Sales Transaction, <Code>pricingPref:Force</Code>, <Code>configurationPref:{"{configurationMethod:Skip}"}</Code>.</p>
          </Card>
        </div>

        <SecH>6 · End-to-end validation (fresh live run, 2026-06-14)</SecH>
        <Table head={["Stage", <>Owned maintenance line · <Mono>PIA-PIA-RNM-PIAMBK</Mono></>]} rows={[
          [<><Code>initiateRenewal</Code> → before flip</>, <><Pill kind="warn">No Change</Pill> qty 0 · StartQty 1 · <b>Net = null</b> · QA = No Change <span style={{ color: C.mut2 }}>← root cause reproduced live</span></>],
          [<>after <Mono>flipToRenew</Mono></>, <><Pill kind="info">Renew</Pill> qty 1 · StartQty 0 · Net still null</>],
          ["after Force/Skip reprice", <><Pill kind="ok">Renew</Pill> qty 1 · <G>Net = 67.38</G> · NetTotal 67.38 · Uplift 7.85% · QA = Renew</>],
        ]} />
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16, marginTop: 14 }}>
          <Card title="Survival — all-lines proof">
            An unfiltered query of <b>every</b> line on the renewal quote returned <G>exactly 1 line, 0 RRM lines</G>.
            The flipped owned line is the sole, correctly-priced maintenance line — no asset-less substitute survived.
          </Card>
          <Card title="Rollup — header not stale">
            Quote header totals all reconcile to the line: <Mono>Subtotal = TotalPrice = GrandTotal = ALE = 67.38</Mono>,
            LineItemCount 1. The original business symptom (a stale total) cannot re-surface.
          </Card>
        </div>
        <Note>
          <b>Native-engine commit confirmed.</b> The custom <Code>COLACalculatedPrice__c</Code> field read <b>0</b> on the
          settled line while <Code>NetUnitPrice = 67.38</Code> — proving the <i>platform</i> renewal uplift committed the
          value once the line became a <Code>Renew</Code> node, not a custom Apex write. Downstream (Workday line-type,
          billing dates, ARR) is independent of the maintenance-type split. Test data was deleted; the canary asset remains intact at $62.48.
        </Note>

        <SecH>7 · Honest caveats & scope</SecH>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
          <Card title="Forward-only fix">
            The flip corrects renewals <b>as they are generated</b> (the wired flow / on-demand <Mono>flipToRenew</Mono>).
            It does <b>not</b> retroactively heal already-settled fossil lines on pre-existing Draft quotes — those need a separate remediation reprice.
          </Card>
          <Card title="Known residuals to confirm">
            <ul style={{ margin: "0 0 0 18px" }}>
              <li>The exact platform reason a direct <Code>NetUnitPrice</Code> write no-ops is empirically strong (reproduced 3×) but not mechanistically pinned.</li>
              <li>The 7.85% rate comes from a COLA-rate custom metadata rule; the exact record was not re-pinned this pass — verify before prod.</li>
            </ul>
          </Card>
        </div>

        <SecH>8 · Before production promotion</SecH>
        <Card>
          Two verify-before-prod items carry forward: <b>re-pin the 7.85% BoKS COLA rate</b> to its{" "}
          <Code>Maintenance_Rate__mdt</Code> record (a known orphan-“platinum” rule exists elsewhere in this catalog),
          and <b>resolve the pre-existing <Code>COLAUpliftTest.buildOverrideMap</Code> coverage drift</b> (a separate
          test-suite issue that gates any procedure-side validate). A single production renewal smoke-test then confirms
          the flip + reprice commits <b>$67.38</b> end to end.
        </Card>

        <div style={{ marginTop: 30, color: "#6e7681", fontSize: 12, textAlign: "center",
          borderTop: `1px solid ${C.line2}`, paddingTop: 16 }}>
          FortraUAT (00DWC000006eUFF2A2) · canary asset 02iWC000008DmS1YAK · tests 4/4 + 100% class coverage · E2E
          all-lines + header-rollup verified · no Orders activated, no Workday events, Accepted quote 00781068 untouched ·
          test data cleaned, canary intact · companion detail in the full MD
        </div>

      </div>
    </div>
  );
}
