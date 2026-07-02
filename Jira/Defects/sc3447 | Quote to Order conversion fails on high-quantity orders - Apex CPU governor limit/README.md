# SC-3447 — Quote→Order conversion fails on high-quantity orders (Apex CPU governor limit)

**Status:** Root cause confirmed against live FortraUAT (read-only) · roadmap ready · **no code/data changes made**
**Priority:** Blocker · **Reporter:** Joe Romo · **Assignee:** Liam Jeong · **Label:** CRM-Revenue-Cloud
**Component:** Quote → Order conversion (`Fortra Quote to Order Conversion` flow → `PowerOrderSplittingService`)
**Researched:** 2026-06-18 · **Re-verified live 2026-06-26**

---

> ### ⚠️ 2026-06-26 RE-VERIFICATION — two corrections to the notes below
> Full deep-research report (live-verified): **`Data/sc3447/00_DEEP_RESEARCH_REPORT.md`** (+ data in `01_LIVE_EVIDENCE_DATA.md`).
> 1. **The "(Deprecated) Autolaunched Set Workday Contract Line Type" subflow is now INACTIVE** (no active
>    version; SC-3366 deactivated it 2026-06-08) and **no live flow invokes it.** So the per-clone load today is
>    **2 flows, not 3** — the "remove the deprecated subflow" item is already done. The 1,293-interview / ~400-clone
>    figures below came from a **pre-2026-06-08 log**; the CPU ceiling has since moved up and the Abstract @ 456
>    repro **may now convert** (re-test to find the current threshold). The architectural defect is unchanged.
> 2. **Bigger scope than "Abstract is mis-tagged test data":** `Power` is a real 3,406-product catalog group and
>    live Power `Quantity` is routinely a **user/seat count in the thousands** (Powertech Password Self Help @ 7,500;
>    MFA @ 9,900) or an **"unlimited" sentinel** (9,999 / 99,999 / **999,999**; 134 lines at 999,999). Per-unit
>    splitting is **conceptually wrong** for these, not just slow. Also: only **1 of 3,406** Power products uses the
>    `Order Line and Hardware` split type — the hardware-clone branch is effectively dead.
> 3. **Clones are NOT reliably pre-stamped** (live sample shows null line-type/dates on some split lines) — so any
>    fix that suppresses the per-clone flows **must explicitly stamp** line-type/dates/PTC on clones in Apex.

---

## TL;DR

Converting a quote that contains a high-quantity **"Power" Solution-Group** line fails with a CPU
governor limit. The conversion calls `PowerOrderSplittingService`, which clones the line into
**(qty − 1) individual qty=1 OrderItems** (one per unit, plus a Hardware + Partition clone each),
then runs **three autolaunched flows on every clone**. On the repro quote that is ~**1,293 flow
interviews / 480 DML rows / ~401 clones in one synchronous transaction**, which blows the **10,000 ms
Apex CPU limit** → `System.LimitException: Apex CPU time limit exceeded` → the whole convert rolls
back. The UI shows it as either *"Limit Exceeded — exceeded the maximum limit for this feature"* or
*"An unhandled fault has occurred in this flow"* (same underlying failure, two render paths).

**It is not an org/license entitlement cap** (all 72 org named-limits are healthy) and **not** the
earlier convert defect that was already resolved.

## Scope (important)

The split is **hardcoded-gated** to `Product2.Solution_Group__c = 'Power' AND Quantity > 1`. So the
trigger is **high quantity on a *Power*-group product specifically — not high quantity in general:**

| Line on repro quote | Solution Group | Qty | Splits? |
|---|---|---|---|
| **Abstract** (`01tWC00000DD11GYAT`) | **Power** | 456 | ✅ → 455 clones → **blows CPU** |
| Accelerated (`01tWC00000DD11HYAT`) | Managed File Transfer | 3,425 | ❌ no |
| **Endpoint DLP** (Joe's 750,000-qty example) | Defensive Security | 750,000 | ❌ no |

➡️ Joe's *Endpoint DLP @ 750k* would actually **convert fine** — it isn't a Power product. This both
narrows the blast radius and gives us a clean **negative test** (a non-Power high-qty order must pass).

## The bug in one paragraph

`PowerOrderSplittingService.queryOrderItemsToSplit` selects every `Solution_Group='Power' AND Quantity>1`
OrderItem, then `createFullClone()`s it **(qty − 1)** times (`for (Integer i = 1; i < qty; i++)`),
cloning ~150 fields + a Hardware + Partition record per clone. The clones insert in one synchronous
request; each then fires `Fortra | OrderItem | Set Dates`, `Fortra | OrderItem | Set Workday Contract
Line Type` (V11), and a **deprecated** `Autolaunched | Set Workday Contract Line Type` duplicate. The
accumulated Apex CPU crosses 10,000 ms at ~400 clones and the transaction dies.

## Files in this folder

| File | Contents |
|---|---|
| **README.md** | this overview |
| **01_EVIDENCE.md** | log analysis, exact counts, code references, the splitting algorithm |
| **02_ROOT_CAUSE_AND_ROADMAP.md** | root-cause statement + phased fix roadmap (P0→P4) |
| **JIRA_DESCRIPTION.md** | paste-ready Jira wiki-markup description |
| `evidence/PowerOrderSplittingService.cls` | retrieved Apex (the splitter) |
| `evidence/convert_flow_excerpt.log` | convert-flow interview excerpt |

Raw artifacts (full 19.5 MB log, retrieves) under `Data/sc3447/`.

## Related

- **SC-3366** — order-completion SOQL governor blowout on large orders (same family; same deprecated
  Autolaunched Workday line-type subflow is wasted load).
