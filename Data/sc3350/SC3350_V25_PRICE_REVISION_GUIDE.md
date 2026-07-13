# SC-3350 — Commit renewal COLA to NetUnitPrice via a native Price Revision element (V25 canvas guide)

**Org:** FortraUAT · **Procedure:** `Rev_Mgmt_Default_Pricing_Procedure` **V25 (Active)** · **Test quote:** `0Q0WC000003Ibx3`
**Author:** Liam Jeong

---

## STAGED SO FAR (Apex + data done — canvas is the remaining step)

- ✅ **`PriceRevisionPolicy` created** — `Fortra COLA Renewal Uplift`, Id **`1VCWC0000002fn34AA`** (PolicyType=`Flat`, Formula=`0`, EffectiveFrom 2026-01-01, USD). Reference this from the Price Revision element (or per line).
- ✅ **`COLAUpliftHandler` deployed** (API bumped 59→65 so `UnitPriceUplift` is Apex-visible): stamps `QLI.UnitPriceUplift = COLA_Uplift_Percent__c` on insert + on every update/override. Tests **61/61 green**.
- ✅ **Ibx3 test lines stamped** — `04267432` `UnitPriceUplift=5`, `04267433` `UnitPriceUplift=6.2`, both `PriceRevisionPolicyId=1VCWC0000002fn34AA`. Ready for your reprice once the element exists.
- ⏸️ **Deferred:** removing the prehook `NetUnitPrice` seed (currently inert — the engine discards it; harmless). I'll remove it *after* the Price Revision element is confirmed committing the net, so there's no window with no net mechanism and rollback stays trivial.
- 📌 **Gotcha for your canvas work:** `UnitPriceUplift`/`PriceRevisionPolicy` are **API 65.0+**. Any Apex/Flow that references them must be at ≥65.

**Your remaining step:** §6 — add the Price Revision element in-place on V25, then reprice Ibx3 (§9).

---

## 0. TL;DR — the direction

We proved (live debug trace, reprice of Ibx3) that **no Apex hook can commit `NetUnitPrice`** on V25: the prehook/posthook write `NetUnitPrice=98700/63720` and get `isSuccess:true`, but the engine **discards** it — the `price_water_fall` owned by the native `PricingSetting` element re-asserts the asset base (94000/60000) on every reprice, and `NetUnitPrice` is `IsUpdatable=false` so post-persist DML can't set it either.

Official Salesforce best practice (researched + verified) inverts the pattern:

> **Stop writing the OUTPUT (`NetUnitPrice`) from a hook. Instead the Apex layer stamps a writable INPUT (`UnitPriceUplift` %, per line, per solution-category), and a native `Price Revision` element in the pricing procedure PRODUCES and commits `NetUnitPrice = priorNet × (1 + uplift)`.** `Asset.PricingSource = LastTransaction` (which we treated as the obstacle) is the documented *trigger*.

V25 has **no** Price Revision element today, so it must be **added once, in place** (deactivate → add element → reactivate → re-sync context) — **no new version**.

**Three coordinated changes:**
1. **Data/config** — create a `PriceRevisionPolicy` record; (likely) set `Asset.PricingSource='LastTransaction'` on renewal source assets.
2. **Canvas (V25)** — add one `Price Revision` element in the renewal branch, gated to Fortra-Originated renewal COLA lines; retire the inert `COLA Uplift Net on Renewal` element.
3. **Apex** — `COLAUpliftHandler` stamps `QLI.UnitPriceUplift = colaPercent` (+ `PriceRevisionPolicyId`); remove the discarded `NetUnitPrice` seed from `COLAUpliftPrehook`.

---

## 1. Why this is the right fix (evidence)

| Layer | What we tried | Result (proven on Ibx3 reprice, log `07LWC00000QEleP2AT`) |
|---|---|---|
| Prehook | `updateContextAttributes({NetUnitPrice:98700})` | `isSuccess:true`; context shows 98700 mid-prehook (log 24880–25418) → **reverts to 94000** between apex phases (25476) |
| Posthook | `buildRenewalColaCommitUpdate` re-writes 98700 | `RENEWAL COLA COMMIT ... -> colaNet=63720`, `isSuccess:true` → **also discarded**; final persist 94000 |
| Procedure `AssignmentElement` | `COLAUpliftNetonRenewal` (`COLACalculatedPrice__c → NetUnitPrice`) | Inert — a ListGroup net-write updates only the context var, never the waterfall (June RCA + SC-3346 lever-d both confirmed) |

**Root:** `NetUnitPrice` is an engine output owned by `price_water_fall` (the `PricingSetting` element, `sequenceNumber=1`, outputs `PriceWaterfall`+`NetUnitPrice`+`Subtotal`). For a renewal line (`ItemPricingSource='LastTransaction'`) it sources the prior asset net and re-asserts it. Only a **native net-producing element** can change the committed net — and `Price Revision` is the one purpose-built for LTP renewal uplift.

---

## 2. Prerequisites — verify in Setup BEFORE canvas work

1. **Feature "Apply Policy-Driven Price Revisions"** must be enabled (Setup → Revenue Settings / Pricing). The objects/fields exist in the org (`PriceRevisionPolicy`, `QLI.UnitPriceUplift`, `QLI.PriceRevisionPolicyId`, `Asset.PricingSource`, AAS records) so the licensed feature is present — confirm the toggle is ON.
2. **API version ≥ 65.0** — ✅ org runs metadata v66/67.
3. Confirm you can **deactivate → edit → reactivate** V25 in the Pricing Procedure Designer (standard flow; no new version needed).

Docs (canvas click-path):
- Price Revision element: `help.salesforce.com/s/articleView?id=ind.pricing_use_the_price_revision_element_in_a_pricing_procedure.htm`
- Policy-driven revisions: `help.salesforce.com/s/articleView?id=ind.pricing_apply_policy_driven_price_revisions.htm`
- CPI & uplifts (the formula): `help.salesforce.com/s/articleView?id=ind.qocal_consumer_price_index_and_price_uplifts.htm`
- `PriceRevisionPolicy` object: `developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/.../sforce_api_objects_pricerevisionpolicy.htm`

---

## 3. Feasibility snapshot (confirmed on FortraUAT)

| Item | State |
|---|---|
| `PriceRevisionPolicy` object | ✅ present; `PolicyType` picklist = **`Flat`, `PriceIndex`**; fields `Formula`, `Region`, `EffectiveFrom/To`, `CurrencyIsoCode` |
| `QuoteLineItem.UnitPriceUplift` | ✅ type **percent**, updateable |
| `QuoteLineItem.PriceRevisionPolicyId` | ✅ reference → `PriceRevisionPolicy`, updateable |
| `Asset.PricingSource` | picklist `PriceBookListPrice`/`LastTransaction`, updateable — **currently `null`** on Ibx3 assets |
| AAS (`AssetActionSource`) for Ibx3 assets | ✅ present: `Subtotal=94000/60000`, `Quantity=1`, `NetUnitPrice=94000/60000` — the LTP formula inputs exist |
| Assets | Installed, `HasLifecycleManagement=true`, `CurrentLifecycleEndDate=2027-07-05` |
| Price Revision **element in V25** | ❌ absent (must add) |
| `PriceRevisionPolicy` records | ❌ none (must create) |

---

## 4. Step 1 — Create the PriceRevisionPolicy (data)

Create one policy to reference from the lines:

```
Name           = Fortra COLA Renewal Uplift
PolicyType     = Flat          (our COLA is a fixed per-category %, not a market index)
Region         = (leave blank / All, unless per-region needed)
CurrencyIsoCode= USD           (per-currency if you localize later)
EffectiveFrom  = <go-live date, e.g. 2026-01-01>
EffectiveTo    = <far future, e.g. 2099-12-31>
Formula        = <see note>
```

> **TEST-AND-ADJUST (policy math):** the per-category rate comes from the **per-line `UnitPriceUplift`** (5% / 6.2%), not the policy. A `Flat` policy should apply `net = priorNet × (1 + UnitPriceUplift)` with the policy's own base = 0. If, during testing, `Flat` ignores the per-line uplift, switch to `PolicyType=PriceIndex` with a `Formula` that yields a 0 base index, so only the per-line `UnitPriceUplift` drives the result (docs: for LTP + CPI/Variable, `net = AAS(Δsubtotal/Δqty) × (1 + renewal uplift percent)`). Validate on Ibx3 either way (§8).

Capture the created record Id — the Apex handler stamps it onto lines (or set it as the element's default).

---

## 5. Step 2 — Set Asset.PricingSource (data — verify need)

Both Ibx3 source assets have `PricingSource = null`, yet the pricing context already resolves `ItemPricingSource='LastTransaction'` (the COLA elements matched). Docs say the uplift "only functions when the asset pricing source is LastTransaction."

- **Action:** set `Asset.PricingSource = 'LastTransaction'` on the renewal source assets (`02iWC000008kDFOYA2`, `02iWC000008kDFPYA2`) and re-test.
- If the Price Revision element fires with `PricingSource=null` (because the engine derives LTP from the Renew QuoteAction), this step is unnecessary — **confirm during §8**. If it's required org-wide, add it to the renewal-creation flow so every renewal asset carries it.

---

## 6. Step 3 — Canvas edit on V25 (the one in-place procedure change)

### 6.0 The placement decision (READ FIRST — this is the crux)

Two facts from V25's structure decide where the element goes:

- **`Pricing Setting`** (the element that outputs `NetUnitPrice` + `price_water_fall`) is a **TOP-LEVEL step** (no `parentStep`), `resultIncluded=true`, `sequenceNumber=1`. **Top-level net-producers COMMIT.**
- The inert **`COLA Uplift Net on Renewal`** (`COLAUpliftNetonRenewal`) sits **inside `ListContainer2`** (a ListGroup), `resultIncluded=false`. June proved a `NetUnitPrice` write from *inside a ListGroup* updates only the context var and **never flushes**.

➡️ **Put the Price Revision element at the TOP LEVEL, immediately AFTER `Pricing Setting` — NOT inside `ListContainer2`.** It is a native net-producer like `Pricing Setting`, so at the top level it should commit; placed inside `ListContainer2` it would likely be swallowed like the AssignmentElement was. (If your Designer only lets a Price Revision element live inside a group, make it its **own new top-level container** with the gate below — do not reuse `ListContainer2`.)

### 6.1 Deactivate

Open V25 in the Pricing Procedure Designer → **Deactivate** (required to edit an active version). **Record the current version** first (screenshot the flow) for rollback. **Do not Save-As / do not create a new version.**

### 6.2 Add the `Price Revision` element (top-level, after `Pricing Setting`)

Add a new **Price Revision** element and drag it so it executes **right after `Pricing Setting`** in the top-level sequence.

- **Result:** turn **Include in Result = ON** (`resultIncluded=true`) — this is what makes its output commit.
- **Policy:** point it at the created policy **`Fortra COLA Renewal Uplift` (`1VCWC0000002fn34AA`)** — either as the element's default policy, or map it to read `PriceRevisionPolicyId` from the line (both are stamped on the Ibx3 lines already).
- **Uplift source:** the per-line **`Unit Price Uplift`** (maps to `QuoteLineItem.UnitPriceUplift`, already stamped `5` / `6.2`). This is what makes the rate vary per solution-category.
- **Output:** it produces **`NetUnitPrice`** for LTP lines (`= priorNet × (1 + uplift)` from the asset's AAS). Let the existing downstream `Quantity * Price` / aggregate steps roll `NetUnitPrice` up into `NetTotalPrice`/`TotalPrice`/GrandTotal (they already do this for `Pricing Setting`'s output — no extra mapping needed).

### 6.3 Gate the element (exact criteria — blast-radius CONFIRMED against live data)

> **⚠️ Corrected after a live population check (2026-07-12).** The verbatim `ListContainer2` gate (`...DerivedPricingAttribute IsNotNull... COLA_Uplift_Percent__c IsNotNull`) is **NOT safe to reuse as-is** — it matches **1 Renewal Maintenance line** (`0QLWC000003dEW24AM`, BoKS, COLA%=7.85), which the SC-3346 path owns. Use the corrected gate below, which keys on `UnitPriceUplift IsNotNull` — and the handler now stamps `UnitPriceUplift` **only on non-maintenance** lines, so maintenance stays null → the element is a guaranteed no-op on it.

```
Condition logic: 1 AND 2 AND 3 AND 4 AND 5
  1. ItemPricingSource          Equals      'LastTransaction'      (Literal)
  2. SalesTransactionActionType Equals      'Renew'                (Literal)
  3. UnitPriceUplift            IsNotNull        ← the discriminator: only handler-staged, non-maintenance renewal COLA lines have it (maintenance = null → excluded, null-safe)
  4. Deal_Type__c               Equals      'Fortra Originated'    (Literal)  ← partner-safe, NARROWEST scope (see note)
  5. Fortra_Product_Type__c     NotEquals   'Renewal Maintenance'  (Literal)  ← belt-and-suspenders vs SC-3346
```

**Deal_Type scope decision (yours):** `Equals 'Fortra Originated'` is the narrowest — it fixes the 83 Fortra-Originated renewal COLA lines (incl. Ibx3) and excludes 8 partner (`Channel Originated`) + 28 `null`-Deal_Type lines. To also cover the 28 null-Deal_Type lines, switch #4 to `NotEquals 'Channel Originated'`. Start narrow; expand after validation.

### 6.4 Retire the inert `COLA Uplift Net on Renewal`

Inside `ListContainer2`, **delete (or disable)** `COLA Uplift Net on Renewal` (`COLAUpliftNetonRenewal`, `COLACalculatedPrice__c → NetUnitPrice`). It is proven inert and now redundant — leaving it invites confusion during testing. **KEEP** `COLA Uplift on Renewal` (`COLAUpliftonRenewal`, `COLACalculatedPrice__c → InputUnitPrice`) — that InputUnitPrice write is still valid.

### 6.5 Reactivate + re-sync context

**Reactivate** V25, then **re-sync the context definition** `SalesTransactionContextExt_v2` (Pricing Procedure Designer → the context re-sync action). This prevents the "Specify contextDefinitionName" gack that an in-place edit without re-sync causes (memory `project_reprice_contextdef_error`). A deploy/activation that merely shows "Active" does **not** recompile the runtime — the **reactivate + re-sync** is what republishes it.

### 6.6 Smoke-test → run §9 acceptance

Reprice Ibx3 (`Data/.../scratchpad/reprice_ibx3.sh`) and check the trace: the committed `NetUnitPrice` must now come from the **Price Revision element**, not revert to base. Then run §9.

---

## 7. Blast radius — CONFIRMED against live data (2026-07-12)

Live query of renewal QLIs with a Renew QuoteAction + `COLA_Uplift_Percent__c` set, by product type × deal type:

| Fortra_Product_Type | Deal_Type | Count | Under the gate (`Fortra Originated`)? |
|---|---|---|---|
| null (license) | Fortra Originated | 68 | ✅ **IN** — target (Ibx3's type) |
| Subscription | Fortra Originated | 8 | ✅ IN — ⚠️ verify vs Subscription/term (below) |
| Software | Fortra Originated | 7 | ✅ IN |
| **Renewal Maintenance** | Fortra Originated | **1** | ❌ **OUT** — `UnitPriceUplift` null (handler excludes) + criterion 5 |
| null | null | 22 | ❌ OUT (null Deal_Type) — scope decision |
| Subscription | null | 6 | ❌ OUT (null Deal_Type) |
| null / Software | Channel Originated | 8 | ❌ OUT — partner |

**So this is NOT a 2-line change — it corrects ~83 Fortra-Originated renewal COLA lines** (every currently-broken one, which is the intent). Confirmed exclusions:

- **Maintenance** — the 1 BoKS `Renewal Maintenance` line is excluded two ways: the handler now leaves its `UnitPriceUplift` null (→ element applies 0 uplift), plus criterion 5. Prevents a collision with the SC-3346 path.
- **New business** — not `LastTransaction` (no Renew QA), excluded by criteria 1–2.
- **No-Change lines** (e.g. Ibx3 `04267431`) — not `'Renew'` + `UnitPriceUplift` null.
- **Partner (`Channel Originated`)** — excluded by criterion 4. Applying COLA uplift *and* partner discount needs deliberate sequencing (uplift → Partner Discount element); defer until agreed.

### ⚠️ NOT yet verified (validate before trusting the broad scope)
- **Subscription / Software lines (15 of the 83)** interact with the `Subscription Pricing` element (net × term). Price Revision uplifts the per-unit net *before* that multiply — the result could be correct **or** double-count depending on term math. **Validate a subscription renewal separately** before relying on these; consider starting with license-only (`null` product type) and adding subscription/software after a clean subscription test.
- **`DerivedPricingAttribute` context value** on target lines — I could not read it from the trace; the corrected gate no longer depends on it (uses `UnitPriceUplift IsNotNull`), so this is moot for the gate, but confirm during the Ibx3 trace that only the two intended lines are hit.

---

## 8. Step 4 — Apex rework (coordinate with the canvas change)

Replace "write the output" with "stamp the input." (I will implement + deploy this in coordination — it's inert until the canvas element exists, so order isn't critical, but ship together for a clean state.)

**`COLAUpliftHandler` (before insert/update on QuoteLineItem):** for each renewal COLA line, stamp the writable inputs (Trigger.new mutation — DML-free, §2/§8 compliant, **fill-only** so a rep's manual uplift override is preserved):
```apex
qli.UnitPriceUplift      = colaPercent;                 // 5 / 6.2 — the per-category rate
qli.PriceRevisionPolicyId = fortraColaRenewalPolicyId;  // resolved dynamically, not hardcoded (§5 apex-compliance)
```

**`COLAUpliftPrehook`:** remove the `pendingNetUnitPriceUpdates` seed + `shouldSeedRenewalNet`/`buildNetUnitPriceUpdate` calls (the discarded `NetUnitPrice` write). Keep the audit-field stamps (`COLACalculatedPrice__c`, `Pre_COLA_Price__c`, `COLA_Source__c`, explainer) — those are legitimate context writes that persist.

**Tests:** assert `UnitPriceUplift`/`PriceRevisionPolicyId` are stamped per category, fill-only preservation, and (new E2E) that committed `NetUnitPrice == priorNet × (1+UnitPriceUplift)`.

> Note: my earlier deployed guard broadening in `COLAUpliftPrehook` is currently **inert** on V25 (it fires the seed; the engine discards it). It will be removed in this rework.

---

## 9. Step 5 — Validate on Ibx3 (acceptance)

After policy + (asset) + canvas + Apex:

1. Force-reprice `0Q0WC000003Ibx3` (Place Sales Transaction, `pricingPref:Force`).
2. **Assert committed:** `NetUnitPrice = 98700 / 63720`, `NetTotalPrice`/`TotalPrice` follow, **Quote GrandTotal = 162420** (= Subtotal).
3. **Idempotent:** reprice again → identical (98700/63720).
4. **D-18 clean:** no new `Exception_Log__c` / `Pricing_Exception__e`.
5. **No collateral:** the `No Change` line and any maintenance/new-business/partner lines unchanged.

Harness: `Data/.../scratchpad/reprice_ibx3.sh` + `verify_ibx3.sh`; trace via the active FINEST TraceFlag on the API user; look for the Price Revision element producing net (not a hook write).

---

## 10. Rollback (clean, reversible)

1. **Canvas:** Deactivate V25 → remove the Price Revision element → (optionally restore `COLA Uplift Net on Renewal`) → Reactivate → re-sync context. Restores V25 exactly (same pattern as the SC-3346 lever-d runbook, proven reversible).
2. **Apex:** redeploy the prior `COLAUpliftHandler`/`COLAUpliftPrehook`.
3. **Data:** delete the `PriceRevisionPolicy` record; null `Asset.PricingSource` if it was set.

Record the current V25 state before editing; keep V24 available for reactivation as the ultimate fallback.

---

## 11. Open items to confirm during your canvas work

1. **Flat vs PriceIndex policy** — which one honors the per-line `UnitPriceUplift`. Start `Flat`; if per-line % is ignored, use `PriceIndex` with a 0-base formula (§4).
2. **`Asset.PricingSource=null`** — does the Price Revision element fire without it, or must it be `'LastTransaction'` (§5)?
3. **Uplift sourcing** — verify `net = priorNet × (1 + UnitPriceUplift)` exactly (not `× (1 + policyRate + uplift)` with a nonzero policy rate).
4. **Element position** — confirm it runs after `Pricing Setting` and its net survives to persist (watch the trace; the committed value must come from the Price Revision element, not revert like the hook writes did).
5. **Partner renewals** — deferred by the `Deal_Type` gate; sequence COLA-then-partner deliberately before scoping them in.
