import React from "react";

const RESULTS = [
  { id: "NB-PERP", domain: "New-business pricing", title: "Perpetual/License net pricing — List x partner x discretionary", status: "pass", severity: "none", isKnownIssue: false, ticket: "" },
  { id: "NB-MAINT", domain: "New-business pricing", title: "Maintenance derived pricing + auto-add first-year maintenance (SC-3346)", status: "fail", severity: "high", isKnownIssue: true, ticket: "SC-3372" },
  { id: "NB-SVC", domain: "New-business pricing", title: "Services-only USD new-business quote prices at catalog", status: "pass", severity: "none", isKnownIssue: false, ticket: "" },
  { id: "NB-HW", domain: "New-business pricing", title: "Hardware attribute pricing (Powertech pGroup/userTier/systemType)", status: "partial", severity: "medium", isKnownIssue: false, ticket: "" },
  { id: "NB-TIER", domain: "New-business pricing", title: "Tiered / attribute-volume pricing (SC-3390): tier resolves, committed net $0", status: "fail", severity: "high", isKnownIssue: true, ticket: "SC-3384" },
  { id: "NB-BUNDLE", domain: "New-business pricing", title: "Bundle / product configuration rule pricing", status: "partial", severity: "high", isKnownIssue: true, ticket: "SC-3384" },
  { id: "RN-LIC", domain: "Renewal pricing", title: "Renewal license COLA uplift", status: "pass", severity: "none", isKnownIssue: false, ticket: "" },
  { id: "RN-MAINT", domain: "Renewal pricing", title: "Renewal maintenance COLA net commits stale value (SC-3404)", status: "fail", severity: "high", isKnownIssue: true, ticket: "SC-3404" },
  { id: "RN-SUB", domain: "Renewal pricing", title: "Renewal subscription pricing — catalog net + partner margin", status: "pass", severity: "none", isKnownIssue: false, ticket: "" },
  { id: "AMEND", domain: "Renewal pricing", title: "Amendment quote pricing", status: "pass", severity: "none", isKnownIssue: false, ticket: "" },
  { id: "MOD-PART12", domain: "Pricing modifiers", title: "Partner discount 12% model (renewal-maintenance lines)", status: "fail", severity: "high", isKnownIssue: true, ticket: "SC-3404" },
  { id: "MOD-PART15", domain: "Pricing modifiers", title: "Partner discount 15% model", status: "pass", severity: "none", isKnownIssue: false, ticket: "" },
  { id: "MOD-QDISC", domain: "Pricing modifiers", title: "Quote-level discount (% and amount; equal/proportionate distribution)", status: "partial", severity: "medium", isKnownIssue: false, ticket: "" },
  { id: "MOD-LDISC", domain: "Pricing modifiers", title: "Line-level (partner) + discretionary discount on Quote lines", status: "fail", severity: "high", isKnownIssue: true, ticket: "SC-3359" },
  { id: "MOD-CUR-AUD", domain: "Pricing modifiers", title: "Multi-currency AUD (rate 1.52) net not scaled by conversion rate", status: "fail", severity: "high", isKnownIssue: true, ticket: "SC-3384" },
  { id: "MOD-CUR-EUR", domain: "Pricing modifiers", title: "Multi-currency EUR (rate 0.92) configured pricing uses USD values", status: "fail", severity: "high", isKnownIssue: true, ticket: "SC-3384" },
  { id: "MOD-CUR-USDONLY", domain: "Pricing modifiers", title: "Non-USD configured product uses USD values + JPY 1.0-rate corruption", status: "fail", severity: "high", isKnownIssue: true, ticket: "SC-3384" },
  { id: "MOD-REGION", domain: "Pricing modifiers", title: "Regional services pricing (Italy 0.64 multiplier, CEILING/5)", status: "fail", severity: "high", isKnownIssue: false, ticket: "" },
  { id: "TOT-CONSIST", domain: "Totals & rollups", title: "NetUnitPrice/NetTotal/Subtotal/GrandTotal consistency (multi-line)", status: "partial", severity: "medium", isKnownIssue: true, ticket: "SC-3345" },
  { id: "TOT-ALE", domain: "Totals & rollups", title: "ALE formula + Services category aggregate + stale-aggregate (SC-3345)", status: "pass", severity: "none", isKnownIssue: false, ticket: "" },
  { id: "QO-CONVERT", domain: "Quote-to-Order", title: "Convert Draft quote to Order (non-activating) + field mapping", status: "pass", severity: "none", isKnownIssue: false, ticket: "" },
  { id: "QO-PRICEPARITY", domain: "Quote-to-Order", title: "Order pricing parity vs source quote (net carries correctly)", status: "fail", severity: "high", isKnownIssue: true, ticket: "SC-3359" },
  { id: "QO-DECOMP", domain: "Quote-to-Order", title: "Order line decomposition / maintenance split — Source_List_Price carry-through", status: "pass", severity: "none", isKnownIssue: false, ticket: "SC-3346" },
  { id: "VAL-REQ", domain: "Validation", title: "Required-fields-for-submission completeness (SC-3338)", status: "pass", severity: "none", isKnownIssue: false, ticket: "" },
  { id: "VAL-SUBMIT", domain: "Validation", title: "Order submission required-field validation (SC-3291)", status: "pass", severity: "none", isKnownIssue: false, ticket: "SC-3291" },
  { id: "CFG-AUTOMAINT", domain: "Configuration", title: "Auto-add first-year maintenance config rule fires on add", status: "pass", severity: "low", isKnownIssue: false, ticket: "SC-3372" },
  { id: "DOC-PDF", domain: "DocGen", title: "Quote PDF generation: pricing + line descriptions content (SC-3335/3349)", status: "pass", severity: "none", isKnownIssue: false, ticket: "SC-3335 / SC-3349" },
];

const STATUS_COLORS = {
  pass: { bg: "#e6f4ea", fg: "#1e7e34", border: "#9bd3ac" },
  fail: { bg: "#fdecea", fg: "#c0271a", border: "#f0a7a0" },
  partial: { bg: "#fff4e0", fg: "#b56a00", border: "#f3cf94" },
  blocked: { bg: "#eceff1", fg: "#455a64", border: "#b0bec5" },
};

const SEVERITY_COLORS = {
  critical: { bg: "#7a0c00", fg: "#ffffff" },
  high: { bg: "#fdecea", fg: "#c0271a", border: "#f0a7a0" },
  medium: { bg: "#fff4e0", fg: "#b56a00", border: "#f3cf94" },
  low: { bg: "#eef6ff", fg: "#1565c0", border: "#bcdcff" },
  none: { bg: "#f2f3f5", fg: "#8a8f98", border: "#dfe2e6" },
};

const DOMAIN_ORDER = [
  "New-business pricing",
  "Renewal pricing",
  "Pricing modifiers",
  "Totals & rollups",
  "Quote-to-Order",
  "Validation",
  "Configuration",
  "DocGen",
];

const SEV_RANK = { critical: 0, high: 1, medium: 2, low: 3, none: 4 };

function StatusPill({ status }) {
  const c = STATUS_COLORS[status] || STATUS_COLORS.blocked;
  return (
    <span
      style={{
        display: "inline-block",
        minWidth: 64,
        textAlign: "center",
        padding: "3px 10px",
        borderRadius: 12,
        fontSize: 11,
        fontWeight: 700,
        letterSpacing: 0.4,
        textTransform: "uppercase",
        background: c.bg,
        color: c.fg,
        border: `1px solid ${c.border}`,
      }}
    >
      {status}
    </span>
  );
}

function SeverityPill({ severity }) {
  const c = SEVERITY_COLORS[severity] || SEVERITY_COLORS.none;
  return (
    <span
      style={{
        display: "inline-block",
        padding: "2px 8px",
        borderRadius: 10,
        fontSize: 10,
        fontWeight: 700,
        letterSpacing: 0.3,
        textTransform: "uppercase",
        background: c.bg,
        color: c.fg,
        border: c.border ? `1px solid ${c.border}` : "none",
      }}
    >
      {severity}
    </span>
  );
}

function KpiCard({ label, value, accent, sub }) {
  return (
    <div
      style={{
        flex: "1 1 0",
        minWidth: 120,
        background: "#ffffff",
        border: "1px solid #e3e6ea",
        borderTop: `3px solid ${accent}`,
        borderRadius: 8,
        padding: "14px 16px",
        boxShadow: "0 1px 2px rgba(16,24,40,0.04)",
      }}
    >
      <div style={{ fontSize: 28, fontWeight: 800, color: "#1a2230", lineHeight: 1.1 }}>{value}</div>
      <div style={{ fontSize: 12, fontWeight: 600, color: "#5b636e", marginTop: 4, textTransform: "uppercase", letterSpacing: 0.5 }}>
        {label}
      </div>
      {sub ? <div style={{ fontSize: 11, color: "#8a8f98", marginTop: 2 }}>{sub}</div> : null}
    </div>
  );
}

export default function ExecutiveSummary() {
  const total = RESULTS.length;
  const counts = RESULTS.reduce(
    (acc, r) => {
      acc.status[r.status] = (acc.status[r.status] || 0) + 1;
      acc.severity[r.severity] = (acc.severity[r.severity] || 0) + 1;
      if (r.isKnownIssue) acc.known += 1;
      return acc;
    },
    { status: {}, severity: {}, known: 0 }
  );

  const passCount = counts.status.pass || 0;
  const failCount = counts.status.fail || 0;
  const partialCount = counts.status.partial || 0;
  const blockedCount = counts.status.blocked || 0;
  const knownCount = counts.known;
  const newDefectCount = RESULTS.filter((r) => !r.isKnownIssue && (r.status === "fail" || r.status === "partial")).length;
  const passRate = Math.round((passCount / total) * 100);

  // Overall health: green if mostly pass, amber if partials/known issues dominate, red if many fails
  let health, healthColor, healthNote;
  if (failCount === 0 && partialCount === 0) {
    health = "HEALTHY";
    healthColor = "#1e7e34";
    healthNote = "No failing or partial scenarios.";
  } else if (failCount > 0 && newDefectCount > 0) {
    health = "AT RISK";
    healthColor = "#c0271a";
    healthNote = `${failCount} failing scenario(s); ${newDefectCount} not attributed to a known issue.`;
  } else {
    health = "DEGRADED";
    healthColor = "#b56a00";
    healthNote = `${failCount} fail / ${partialCount} partial; ${knownCount} attributed to known issues.`;
  }

  const critical = RESULTS.filter((r) => r.severity === "critical" || r.severity === "high").sort(
    (a, b) => SEV_RANK[a.severity] - SEV_RANK[b.severity]
  );
  const knownIssues = RESULTS.filter((r) => r.isKnownIssue);

  const byDomain = DOMAIN_ORDER.map((d) => ({
    domain: d,
    rows: RESULTS.filter((r) => r.domain === d),
  })).filter((g) => g.rows.length > 0);

  const sectionTitle = {
    fontSize: 13,
    fontWeight: 800,
    letterSpacing: 0.6,
    textTransform: "uppercase",
    color: "#3a4250",
    margin: "0 0 12px 0",
  };

  return (
    <div
      style={{
        fontFamily:
          "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif",
        background: "#f6f7f9",
        color: "#1a2230",
        padding: "28px 24px",
        maxWidth: 1100,
        margin: "0 auto",
      }}
    >
      {/* Header */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", flexWrap: "wrap", gap: 12, marginBottom: 22 }}>
        <div>
          <div style={{ fontSize: 12, fontWeight: 700, color: "#8a8f98", letterSpacing: 1, textTransform: "uppercase" }}>
            RCA End-to-End Test Run — Executive Summary
          </div>
          <h1 style={{ fontSize: 26, fontWeight: 800, margin: "4px 0 0 0", color: "#101828" }}>
            Fortra Pricing & Quote-to-Order Validation
          </h1>
          <div style={{ fontSize: 13, color: "#5b636e", marginTop: 4 }}>
            Active pricing procedure <strong>Rev_Mgmt_Default_Pricing_Procedure V14</strong> · {total} scenarios across {byDomain.length} domains
          </div>
        </div>
        <div
          style={{
            background: "#ffffff",
            border: `1px solid ${healthColor}`,
            borderRadius: 10,
            padding: "12px 18px",
            textAlign: "center",
            minWidth: 160,
          }}
        >
          <div style={{ fontSize: 11, fontWeight: 700, color: "#8a8f98", letterSpacing: 0.8, textTransform: "uppercase" }}>
            Overall Health
          </div>
          <div style={{ fontSize: 22, fontWeight: 900, color: healthColor, marginTop: 2 }}>{health}</div>
          <div style={{ fontSize: 11, color: "#5b636e", marginTop: 4, maxWidth: 200 }}>{healthNote}</div>
        </div>
      </div>

      {/* KPI Row */}
      <div style={{ display: "flex", gap: 12, flexWrap: "wrap", marginBottom: 28 }}>
        <KpiCard label="Total Scenarios" value={total} accent="#475467" />
        <KpiCard label="Pass" value={passCount} accent="#1e7e34" sub={`${passRate}% pass rate`} />
        <KpiCard label="Fail" value={failCount} accent="#c0271a" />
        <KpiCard label="Partial" value={partialCount} accent="#b56a00" />
        <KpiCard label="Blocked" value={blockedCount} accent="#607d8b" />
        <KpiCard label="Known Issues" value={knownCount} accent="#1565c0" sub={`${newDefectCount} new / unattributed`} />
      </div>

      {/* Results by domain */}
      <div style={{ marginBottom: 30 }}>
        <h2 style={sectionTitle}>Results by Domain</h2>
        <div style={{ background: "#ffffff", border: "1px solid #e3e6ea", borderRadius: 8, overflow: "hidden" }}>
          <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
            <thead>
              <tr style={{ background: "#f0f2f5", textAlign: "left" }}>
                <th style={{ padding: "8px 12px", fontWeight: 700, color: "#5b636e", width: 110 }}>ID</th>
                <th style={{ padding: "8px 12px", fontWeight: 700, color: "#5b636e" }}>Scenario</th>
                <th style={{ padding: "8px 12px", fontWeight: 700, color: "#5b636e", width: 96 }}>Status</th>
                <th style={{ padding: "8px 12px", fontWeight: 700, color: "#5b636e", width: 90 }}>Severity</th>
                <th style={{ padding: "8px 12px", fontWeight: 700, color: "#5b636e", width: 130 }}>Ticket</th>
              </tr>
            </thead>
            <tbody>
              {byDomain.map((group) => (
                <React.Fragment key={group.domain}>
                  <tr>
                    <td
                      colSpan={5}
                      style={{
                        background: "#eef1f5",
                        padding: "6px 12px",
                        fontWeight: 800,
                        fontSize: 11,
                        letterSpacing: 0.6,
                        textTransform: "uppercase",
                        color: "#3a4250",
                        borderTop: "1px solid #dfe3e8",
                      }}
                    >
                      {group.domain}{" "}
                      <span style={{ fontWeight: 600, color: "#8a8f98" }}>
                        ({group.rows.filter((r) => r.status === "pass").length}/{group.rows.length} pass)
                      </span>
                    </td>
                  </tr>
                  {group.rows.map((r) => (
                    <tr key={r.id} style={{ borderTop: "1px solid #eef0f3" }}>
                      <td style={{ padding: "8px 12px", fontFamily: "ui-monospace, Menlo, monospace", fontSize: 12, fontWeight: 700, color: "#344054" }}>
                        {r.id}
                      </td>
                      <td style={{ padding: "8px 12px", color: "#1a2230" }}>
                        {r.title}
                        {r.isKnownIssue ? (
                          <span style={{ marginLeft: 8, fontSize: 10, fontWeight: 700, color: "#1565c0", background: "#eef6ff", border: "1px solid #bcdcff", borderRadius: 8, padding: "1px 6px" }}>
                            KNOWN
                          </span>
                        ) : null}
                      </td>
                      <td style={{ padding: "8px 12px" }}>
                        <StatusPill status={r.status} />
                      </td>
                      <td style={{ padding: "8px 12px" }}>
                        <SeverityPill severity={r.severity} />
                      </td>
                      <td style={{ padding: "8px 12px", fontSize: 12, color: r.ticket ? "#344054" : "#b0b5bd" }}>
                        {r.ticket || "—"}
                      </td>
                    </tr>
                  ))}
                </React.Fragment>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Two-column: critical findings + known issues */}
      <div style={{ display: "flex", gap: 20, flexWrap: "wrap" }}>
        {/* Critical findings */}
        <div style={{ flex: "1 1 440px", minWidth: 320 }}>
          <h2 style={sectionTitle}>Critical & High-Severity Findings ({critical.length})</h2>
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            {critical.map((r) => (
              <div
                key={r.id}
                style={{
                  background: "#ffffff",
                  border: "1px solid #e3e6ea",
                  borderLeft: `4px solid ${(SEVERITY_COLORS[r.severity] || SEVERITY_COLORS.none).fg}`,
                  borderRadius: 6,
                  padding: "10px 14px",
                }}
              >
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8 }}>
                  <span style={{ fontFamily: "ui-monospace, Menlo, monospace", fontSize: 12, fontWeight: 800, color: "#344054" }}>{r.id}</span>
                  <div style={{ display: "flex", gap: 6, alignItems: "center" }}>
                    <SeverityPill severity={r.severity} />
                    <StatusPill status={r.status} />
                  </div>
                </div>
                <div style={{ fontSize: 13, color: "#1a2230", marginTop: 6 }}>{r.title}</div>
                <div style={{ fontSize: 11, color: "#8a8f98", marginTop: 4 }}>
                  {r.domain}
                  {r.ticket ? ` · ${r.ticket}` : ""}
                  {r.isKnownIssue ? " · known issue" : " · NOT attributed to a known ticket"}
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Known issues */}
        <div style={{ flex: "1 1 360px", minWidth: 300 }}>
          <h2 style={sectionTitle}>Known Issues Reproduced ({knownIssues.length})</h2>
          <div style={{ background: "#ffffff", border: "1px solid #e3e6ea", borderRadius: 8, overflow: "hidden" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 12.5 }}>
              <thead>
                <tr style={{ background: "#f0f2f5", textAlign: "left" }}>
                  <th style={{ padding: "7px 12px", fontWeight: 700, color: "#5b636e" }}>Scenario</th>
                  <th style={{ padding: "7px 12px", fontWeight: 700, color: "#5b636e", width: 120 }}>Ticket</th>
                  <th style={{ padding: "7px 12px", fontWeight: 700, color: "#5b636e", width: 80 }}>Status</th>
                </tr>
              </thead>
              <tbody>
                {knownIssues.map((r) => (
                  <tr key={r.id} style={{ borderTop: "1px solid #eef0f3" }}>
                    <td style={{ padding: "7px 12px" }}>
                      <span style={{ fontFamily: "ui-monospace, Menlo, monospace", fontWeight: 700, color: "#344054" }}>{r.id}</span>
                    </td>
                    <td style={{ padding: "7px 12px", color: "#344054" }}>{r.ticket || "—"}</td>
                    <td style={{ padding: "7px 12px" }}>
                      <StatusPill status={r.status} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div style={{ fontSize: 11, color: "#8a8f98", marginTop: 8, lineHeight: 1.5 }}>
            SC-3384 (multi-currency / configured pricing uses USD values) is the most frequently reproduced family,
            followed by SC-3404 (renewal-maintenance COLA net) and SC-3359 (partner-net on Perpetual / Quote-to-Order).
            Known issues are pre-existing defects, not regressions introduced by this run.
          </div>
        </div>
      </div>

      {/* Footer note */}
      <div style={{ marginTop: 28, fontSize: 11, color: "#9aa0a8", borderTop: "1px solid #e3e6ea", paddingTop: 12 }}>
        All validations performed read-only or via the sanctioned Place Sales Transaction Skip reprice harness on Draft
        records. No Quote/QLI direct DML, no order activation/submission, no platform events, no Workday/MuleSoft
        integration, no deletes. New / unattributed defects requiring triage: NB-HW (hardware audit-field persistence +
        inactive P5 picklist), MOD-QDISC (header discount not distributed), MOD-REGION (regional price computed but not
        committed).
      </div>
    </div>
  );
}
