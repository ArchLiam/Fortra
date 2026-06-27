/**
 * SC-3354 — COLA Pricing: Renewal Quotes Not Priced Correctly (Peer Review)
 * High-visibility React mirror of SC-3354_PEER_REVIEW.html.
 * Self-contained: inline styles, no external CSS/deps. Default-exported.
 *
 *   <SC3354PeerReview />
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

const SecH = ({ children }) => (
  <div style={{ fontSize: 12.5, letterSpacing: "2px", textTransform: "uppercase", color: C.mut2,
    fontWeight: 800, margin: "42px 0 14px" }}>{children}</div>
);

const Card = ({ title, accent, children }) => (
  <div style={{ background: C.card, border: `1px solid ${C.line}`,
    borderLeft: accent ? `4px solid ${accent}` : `1px solid ${C.line}`,
    borderRadius: 14, padding: "20px 22px", marginBottom: 14 }}>
    {title && <h3 style={{ fontSize: 16.5, margin: "0 0 6px", color: "#fff", display: "flex",
      alignItems: "center", gap: 10, flexWrap: "wrap" }}>{title}</h3>}
    <div style={{ fontSize: 14.5, color: "#adbac7" }}>{children}</div>
  </div>
);

const Pill = ({ kind, children }) => {
  const m = {
    bad: { color: C.red, background: C.redD },
    warn: { color: C.amber, background: C.amberD },
    ok: { color: C.greenL, background: C.greenD },
  }[kind];
  return <span style={{ display: "inline-block", fontSize: 10.5, fontWeight: 800, padding: "2px 9px",
    borderRadius: 20, letterSpacing: ".3px", textTransform: "uppercase", ...m }}>{children}</span>;
};

const KPI = ({ n, l, color }) => (
  <div style={{ flex: 1, minWidth: 165, background: C.card, border: `1px solid ${C.line}`,
    borderRadius: 13, padding: "17px 16px", textAlign: "center" }}>
    <div style={{ fontSize: 30, fontWeight: 850, lineHeight: 1.05, color }}>{n}</div>
    <div style={{ fontSize: 11, letterSpacing: ".6px", textTransform: "uppercase", color: C.mut2,
      marginTop: 7, fontWeight: 600 }}>{l}</div>
  </div>
);

const Table = ({ head, rows, align = [] }) => (
  <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 14, marginTop: 4 }}>
    <thead><tr>{head.map((h, i) => (
      <th key={i} style={{ textAlign: align[i] === "r" ? "right" : "left", padding: "9px 11px", fontSize: 10.5,
        letterSpacing: "1px", textTransform: "uppercase", color: C.mut2, borderBottom: `2px solid ${C.line}`,
        fontWeight: 700 }}>{h}</th>))}</tr></thead>
    <tbody>{rows.map((r, ri) => (
      <tr key={ri}>{r.map((c, ci) => (
        <td key={ci} style={{ padding: "10px 11px", borderBottom: `1px solid ${C.line2}`, verticalAlign: "top",
          color: "#c9d1d9", textAlign: align[ci] === "r" ? "right" : "left",
          fontVariantNumeric: align[ci] === "r" ? "tabular-nums" : "normal",
          fontFamily: align[ci] === "r" ? "ui-monospace,monospace" : "inherit" }}>{c}</td>))}</tr>))}
    </tbody>
  </table>
);

const Step = ({ when, children, tone }) => {
  const dot = tone === "bad" ? C.red : tone === "ok" ? C.green : C.mut2;
  return (
    <div style={{ position: "relative", padding: "0 0 16px 26px", borderLeft: `2px solid ${C.line}` }}>
      <div style={{ position: "absolute", left: -7, top: 2, width: 12, height: 12, borderRadius: "50%",
        background: dot, border: `2px solid ${dot}` }} />
      <div style={{ fontSize: 11.5, letterSpacing: ".5px", textTransform: "uppercase", color: C.mut2, fontWeight: 700 }}>{when}</div>
      <div style={{ fontSize: 14, color: "#c9d1d9", marginTop: 2 }}>{children}</div>
    </div>
  );
};

const Rec = ({ tag, tone, children }) => {
  const t = { 0: { color: "#fff", background: "#9e1c24" }, 1: { color: "#1a1205", background: C.amber },
    2: { color: "#cfe", background: "#173a52" } }[tone];
  return (
    <div style={{ display: "flex", gap: 14, alignItems: "flex-start", padding: "13px 0",
      borderBottom: `1px solid ${C.line2}` }}>
      <span style={{ flex: "0 0 auto", fontSize: 11, fontWeight: 900, padding: "3px 10px", borderRadius: 7,
        marginTop: 1, ...t }}>{tag}</span>
      <div style={{ fontSize: 14.5, color: "#d7dee6" }}>{children}</div>
    </div>
  );
};

const Z = () => <span style={{ color: C.red, fontWeight: 800 }}>0</span>;

export default function SC3354PeerReview() {
  return (
    <div style={{ background: C.bg, color: C.text, minHeight: "100vh",
      fontFamily: '-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif', lineHeight: 1.55 }}>
      <div style={{ maxWidth: 1040, margin: "0 auto", padding: "38px 26px 80px" }}>

        <h1 style={{ fontSize: 27, margin: "0 0 4px", letterSpacing: "-.3px" }}>
          Peer Review — COLA Pricing: Renewal Quotes Not Priced Correctly</h1>
        <div style={{ color: C.mut, fontSize: 13.5, marginBottom: 26 }}>
          Board ticket <b style={{ color: "#c9d1d9" }}>SC-3350</b> · Peer-review subtask{" "}
          <b style={{ color: "#c9d1d9" }}>SC-3354</b> · Org <b style={{ color: "#c9d1d9" }}>FortraUAT</b>{" "}
          <Mono>00DWC000006eUFF2A2</Mono> · <b style={{ color: "#c9d1d9" }}>2026-06-26</b> · Method: read-only
          (12-agent verification + independent confirm, zero org mutation)
        </div>

        {/* VERDICT */}
        <div style={{ display: "flex", alignItems: "center", gap: 22, flexWrap: "wrap",
          background: "linear-gradient(110deg,#23121420,#2a141680)", border: "1px solid #5b2326",
          borderLeft: `6px solid ${C.red}`, borderRadius: 16, padding: "22px 26px", margin: "6px 0 4px" }}>
          <div style={{ fontSize: 34, fontWeight: 900, color: C.red, letterSpacing: ".5px", whiteSpace: "nowrap" }}>
            <span style={{ fontSize: 22, verticalAlign: "middle", marginRight: 8 }}>●</span>NO-GO</div>
          <p style={{ margin: 0, fontSize: 15, color: "#dfe6ee", flex: 1, minWidth: 280 }}>
            The SC-3350 <Mono>NetUnitPrice</Mono> seed — the only mechanism ever <i>proven</i> to commit the
            COLA-adjusted net to a non-derived license/subscription renewal line — was deleted from live when the
            co-owned <Mono>COLAUpliftPrehook</Mono> was reworked for <b>SC-3346</b>. No surviving live mechanism
            commits it. <b>Defect&nbsp;#1 reproduces at 100% on every renewal created since the rework.</b></p>
        </div>

        <div style={{ display: "flex", gap: 14, flexWrap: "wrap", margin: "18px 0 4px" }}>
          <KPI n="9 / 9" l="Fresh renewals at $0" color={C.red} />
          <KPI n="100%" l="Post-rework failure" color={C.red} />
          <KPI n="26%" l={'"Correct" — all stale residue'} color={C.amber} />
          <KPI n="~36%" l="Renewal lines · null description" color={C.amber} />
          <KPI n="125/125" l="Tests green · 0 net-commit asserts" color={C.greenL} />
        </div>

        {/* REGRESSION */}
        <SecH>The regression — how the fix disappeared</SecH>
        <Card>
          <div style={{ margin: "2px 0 14px" }}>
            <Step when="2026-06-09 / 10" tone="ok">
              Dossier review = NO-GO. The $0-net root cause is cracked: on a non-derived renewal line, only a{" "}
              <b>direct</b> <Mono>NetUnitPrice</Mono> write in an isolated <Mono>updateContextAttributes</Mono>{" "}
              batch commits — a ListGroup Formula/Assignment write does not.
            </Step>
            <Step when="2026-06-11 ~01:00Z — fix deployed & working" tone="ok">
              <Mono>COLAUpliftPrehook</Mono> seed added (<Mono>buildNetUnitPriceUpdate</Mono> /{" "}
              <Mono>pendingNetUnitPriceUpdates</Mono>). Proven live: quote <Mono>0Q0WC000003671t0AA</Mono>{" "}
              net <b>$0 → 4697.95 / 929.25</b>, GrandTotal <b>$0 → $5,627.20</b>.
            </Step>
            <Step when="2026-06-13 / 14 — silent clobber" tone="bad">
              The <b>same class</b> is reworked for a <b>different ticket, SC-3346</b> (renewal-maintenance),
              realigned to a "v1.1" baseline. <b>The SC-3350 net-seed is deleted entirely.</b> Green tests miss it.
            </Step>
            <Step when="2026-06-26 — this review" tone="bad">
              Live <Mono>COLAUpliftPrehook</Mono> = 1378 L, <Mono>@version 1.1</Mono>; grep = <b>0</b> for{" "}
              <Mono>NetUnitPrice</Mono> / <Mono>buildNetUnitPriceUpdate</Mono> / <Mono>seed</Mono> / <Mono>SC-3350</Mono>.
              For renewals it now writes only audit attrs — never the net. Defect&nbsp;#1 is back.
            </Step>
          </div>
          <div style={{ background: C.card2, border: `1px solid ${C.line}`, borderLeft: `4px solid ${C.amber}`,
            borderRadius: 10, padding: "14px 18px", fontSize: 14, color: "#cdd6df" }}>
            <b>Why V16 doesn't save it:</b> the active procedure <Mono>Rev_Mgmt_Default_Pricing_Procedure V16</Mono>{" "}
            has a step "COLA Uplift Net on Renewal" (<Mono>COLACalculatedPrice__c → NetUnitPrice</Mono>), correctly
            gated — but it lives inside <Mono>ListContainer2</Mono>, the exact ListGroup scope proven unable to flush
            a <Mono>NetUnitPrice</Mono> write. The one quote that still prices correctly
            (<Mono>0Q0WC000003671t0AA</Mono>) is a <b>frozen 06-11 residue</b>, not a live reprice.
          </div>
        </Card>

        {/* DEFECTS */}
        <SecH>Defect status</SecH>

        <Card title={<>Defect&nbsp;#1 — priced at $0 / list instead of prior × (1 + COLA%) <Pill kind="bad">FAIL · blocker</Pill></>}>
          <p style={{ margin: "8px 0" }}>COLA computes correctly into <Mono>UnitPrice</Mono> /{" "}
            <Mono>COLACalculatedPrice__c</Mono>; it simply never commits to <Mono>NetUnitPrice</Mono>.
            Confirmed live + independently re-queried:</p>
          <Table
            head={["Line", "Product", "Created", "Computed", "NetUnitPrice"]}
            align={["", "", "", "r", "r"]}
            rows={[
              [<Mono>0QLWC000003eofV4AQ</Mono>, "EFT 8 Enterprise", "06-15",
                <span style={{ color: C.greenL }}>18,192.57</span>, <Z />],
              [<Mono>0QLWC000003g2uw4AA</Mono>, "Outflank (OST)", "06-18",
                <span style={{ color: C.greenL }}>10,089.00</span>, <Z />],
              [<Mono>0QLWC000003g4Ld4AI</Mono>, "Active Defense BEC", "06-18",
                <span style={{ color: C.greenL }}>98,700.00</span>, <Z />],
              [<Mono>0QLWC000003iZ0M4AU</Mono>, "beSECURE — Cloud-Based", "06-24",
                <span style={{ color: C.greenL }}>7,110.41</span>, <Z />],
            ]} />
          <p style={{ margin: "12px 0 0" }}><b>Not a "drafts not yet repriced" artifact:</b> quote{" "}
            <Mono>0Q0WC0000039cfR0AQ</Mono> is <b>Status = Accepted, GrandTotal = $0.00</b>. The dossier's own repro
            line <Mono>0QLWC000003bHpl4AE</Mono> is also broken now.</p>
          <p style={{ color: C.mut, margin: "8px 0 0" }}>Buckets across all 58 non-maintenance renewal lines:
            ZERO 19 (33%) · CORRECT 15 (26%, all ≤ 06-07 frozen residue) · AT-LIST 10 (17%) · NET-NULL 7 (12%) ·
            OTHER 5 (9%) · NET=CALC 2 (3%). Nothing created/repriced after the 06-14 seed removal is correct.</p>
        </Card>

        <Card title={<>Defect&nbsp;#2 — Line Item Description not populated on renewals <Pill kind="warn">FAIL · high</Pill></>}>
          <p style={{ margin: "8px 0" }}><Mono>QLDescriptionGeneratorPrehook</Mono> (live <Mono>@version 8.0</Mono>)
            has zero renewal awareness and no self-triggered reprice — it writes a description only when an external
            reprice happens to run the line through it. <b>~36%</b> of attribute-bearing renewal lines ship null
            (feeds the quote PDF).</p>
          <Table head={["Cohort (post-fix window)", "Description populated"]} align={["", "r"]}
            rows={[
              ["Regular Add", "82.9%"],
              ["Amend", "78.6%"],
              [<b>Renew</b>, <b style={{ color: C.amber }}>56.3%</b>],
            ]} />
          <p style={{ color: C.mut, margin: "10px 0 0" }}>Cleanest repro: four 06-24 beSECURE renewals with the full
            attribute set — the one re-saved 48 min after creation got a description; the three never-repriced stayed
            null. Gap is broader than renewals — fix the orchestration, not just the renewal branch.</p>
        </Card>

        {/* BLOCKERS */}
        <SecH>Blockers — verification-upheld only</SecH>
        <Table head={["#", "Issue", "Sev", "Blocks"]}
          rows={[
            [<Mono>B-1</Mono>, "No live mechanism commits the COLA'd net for non-derived renewals — Apex seed removed; V16 net step inert in ListGroup scope", <Pill kind="bad">blocker</Pill>, <Z2>Yes</Z2>],
            [<Mono>B-2</Mono>, <>Defect&nbsp;#1 reproduces: 9/9 fresh post-rework renewals commit <Mono>NetUnitPrice=0</Mono>; one already Accepted at GrandTotal $0</>, <Pill kind="bad">blocker</Pill>, <Z2>Yes</Z2>],
            [<Mono>B-3</Mono>, "Defect #2 reproduces: ~36% of attribute-bearing renewal lines ship null Line Item Description", <Pill kind="warn">high</Pill>, <Z2>Yes</Z2>],
            [<Mono>B-4</Mono>, "Not promotable from force-app: 0/5 COLA Apex classes staged; both CMDT types + 22 records absent", <Pill kind="bad">blocker</Pill>, <Z2>Yes</Z2>],
            [<Mono>B-5</Mono>, <><Mono>COLA_Source__c</Mono> in force-app is restricted, missing <Mono>MyCAP Default</Mono> (10 live rows) → restricted-picklist deploy error</>, <Pill kind="bad">blocker</Pill>, <Z2>Yes</Z2>],
            [<Mono>B-6</Mono>, "Prehook catch returns SUCCESS on any exception → COLA failures are silent", <Pill kind="warn">high</Pill>, <Z2>Yes</Z2>],
            [<Mono>B-7</Mono>, "Rule match is Solution-Category grain (spec = Solution-Name): 2 wrong rates, ~34 products", <Pill kind="warn">high</Pill>, <Z2>Yes</Z2>],
          ]} />

        {/* REFUTED */}
        <SecH>Refuted / downgraded during verification — do not carry forward</SecH>
        <Card>
          <div style={{ opacity: 0.66 }}>
            <p style={{ margin: "6px 0" }}><Pill kind="ok">closed</Pill> &nbsp;<b>B8 — TEMP BoKS strands ~17 products.</b>{" "}
              "Powertech IAM BoKS" is a permanent, spec-conformant rule at 7.85; 17 products correctly served.</p>
            <p style={{ margin: "6px 0" }}><Pill kind="ok">out of scope</Pill> &nbsp;<b>Out-year / MyCAP / multi-year COLA.</b>{" "}
              Spec is single-year; broken inert <Mono>Final_Year_COLA_Calculated_Price__c</Mono> = cleanup, not a defect.</p>
            <p style={{ margin: "6px 0" }}><Pill kind="ok">overstated</Pill> &nbsp;<b>"~77% uncommitted".</b>{" "}
              Conflated 89 SC-3346 maintenance/derived lines. True SC-3350 figure = ~28% all-time,{" "}
              <b>100% on fresh post-rework lines</b> (the decisive number).</p>
            <p style={{ margin: "6px 0" }}><Pill kind="ok">false</Pill> &nbsp;<b>"Quote/QLI not queryable via{" "}
              <Mono>sf data query</Mono>".</b> Cosmetic method error — all three objects query fine.</p>
          </div>
        </Card>

        {/* RECOMMENDATIONS */}
        <SecH>Recommended actions for the author</SecH>
        <Card>
          <Rec tag="P0" tone={0}><b>Restore the committed-net path</b> (closes B-1/B-2). Re-add the proven Apex{" "}
            <Mono>NetUnitPrice</Mono> seed (with the stored-net &gt; 0 guard) <i>or</i> move the V16 net step out of{" "}
            <Mono>ListContainer2</Mono>. <b>Validate on a fresh reprice</b> — never against the frozen{" "}
            <Mono>0Q0WC000003671t0AA</Mono> quote.</Rec>
          <Rec tag="P0" tone={0}><b>Guarantee a reprice (or direct write) on the renewal path</b> (closes B-3) so
            descriptions populate. Fix the orchestration, not just the renewal branch.</Rec>
          <Rec tag="P0" tone={0}><b>Close packaging gaps before any promotion</b> (closes B-4/B-5): stage the 5
            reconciled COLA classes + CMDT type & 22 records; add <Mono>MyCAP Default</Mono> to the force-app{" "}
            <Mono>COLA_Source__c</Mono> picklist; promote V16 via deactivate→deploy→reactivate, not the stale file.</Rec>
          <Rec tag="P1" tone={1}><b>Surface COLA failures instead of swallowing them</b> (closes B-6) — replace the
            unconditional SUCCESS in the catch block.</Rec>
          <Rec tag="P1" tone={1}><b>Decide the rule-match grain</b> (closes B-7) — re-key from{" "}
            <Mono>Solution_Category__c</Mono> to Solution-Name. Design call (Marc / German) — escalate.</Rec>
          <Rec tag="P2" tone={2}><b>Add an end-to-end net-commit test</b> — insert a renewal QLI, reprice, assert
            persisted <Mono>NetUnitPrice == prior × (1 + COLA%)</Mono>. The green suite never asserts a committed
            net, which is exactly why this regression shipped.</Rec>
          <Rec tag="P2" tone={2}><b>Latent / cleanup</b> — fix <Mono>AssetContractQueryHelper</Mono> multi-asset
            collapse (key by <Mono>(ContractId, AssetId)</Mono>); remove the broken inert out-year field.</Rec>
        </Card>

        <div style={{ background: C.card2, border: `1px solid ${C.line}`, borderLeft: `4px solid ${C.red}`,
          borderRadius: 10, padding: "14px 18px", fontSize: 14, color: "#cdd6df", marginTop: 22 }}>
          <b>Root lesson for the team:</b> SC-3350 and SC-3346 co-own <Mono>COLAUpliftPrehook</Mono>. The SC-3346
          rework silently overwrote the SC-3350 fix, and with no test asserting a committed net, the green build hid it.
        </div>

        <div style={{ marginTop: 46, paddingTop: 18, borderTop: `1px solid ${C.line}`, fontSize: 12.5, color: C.mut2 }}>
          All findings independently re-verified against live FortraUAT (read-only — <Mono>sf data query</Mono>,{" "}
          <Mono>sf project retrieve</Mono>, <Mono>sf apex run test</Mono>; zero DML/deploy). The NO-GO is driven by
          B-1/B-2: the proven commit mechanism is gone and 100% of fresh renewals price the COLA net at $0. · Source
          report: <Mono>Data/sc3354/SC-3354_PEER_REVIEW_2026-06-26.md</Mono>.
        </div>

      </div>
    </div>
  );
}

/* Small helper: red "Yes" cell for the blockers table. */
function Z2({ children }) {
  return <span style={{ color: "#ff7b72", fontWeight: 800 }}>{children}</span>;
}
