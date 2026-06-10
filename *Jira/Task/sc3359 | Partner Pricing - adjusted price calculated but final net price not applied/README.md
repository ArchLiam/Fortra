# SC-3359 — Partner Pricing: adjusted price is calculated correctly but the final (net) line price is not applied on One-Time / Perpetual lines

> Space: Salesforce-Coastal (SC) · Type: Task · [SC-3359](https://helpsystems.atlassian.net/browse/SC-3359)
>
> 🔬 **Root cause CONFIRMED (read-only deep dive, FortraUAT 2026-06-07; multi-agent RCA, adversarially verified — 3/3 lenses, high confidence).**
> The partner discount **is** calculated and **is** written to `NetUnitPrice` by the pricing procedure's standard
> *Partner Discount* step — but a **later, selling-model-routed `SubscriptionPricing` step overwrites it** for
> **One-Time (Perpetual)** lines by re-reading the **un-discounted `InputUnitPrice`**. The **TermDefined/Evergreen**
> branches read `NetUnitPrice` and preserve the discount, which is why **Services worked but Perpetual didn't**.
> The discriminator is **`SellingModelType`**, *not* product family. The maintenance symptom is a **distinct** bug.

---

## ⚠️ UPDATE 2026-06-08 — Deep re-investigation corrections (READ THIS FIRST; supersedes claims below)

A second, independent read-only deep investigation (9-agent workflow: 5 investigators → 3 adversarial lenses, **all 3 lenses refuted a prior claim** → synthesis; FortraUAT, no DML/deploy/reprice) confirmed the **defect is real and lives in active V9 `SubscriptionPricing74`**, but **materially corrected the mechanism and the fix**. Treat the "Root cause CONFIRMED / high confidence" banner above and the "Proposed solution (RECOMMENDED)" section below as **partially superseded**:

1. **The proposed fix is INCOMPLETE and UNSAFE as written.** The mapping `TotalSubscriptionPrice: TotalLineAmount → ItemNetTotalPrice` **regresses `Subtotal`/`TotalLineAmount`**. On the One-Time path, `SubscriptionPricing74` is the **only** seeder of `TotalLineAmount` (the gross/list channel) — TermDefined gets it from a *second* step (`SubscriptionPricing80`). Removing it collapses the line's `Subtotal` from list ($2,008) to net (~$1,706.80) via `FormulaBasedPricing3`(seq34)→`AggregatePrice`(seq35)→`Assignment101`(seq41), diverging from every other line and from the very TermDefined branch the fix claims to mirror. **"Make SP74 identical to TermDefined" is a false symmetry** (TermDefined = two steps; One-Time = one). A safe V10 = INPUT `NetUnitPrice: InputUnitPrice→NetUnitPrice` + OUTPUT `SubscriptionNetUnitPrice: InputUnitPrice→NetUnitPrice`, **plus a deliberate list-amount `TotalLineAmount` seeder**, **plus a business decision on One-Time `Subtotal` semantics (list vs net)**. Keep `ProrationMultiplier=1`. This is a real design decision, not a mechanical flip.

2. **The stated mechanism is wrong.** `SubscriptionPricing74`'s OUTPUT targets the **`InputUnitPrice`/`TotalLineAmount`** context channels — it **never names the net channel** (`NetUnitPrice`/`ItemNetTotalPrice`). So "SP74 OVERWRITES NetUnitPrice back to InputUnitPrice" is false on the XML. The "SubscriptionPricing action sets net from its INPUT base regardless of output target" theory is **FALSIFIED** by the TermDefined control line (04266072) surviving the byte-identical `SubscriptionPricing80`. The action writes net via its **named OUTPUT**, not its input base.

3. **Residual MEDIUM-confidence puzzle (the key open item, fix-blocking).** Static analysis predicts the One-Time saved net should be `PartnerDiscount22`'s **$1,706.80** (it writes net @seq10, never overwritten on the One-Time path), but live shows **$2,008** *and* `NetTotalPrice`=$2,008. So either **(a)** `PartnerDiscount22` did not effectively run/persist for the One-Time line, or **(b)** a first-subscription-step net side-effect. **The fix's sufficiency is CONTINGENT on this** — if (a), re-pointing SP74's INPUT to read `NetUnitPrice` would read $2,008 and the fix would *not* work. **Only an authorized live RevSignaling / pricing-waterfall trace of line `04266071` can decide** (capture: did `PartnerDiscount22` fire, what value did it leave in the net channel @seq10, at which step does net read back as $2,008).

4. **TermDefined is NOT healthy either.** Of 6 clean TermDefined partner lines in all of UAT (0 Evergreen), only **1 is correct**; **3 leak to full list**. The leak is **broader than the One-Time branch**; the differentiator is upstream/temporal (whether `PartnerDiscount22` fired on that reprice), not branch wiring — likely the same root cause as item 3. Do not claim "TermDefined preserves the discount."

5. **Maintenance line: distinct LAYER, but value NOT independent.** The null-partner-fields *symptom* is a genuine separate prehook defect (zero-price guard + null `Fortra_Product_Type__c`). BUT its **$462 net is derived downstream** of the perpetual contributor (≈23.01% of the *un-discounted* $2,008), so after V10 it will **shift $462 → ~$393**. "V10 won't touch maintenance" is wrong for the value — a **post-fix maintenance regression check is mandatory**; guard against double-discount.

6. **`SubscriptionPricing80` = DO NOT TOUCH.** Confirmed it routes **only** TermDefined/Evergreen (never One-Time), is irrelevant to the One-Time fix, and is currently harmless (writes `InputUnitPrice`, not net). "Fixing" it would clobber net for all term/evergreen lines via its un-discounted base. Blast radius = 6 lines / 5 quotes (all TermDefined).

7. **No functional drift, but build from the fresh retrieve.** Live == local for all load-bearing elements (877-line diff = cosmetic tags dropped by API v62). Build any V10 from `Data/sc3359/refresh-drift/...-meta.xml`, **not** `uat-pricing-extracted`. Active still V9 (`..._V90`, `9QBWC0000000me94AA`); **V9 was created 2026-06-06 and last modified 2026-06-07T20:58Z by Nir Kailash** — re-verify active version + `SubscriptionPricing74` bytes immediately before any deploy.

8. **Data drift since first RCA:** partner discounts are now **15% & 8%** (were 20% & 23%) — the quote was re-priced; the qualitative bug is identical. Prehook V1-vs-V2 binding is **not confirmable** from any read-only org surface (handle `PreHookPartnerPricing`); immaterial to the net defect.

**Gate before any change:** (a) capture the live waterfall (item 3); (b) decide One-Time `Subtotal` semantics (item 1); only then design V10. **Any UAT deploy / version activation / reprice needs fresh explicit authorization + Nir Kailash coordination.**

---

## Details

| Field | Value |
|---|---|
| **Status** | To Do |
| **Reporter** | Liam Jeong (created) — **reported by German Wren** (Teams, 2026-06-07) |
| **Assignee** | Liam Jeong |
| **Priority** | 🔴 High — silent margin/revenue leak (every One-Time partner line is billed full list) |
| **Sprint** | CRM Sprint 14 |
| **Components** | SF RCA |
| **Labels** | Bug, CRM, RCA, Pricing, Partner |
| **Environment** | FortraUAT (`fortra--uat.sandbox.lightning.force.com`) |
| **Pricing owner (coordinate fix)** | Nir Kailash |

---

## Summary

When a quote runs through **Partner Pricing**, the engine finds the right partner pricing model and calculates the right
discount — but on **One-Time / Perpetual** product lines the **final selling (net) price is not updated**: the line keeps
its full list price, so the calculated partner discount is silently lost. **Services** (and other term/subscription) lines
apply correctly. A third line (**New Maintenance**) gets **no** partner pricing at all — a separate, distinct defect.

## Reported by

German Wren — Teams, 2026-06-07 (UAT), screenshot attached:

> *"…the process seems to be finding the right partner pricing models, and calculated the right discount, but the final
> price is not being updated. This can be seen on line #2 of this quote … The maintenance price is still not working so
> I'm not sure if the same issue is occurring from maintenance SKUs, but you can see it on the software."*

## Affected record

- **Quote:** Q-Wren - Test GS Quotes2 (`00780912`) — Status **Draft**, USD, model **Guaranteed Margin**, `Deal_Type__c` **Channel Originated**
- **Link:** https://fortra--uat.sandbox.lightning.force.com/lightning/r/Quote/0Q0WC0000036H9K0AU/view
- **Id:** `0Q0WC0000036H9K0AU` · Partners: Distributor `001WC00000ZtazZYAR` (AB Test Partner Account), Reseller `001WC00000bQEV3YAO` (New Partner Company)

### Line evidence (verified SOQL, read-only)

| # | Product | **SellingModelType** | List/Unit | Partner % | `Partner_Adjusted_Price__c` (calc) | **NetUnitPrice (actual)** | Verdict |
|---|---|---|---|---|---|---|---|
| 1 | CCM Limited Scan Engine-NewMaintenance | OneTime | $2,008 | — | **null** (never ran) | $462 *(derived)* | ⚠️ partner pricing **never ran** (distinct bug) |
| 2 | CCM Limited Scan Engine | **OneTime** | $2,008 | 20% | **$1,606.40** | **$2,008** | ❌ **calc discarded — full list charged** |
| 3 | CSCO I & II Course | **TermDefined** | $850 | 23% | $654.50 | $654.50 | ✅ applied correctly |

**Leak on line 2** = $2,008 − $1,606.40 = **$401.60** (20% = Billing Partner 15% + Reseller 5%, additive Guaranteed Margin).
Ruled out: `Is_Partner_Price_Overridden__c` = false on all lines; **zero** `QuoteLinePriceAdjustment` records → line 3's
$654.50 is the pure partner calc (`850 × (1−0.23)`), not a coincidental manual discount.

---

## Root cause (PRIMARY — One-Time / Perpetual)

The apply-to-net failure is **entirely in the active pricing procedure**, not the Apex prehook. The discount is computed
*and* written into `NetUnitPrice` correctly; a later step throws it away for One-Time lines.

**Engine = ExpressionSetDefinition `Rev_Mgmt_Default_Pricing_Procedure`, active version V9** (9 versions exist; V1–V8 Inactive).
Steps execute by `parentStep` + `sequenceNumber` (NOT XML order). The relevant ordered steps:

| Seq | Step (`name`) | What it does to the per-line net |
|---|---|---|
| 10 | **Partner Discount** group (`ListContainer3`): filter `PartnerDiscount` + `PartnerDiscount22` (ManualDiscount) | Reads `PartnerDiscountPercent`; writes **`NetUnitPrice = InputUnitPrice × (1 − PartnerDiscountPercent)`** and `Subtotal → ItemNetTotalPrice`. ✅ After this, line 2 `NetUnitPrice` = **$1,606.40**, line 3 = **$654.50**. |
| 24 | **SubscriptionPricing** (TermDefined branch) | `NetUnitPrice(in) = NetUnitPrice` → `SubscriptionNetUnitPrice(out) = NetUnitPrice` — **preserves** discount. (Line 3 routes here.) |
| 25 | **SubscriptionPricing70** (Evergreen branch) | `NetUnitPrice(in) = NetUnitPrice` — **preserves**. |
| 26 | **SubscriptionPricing74** (`ListContainer71`, **One-Time** branch; selected by `ListOperation72` = `SellingModelType ≠ Evergreen AND ≠ TermDefined`) | **`NetUnitPrice(in) = InputUnitPrice`** → `SubscriptionNetUnitPrice(out) = InputUnitPrice`, `TotalSubscriptionPrice(out) = TotalLineAmount` — **OVERWRITES** `NetUnitPrice` back to the un-discounted base. ❌ **Line 2 reverts $1,606.40 → $2,008.** |

**Why the One-Time branch reverts:** `InputUnitPrice` holds the list-derived base (~$2,008, seeded by the upstream
pricebook/list steps at seq 1–14). The Partner Discount step writes **only `NetUnitPrice`** — it never copies the
discounted value into `InputUnitPrice`, and **no step between seq 10 and seq 26** copies `NetUnitPrice` back into
`InputUnitPrice`. So when `SubscriptionPricing74` reads `InputUnitPrice`, it reads the *un-discounted* price and clobbers
the discount. The total reverts too (`TotalSubscriptionPrice → TotalLineAmount`). Downstream steps (seq 28+) only roll up
totals; none re-derive a discounted `NetUnitPrice`, so the reverted value persists to the saved QLI.

**The one and only difference between the working and broken branches:** the TermDefined/Evergreen branches read
`NetUnitPrice`; the One-Time branch reads `InputUnitPrice`. That asymmetry is the bug.

> **This is a stable config inconsistency, not a V9 regression** — V8's `SubscriptionPricing74` has the identical
> `NetUnitPrice(in) = InputUnitPrice` mapping. It breaks for **any** One-Time / Perpetual partner line, not just this quote.

### Mechanism diagram (line 2, Perpetual)

```
seq 1–2   PriceBookEntries        InputUnitPrice = 2008 (list)           NetUnitPrice = 2008
seq 10    Partner Discount        NetUnitPrice = 2008 × (1−0.20)  ───►    NetUnitPrice = 1606.40  ✅ discount applied
          (InputUnitPrice still = 2008; never updated)
seq 26    SubscriptionPricing74   NetUnitPrice ← InputUnitPrice (2008) ►  NetUnitPrice = 2008     ❌ discount discarded
          (One-Time branch reads the wrong field)
RESULT    saved QLI               NetUnitPrice = NetTotalPrice = TotalPrice = 2008  (full list)
```

For line 3 (Services, TermDefined) seq 24 reads `NetUnitPrice` → $654.50 survives.

## Root cause (SECONDARY — New Maintenance; **distinct bug**)

Line 1 gets **all partner fields null** because the **Apex prehook never ran the margin lookup** for it:

- The prehook's **zero-price skip guard** (`currentPrice = UnitPrice`; fall back to `ListPrice`; `if (currentPrice <= 0) return null`)
  fires **before** any margin/context-write logic. The maintenance product (`01tWC00000DD16HYAT`) has **UnitPrice = 0 in all
  8 PricebookEntries** and the QLI `ListPrice = 0` at prehook time.
- Its real $462 net is a **downstream Derived-Pricing (maintenance-of-license) derivation** that doesn't exist when the
  prehook runs (prehook = seq 3 in the plan; derivation happens inside the procedure at seq 9). The single-pass prehook
  **structurally cannot price a line whose net is derived later.**
- Model data is fine: both active Guaranteed-Margin models have `New_Maintenance_Percent__c` populated (12 and 5 → would be
  17% additive). Minor contributing gap: `Fortra_Product_Type__c` is null on the maintenance QLI/context though the Product2
  carries "New Maintenance" (the prehook defaults blank type to "Software"; not the decisive blocker).

→ **Different layer, different fix.** Track maintenance separately; do **not** bundle it with the Perpetual fix.

## Engine wiring (for reference)

- Apex prehooks are registered via **ProcedurePlanDefinition `Fortra_Pricing_PreHook`** and run **before** the procedure:
  `1 Hardware → 2 Regional → 3 Partner Pricing → 4 AttributeVolume → 6 COLA → 9 PricingProcedure (Rev_Mgmt_Default_Pricing_Procedure) → 10 QLDescription`.
- The registered partner class appears to be **`PartnerPricingPrehook` (V1)**; the **V2 cutover was never applied**. This is
  **immaterial** to both bugs — V1 and V2 are byte-equivalent for the relevant logic (both write only partner *context*
  attributes — `PartnerUnitPrice`, `PartnerDiscountPercent`, `Partner_Adjusted_Price__c`, … — and **never** `NetUnitPrice`),
  and both have the identical zero-price guard. (Exact ApexClassId binding wasn't fully reconfirmable read-only.)
- The procedure XML contains **no Apex/Signaling action** — it consumes `PartnerDiscountPercent` from context via its standard
  *Partner Discount* `ManualDiscount` step. Timing is valid (prehook seq 3 < procedure seq 9).

---

## Proposed solution (RECOMMENDED — fix the pricing procedure)

> ⚠️ **SUPERSEDED IN PART — see "UPDATE 2026-06-08" at the top.** The 3-mapping flip below is **unsafe as written** (the `TotalSubscriptionPrice → ItemNetTotalPrice` change regresses `Subtotal`/`TotalLineAmount`, because `SubscriptionPricing74` is the One-Time path's only `TotalLineAmount` seeder), and its **sufficiency is unverified** (contingent on a live waterfall trace of `PartnerDiscount22` persistence). Use it as direction only; do not deploy it verbatim.

Fix authoritatively in the apply-to-net layer; do **not** hard-code and do **not** make the prehook write net price.

**Make the One-Time `SubscriptionPricing` branch consume the partner-discounted `NetUnitPrice`, exactly like the working branches.**

In the active **V9** of `Rev_Mgmt_Default_Pricing_Procedure` (deploy as a **new version V10** for clean rollback), change
**`SubscriptionPricing74`** (`parentStep ListContainer71`, the One-Time branch):

| Param | Current (broken) | Change to (matches TermDefined branch) |
|---|---|---|
| `NetUnitPrice` (in) | `InputUnitPrice` | **`NetUnitPrice`** |
| `SubscriptionNetUnitPrice` (out) | `InputUnitPrice` | **`NetUnitPrice`** |
| `TotalSubscriptionPrice` (out) | `TotalLineAmount` | **`ItemNetTotalPrice`** |

Leave `Quantity`, **`ProrationMultiplier`** (`PricingTermCountValueOneConstant` — One-Time proration differs from TermDefined; must **not** change), `HideWaterfall`, etc. untouched. Copy the three mappings verbatim from the working `SubscriptionPricing` (TermDefined, seq 24) for guaranteed parity.

**Do NOT change:** `PartnerDiscount`/`PartnerDiscount22` (seq 10), the `ListContainer38` Assignment (seq 16 — it's a *null-fallback* `InputUnitPrice` seeder, gated by `InputUnitPrice IsNull AND DerivedPricingAttribute=false`; a **red herring**, it doesn't fire for line 2), the TermDefined branch (seq 24), or the Evergreen branch (seq 25). Leave the prehook untouched for this fix.

**Companion (gate behind a blast-radius check):** `SubscriptionPricing80` (`ListContainer78`) also reads `InputUnitPrice`,
but its routing filter `ListOperation79` = `SellingModelType Equals 'TermDefined' OR 'Evergreen'` (it is **not** the One-Time
branch, and **not** "InclusivePrice" — that lives in a separate `ListContainer81`/`ListOperation82`, seq 29). The Perpetual
line does **not** route through it, so it is **not** needed for the line-2 fix. However it shares the same `InputUnitPrice`
defect and runs at seq 28 (after the preserving seq-24 branch); org-wide data shows a few TermDefined GM lines reverting,
possibly via this path. **Before** touching it, run a blast-radius query (it covers currently-working lines). Recommendation:
**ship `SubscriptionPricing74` first**, then `SubscriptionPricing80` as a verified fast-follow.

### Alternatives considered (rejected)

| Approach | Why rejected |
|---|---|
| Prehook also writes `NetUnitPrice`/`InputUnitPrice` | Contradicts the prehook's deliberate design; the procedure re-derives net after the prehook anyway → would be clobbered; high regression risk; masks the real inconsistency. |
| New corrective step after the Subscription branches to copy partner price onto `NetUnitPrice` | Overlay, not a root fix; extra ordering/maintenance burden; fights future Subscription behavior. |
| Apex trigger/flow recomputes net on save | Bypasses the authoritative engine, breaks on reprice, desyncs from RLM waterfall/explainability. Against "fix the engine, not hard-code." |
| Reroute One-Time lines through the TermDefined branch | One-Time vs TermDefined have legitimately different **proration**; rerouting would mis-prorate one-time lines. Only the field *read* needs to match, not proration. |

### Maintenance fix (separate ticket / phase — owner: Nir Kailash)

The single-pass prehook can't price a line whose net is derived downstream. Options: (a) defer/re-run partner pricing for
`DerivedPricingAttribute`/`ItemIsDerived = true` lines **after** the Derived Pricing step, or (b) add a post-derivation
partner-discount step scoped to derived lines. **Critical guard:** must not double-discount the already-derived
maintenance-of-license net. Also fix the `Fortra_Product_Type__c` context-mapping gap on maintenance QLIs. **Do not deploy
with the Perpetual fix.**

---

## Steps to reproduce

1. In FortraUAT open a quote with a **One-Time / Perpetual** line and a Partner Pricing model giving a non-zero margin
   (repro: Quote `0Q0WC0000036H9K0AU`, line 2; `Deal_Type__c` ≠ "Fortra Originated").
2. Run Partner Pricing / reprice.
3. Inspect the line: `Partner_Adjusted_Price__c` / `PartnerUnitPrice` show the discounted price, but `NetUnitPrice` /
   `NetTotalPrice` / `TotalPrice` still equal full list.

**Expected:** net price = `Partner_Adjusted_Price__c` (= $1,606.40). **Actual:** net stays at list ($2,008).

## Risks (deploy)

- ExpressionSetDefinition deploys as a **new version** — deploy as **V10**, keep V9 intact for instant rollback (re-activate V9).
- V9 is **freshly churning** (created 2026-05-31 under SC-3345); **re-retrieve + diff immediately before editing** and coordinate with Nir Kailash.
- **`SubscriptionPricing80` blast radius** — covers TermDefined/Evergreen lines that work today; verify before changing it.
- Do **not** alter `ProrationMultiplier` on the One-Time branch (would mis-prorate one-time lines).
- Re-verify Quote-level Subtotal/Total/Discount Amount/Discount % rollups (the out-target changes from `TotalLineAmount` to `ItemNetTotalPrice`).
- Static analysis not yet closed with a live RevSignaling **waterfall** — capture one on the post-fix reprice.
- Org-wide partner data is dirty (28k+ un-repriced null-net rows, stale multi-pass fields, a separate "Discount" model) — rely on controlled same-day repros, not aggregate counts.

## Test plan

1. **Baseline** the 3 repro lines (done): Perpetual Net=2008 (bug), Services Net=654.50 (ok), Maintenance partner fields null.
2. **Validate-only** deploy of V10 to FortraUAT; zero errors.
3. **Blast-radius query** before activation: TermDefined/Evergreen partner lines whose net would change via `SubscriptionPricing80`.
4. Activate V10; reprice `0Q0WC0000036H9K0AU`. **Primary:** Perpetual `NetUnitPrice` 2008 → **1606.40**; NetTotal/TotalPrice follow; partner fields unchanged.
5. **Regression:** Services stays 654.50; build an **Evergreen** GM partner line → discount still applies; **bundle/InclusivePrice** quote unchanged.
6. **Rollups:** mixed OneTime+TermDefined+Evergreen quote — Quote totals/discount internally consistent.
7. **Waterfall:** `NetUnitPrice` = 1606.40 after `PartnerDiscount22` **and** after `SubscriptionPricing74` (was 2008). Archive under `Data/sc3359/`.
8. **Negative control:** a `Fortra Originated` One-Time line still gets **no** partner discount (filter gates it out).
9. **Maintenance:** confirm unchanged (still derived $462), no double-discount; remains pending its own fix.

## Acceptance criteria

- [ ] On `0Q0WC0000036H9K0AU` after reprice, the Perpetual line (`SellingModelType=OneTime`) has `NetUnitPrice = Partner_Adjusted_Price__c = $1,606.40` (= 2008 × (1 − 0.20)); NetTotal/TotalPrice reflect it.
- [ ] Services line (TermDefined) stays `$654.50` — no regression.
- [ ] No Evergreen/Subscription or InclusivePrice/bundle partner line regresses (every previously-correct line still correct).
- [ ] Fix lives entirely in the pricing procedure (`SubscriptionPricing74`, + `SubscriptionPricing80` if shipped) reading the partner-discounted `NetUnitPrice` symmetrically with TermDefined/Evergreen; **prehook unchanged**; no Apex hard-coding.
- [ ] A runtime waterfall confirms the discount is no longer discarded.
- [ ] Quote-level rollups remain consistent on a mixed multi-line quote.
- [ ] V9 can be re-activated to roll back instantly (no data fix).
- [ ] Reviewed/approved by pricing owner (Nir Kailash); deployed only after **explicit user authorization** for the UAT deploy.
- [ ] Maintenance null-partner-fields documented as a **distinct** root cause with its own plan; **not** regressed by this change.

---

## Verification / confidence

Root cause established by a 10-agent read-only RCA workflow (5 parallel investigators → synthesis → 3 adversarial verification
lenses → solution). **All 3 lenses returned `refuted: false`, confidence high.** Minor corrections folded in above
(the `ListContainer38` seeder is conditional/red-herring; `SubscriptionPricing80` is the TermDefined/Evergreen branch, not
One-Time/InclusivePrice; registered prehook is V1 but immaterial). Open item: a live RevSignaling waterfall would close the
last static-analysis gap (planned in the test plan).

## References / artifacts

- Reported via Teams (German Wren), 2026-06-07; screenshot attached.
- Repro quote `0Q0WC0000036H9K0AU` (`00780912`); lines `0QLWC000003bTZB4A2` (NewMaint), `0QLWC000003bTZC4A2` (Perpetual), `0QLWC000003bSWg4AM` (Services).
- Live pricing procedure (retrieved): `Data/sc3359/uat-pricing-extracted/.../Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition` — V9 active ≈ lines 41155–46540; `PartnerDiscount22` ~44407; `SubscriptionPricing74` ~45620; `ListOperation72` ~43930; TermDefined `SubscriptionPricing` ~45462.
- Apex (retrieved live): `Data/sc3359/PartnerPricingPrehook.cls` (V1, registered), `PartnerPricingPrehookV2.cls`, `PartnerPricingService(V2).cls`.
- RCA workflow script + full agent output: `Data/sc3359/research_workflow.js`.
- `ProcedurePlanDefinition` `Fortra_Pricing_PreHook` (Id `1FNWC0000000A4D4AU`), active version `1CvWC0000005vyX0AQ`.
- Related: SC-3345 (Quote pricing rollups / V-version churn), SC-3347 (net-vs-list at Order/Workday).
