# RCA Manual E2E Testing Prompt — FortraUAT Salesforce **UI** (Claude Chrome Extension)

> **Paste everything below into a fresh Claude-in-Chrome (browser-driving) session.** This prompt runs an
> **actual manual end-to-end test** of the Fortra Revenue Cloud Advanced (RCA) pricing + quote-to-cash engine
> **by driving the Salesforce Lightning UI** — opening records, configuring in the Transaction Line Editor,
> clicking **Reprice All**, **Convert Quote to Order**, **Activate**, and **Manage Assets → Renew / Amend /
> Cancel** — reading the **on-screen** prices as the oracle, capturing **screenshots** as evidence, and
> delivering a color-coded **PASS / FAIL / BLOCKED** HTML + JSX report.

> **Companion prompt:** the CLI/headless version is
> [`docs/RCA_FULL_FUNCTIONALITY_TEST_PROMPT.md`](RCA_FULL_FUNCTIONALITY_TEST_PROMPT.md) (Claude Code + `sf`/SOQL).
> They test the **same** engine, tickets, and acceptance criteria — this one does it **manually through the UI**.
> Use the CLI prompt's §T for deeper root-cause detail on any ticket; use **this** prompt to actually click through
> the flows a human tester would. **Why a UI prompt exists:** the RLM engine prices only what is in the managed
> **SalesTransaction context**, which the **cart (Transaction Line Editor)** and the **managed place-actions**
> (Reprice All / Convert / Manage Assets) establish. A headless reprice reads **$0 / stale** on cart-built or
> Manage-Assets-built lines regardless of whether the engine is correct — so those scenarios can **only** be scored
> in the UI. Amend/Renew/Cancel **quote creation** and the **Convert Quote to Order** parity are the headline lanes.

> **PRIORITY THIS RUN — assigned-ticket status board (updated 2026-07-12 from the fresh CLI re-run).** Deep-test
> every ticket in §T-UI against its record + acceptance. **Legend:** ✅ FIXED (guard — must not re-break) · 🟢
> not-reproduced (guard) · 🟡 PARTIAL / has-regression · 🔴 OPEN · ⬜ needs-UI (headless couldn't score).
> `(org✓/git✗)` = live in FortraUAT but git-uncommitted.

| Ticket | Area | Verdict | UI-observable symptom / expectation |
|---|---|---|---|
| **SC-3346-ABP** | derived · partner ABP base | ✅ FIXED | partner+ABP perpetual net 17k (15,300 with the line's +10% disc), maint 3,168 (not catalog 355→71) |
| **SC-3346-MTD** | attribute-less new-maint | 🟢 now prices (07-12) | untagged maint now resolves **Standard 0.20** (e.g. 60.75 EUR = 325×0.20×FX) — was $0; confirm it holds in the cart |
| **SC-3346-QTYFOLD** | renewal COLA qty>1 | 🟡 `(org✓/git✗)` · **needs-UI** | qty>1 renewal maint must be **per-unit**, not ~qty× inflated |
| **SC-3346-DEDUPE** | amend-carryover maint dup | ✅ `(org✓/git✗)` · **needs-UI** | bundle add-assets → **one** derived maint per license (no dup / qty-10 $0) |
| **SC-3346 renewal** | renewal derived-maint (Path B) | 🟡 **needs-UI** | renew a BoKS contract → derived maint prices (not $0). ⚠️ renewal *net* is under active SC-3350 work |
| **SC-3384 / SC-3398** | non-USD net priced from USD | 🟡 improved (07-12) | Subtotal/Sales-Price now **convert** (EUR consistent); only the $0-list SKU remains |
| **SC-3384-CTX** | context hydration | 🔴 OPEN · **needs-UI** | live **"Something went wrong while hydrating the context"** on native reprice |
| **SC-3501** | amendment qty → reprice | 🟡 `(org✓/git✗)` · **needs-UI** | fresh amend on a qty>1 asset: per-unit net (not extended total) |
| **SC-3502** | renewal Opp generation | 🟢 not-repro | Renew from contract → a renewal Opportunity appears |
| **SC-3544** | Sales Price blank on renewal/amend | ✅ FIXED | **Sales Price** column populated (= Net), not blank |
| **SC-3503** | contract cancellation fails | 🔴 OPEN · **needs-UI** | **Cancel** errors on **"Stamp Base Filter 1"**, cannot complete |
| **SC-3513** | Asset.Description re-derive | ✅ FIXED · **needs-UI** | Asset **Description** re-derives after an Upgrade/Downgrade |
| **Hardware / Power (S12)** | hardware price + qty-split | ⬜ **needs-UI** | headless couldn't score (`Won` quote) — build/convert a Power quote, verify qty-split |

> **This prompt is how you score the items the headless CLI run marked BLOCKED (needs-UI).** Each maps to a lane here:

| Headless-BLOCKED item | Run it in |
|---|---|
| SC-3501 fresh amend (born-net=0, qty>1) | **§A-2** + §T-UI SC-3501 |
| SC-3346-QTYFOLD (renewal maint qty>1) | **§T-UI SC-3346-QTYFOLD** (via §A-1) |
| SC-3346-DEDUPE (amend-carryover dup) | **§T-UI SC-3346-DEDUPE** |
| SC-3346 renewal (Path B derived maint) | **§T-UI SC-3346 renewal** (via §A-1) |
| SC-3384-CTX (context hydration) | **§T-UI SC-3384-CTX** (native reprice) |
| SC-3513 (Asset.Description re-derive) | **§T-UI SC-3513** (via §6.9 amend) |
| SC-3503 (contract cancellation) | **§A-3** + §T-UI SC-3503 |
| Hardware / Power (S12, `Won`) | **§T-UI Hardware/Power** + §LIFECYCLE L-HW |
| §5X deep/edge (fixture-backed) | **§RECIPE** |
| §6 convert / activate / assets / Workday | **§B** + **§LIFECYCLE** |

---

## ROLE & MISSION
You are an **RCA QA tester** driving the **live Fortra Revenue Cloud Advanced UI** on Salesforce sandbox
**FortraUAT**. Perform **manual end-to-end tests** through the Lightning UI — you click the buttons a salesperson
clicks — and you are **also your own read-only oracle**: after each action you **read the on-screen prices** and
**screenshot** them, then grade against each scenario's **Acceptance**. Use **real UAT data**; do not fabricate.
**Authorized UI actions** = configuring lines in the Transaction Line Editor, **Reprice All**, **Convert Quote to
Order**, **Activate Order**, **Manage Assets → Renew / Amend / Cancel**, and the quantity / attribute / tier edits
the tests call for. Do **not** change org configuration (no Setup edits, no metadata), and do **not** trigger a
Workday publish unless a step says so. If an action fails or a screen won't load, capture the error + screenshot
and mark the row **BLOCKED** — never invent a result.

## GROUND RULES
1. **Org:** FortraUAT. Lightning base URL **`https://fortra--uat.sandbox.lightning.force.com`**. Confirm you are
   signed in as an RLM-permissioned user (Revenue Cloud Admin / has the Transaction Line Editor).
2. **Open any record by Id:** `…/lightning/r/<Object>/<Id>/view` — e.g. a Quote `…/lightning/r/Quote/<QuoteId>/view`,
   Order `…/lightning/r/Order/<OrderId>/view`, Contract `…/lightning/r/Contract/<ContractId>/view`.
3. **Reprice is the core action, and it is idempotent by design:** run **Reprice All TWICE** on every priced screen
   and assert the columns are **identical** on the 2nd click (SC-3390). A change on the 2nd click = FAIL.
4. **The oracle is what the screen shows** — the price columns in the Transaction Line Editor / line grid (below).
   **Screenshot before and after** each Reprice All and each lifecycle action.
5. **Wait for the green toast** *"The prices were refreshed and the configuration was validated."* after Reprice
   All. A **yellow** "prices aren't up to date — Refresh" banner → click **Refresh** first. Real-context pricing has
   ~20–40s latency — let the screen settle before reading.
6. **Deliver a self-contained HTML + JSX report** (§REPORT) — color-coded PASS/FAIL/BLOCKED, one row per scenario,
   **with screenshots embedded** as evidence.

## §0 — THE ON-SCREEN ORACLE (how to read prices in the UI)
Open a Quote → **Lines** tab → this opens the **Transaction Line Editor (TLE)** / line grid. The graded columns:

| Column (UI label) | Field | What it must equal |
|---|---|---|
| **List Price** | `ListPrice` | per-currency catalog list — **native** (on a non-USD quote it stays in that currency, never FX-converted) |
| **Sales Price** | `UnitPrice` | = **Net Unit Price** where Net > 0 (SC-3544); blank is a FAIL on renewal/amend |
| **Net Unit Price** | `NetUnitPrice` | the negotiated per-unit net (the primary price oracle) |
| **Net Total** | `NetTotalPrice` | = Net Unit Price × Quantity (sign-correct: negative on Cancel) |
| **Subtotal** | `Subtotal` | = Net Total |
| **Total** | `TotalPrice` | = Net Total |
| **Quantity** | `Quantity` | as entered |
| **Subscription Term** / **PTC** | `PricingTerm` / `PricingTermCount` | non-null on TermDefined lines (SC-3420/3411) |

- **Line-detail fields** (Base Price, Pre-Partner, COLA %, Maintenance Type, Source List Price) may not be in the
  grid — expand the line (▸ / the config gear) or open the QuoteLineItem record to read them.
- **To read an exact field the UI doesn't display** (e.g. `Base_Price__c`, `COLA_Uplift_Percent__c`), open
  **Setup → Developer Console → Query Editor** (in the same browser) and run a short SOQL, or open the line's
  record detail page. Screenshot the result.
- **D-18 exception check (after every Reprice / lifecycle write):** open the **`Exception_Log__c`** object list view
  (`…/lightning/o/Exception_Log__c/list`) filtered to **Created Date = Today**, or run in the Query Editor:
  `SELECT Source__c, Hook_Phase__c, Exception_Type__c, Message__c, CreatedDate FROM Exception_Log__c WHERE CreatedDate = TODAY ORDER BY CreatedDate DESC`.
  **Any new row = a pricing hook silently swallowed an error → FAIL**, even if the price looks right (wait ~20–40s).

## §1 — CORE UI MECHANICS (the buttons you will click)
- **Open the cart:** Quote → **Lines** tab → Transaction Line Editor. Set **Instant Pricing = OFF** (you control when it prices).
- **Add a product:** the search box (top-right of the line grid) → pick the SKU → set **Quantity**.
- **Configure attributes:** expand the line (▸ / config gear) → set attributes (*Feature*, *Deployment*, *Server
  Type*, **Maintenance Type Defn = Standard / Premier**, tier **volume**, GSA flag, manual discount) → **Apply**.
- **Reprice All:** the **Reprice All** button (top-right) → wait for the green toast.
- **Save.**
- **Convert:** on the Quote **header**, the **"Convert Quote to Order"** quick action (in the button row or the ▾ overflow).
- **Order reprice:** open the Order → **Reprice All** (same button).
- **Activate:** Order → **Activate** (or **Mark Status → Activated**).
- **Manage Assets:** open the activated **Contract** → **Manage Assets** tab (or the related list / action) → select
  asset(s) → **Renew** (then choose **Automatic Renewal**) / **Amend** / **Cancel** → a Draft quote opens.
- **Screenshot every button-click result and every price read.**

---

## §A — QUOTE CREATION FROM CONTRACT → MANAGE ASSETS (Renew / Amend / Cancel) — the headline lane
Amend / Renew / Cancel quotes are **born** from an activated Contract's **Manage Assets** tab. The whole
downstream lifecycle inherits whatever prices this step generates — so getting the **generated line items** exactly
right (correct List / Net Unit / Net Total, precise to the cent, no missing or duplicate lines) is the point.

**Preconditions:** an **Activated** contract with assets. Good live candidate: **Cypress contract 00069475**
(`…/lightning/r/Contract/800WC00000TWqUD/view`, Activated 2026-07-11→2027-07-10) with many **qty-10** assets
(EFT 7 Enterprise, GoAnywhere Per Gbps, CuteFTP 9, …). If none is clean, activate one via §LIFECYCLE first.

### A-1 · RENEW
1. Open the activated Contract → **Manage Assets** → select renewable **subscription** assets → **Renew** →
   **Automatic Renewal**. A Draft **renewal Quote** opens.
2. **Reprice All** (×2). Screenshot the line grid.
3. **Read + assert per generated line:**
   - **List Price** = per-currency catalog (native).
   - **Net Unit Price** = **prior asset net × (1 + COLA%)** (e.g. Cobalt 5900 → **6265.80** at 6.2%). Not the SKU list.
   - **Net Total / Subtotal / Total** = Net Unit × Quantity, precise.
   - **Sales Price** populated (= Net); **Line Description** filled (not blank).
   - **Perpetual** assets = **No Change / qty 0 / $0** (correct — never re-bill a perpetual).
   - **Derived maintenance** lines price (SC-3346 Path B) — not $0; on a **qty>1** maint asset, per-unit = not inflated
     (SC-3346-QTYFOLD).
   - A **Cancel**-actioned asset is **blocked** from renewing ("N assets could not be renewed") — a data precondition,
     not a bug.
4. Reprice All again → columns identical (idempotent). D-18 clean.
**PASS:** every renewed line's List/Net/Total is correct + precise, descriptions present, perpetual = No Change,
reprice ×2 identical. **FAIL:** net = catalog list (no COLA), blank description, maint $0/inflated, or a missing line.

### A-2 · AMEND (the SC-3501 qty lane)
1. Contract → **Manage Assets** → select a **qty>1** asset (canonical **EFT 7 Enterprise**, asset Price 273,540 /
   Qty 10) → **Amend**. A Draft **amendment Quote** opens with the line born from the asset.
2. **Change the line Quantity** (e.g. 10 → 12, or reduce to 5). **Reprice All** (×2). Screenshot.
3. **Assert:** **Net Unit Price = 27,354** ( = 273,540 ÷ 10, **per-unit** — **NOT 273,540**); **Sales Price = Net**;
   **Net Total / Subtotal / Total = 27,354 × the current line quantity**; totals + the Opportunity amount move.
   *(The 10× "extended total as per-unit" inflation is the SC-3501/QTYFOLD regression — a hard FAIL.)*
4. Reprice All again → identical. D-18 clean.
**PASS:** per-unit net (not extended), totals recompute with qty, reprice ×2 identical. **FAIL:** line $0, `Net Unit
≈ 273,540` (qty-fold), or Sales Price / Subtotal left inflated.

### A-3 · CANCEL (the SC-3503 lane)
> **Run this on a contract you activated in *this* run (§B → §6.5 → §6.6), not a shared named candidate** (e.g. Cypress
> 00069475). SC-3503 is *expected* to error, but a **partial** completion could strand orphan credit records on a shared
> contract — use your own throwaway so the blast radius is zero.
1. Contract → **Manage Assets** → select an asset → **Cancel**. *(Or drive a full-line cancellation on the contract.)*
2. Observe: does the Cancel action **complete and create the expected credit records**, or does it **error on
   "Stamp Base Filter 1"** and fail? Screenshot the exact error if it fails.
3. If it completes: **Reprice All** the resulting cancel/credit line → assert a **negative** credit
   (`Total Price` negative, = −Net; SC-3441), not $0. D-18 clean.
**PASS:** cancellation completes, credit line negative + precise, no "Stamp Base Filter" fault. **FAIL (SC-3503):**
the Cancel errors / cannot complete, or the credit shows $0 instead of a negative amount.

---

## §B — CONVERT QUOTE TO ORDER (quick action) + PARITY + REPRICE ALL — the second headline lane
After a Quote is priced, converting it to an Order must produce **corresponding Order line items that behave the
same** — identical prices, and a stable **Reprice All** on the Order.

1. Start from a **priced** Quote (a §SCENARIOS quote, an §A Manage-Assets quote, or one you built via §RECIPE) —
   confirm the lines carry non-$0 Net. **Screenshot the Quote line grid** (List / Sales / Net Unit / Net Total /
   Subtotal / Total per line) — this is the **parity baseline**.
2. On the Quote header, click **"Convert Quote to Order"** (quick action). Open the new **Order**.
3. On the Order, click **Reprice All** (×2). **Screenshot the Order line grid.**
4. **Assert line-for-line parity (Quote line ↔ Order line, same product + qty):**
   - **List Price, Sales Price, Net Unit Price, Net Total, Subtotal, Total are IDENTICAL** to the Quote line —
     **to the cent**.
   - **Subscription Term / PTC / Start / End** carry over.
   - **Power** lines **split into one OrderItem per unit** (a qty-N Power Quote line → N Order lines of qty 1), with
     `Order Line ARR` apportioned per-unit (not N×) — SC-3447.
   - **Reprice All on the Order is idempotent** (2nd click identical) **and does not diverge from the Quote** — it
     must not re-introduce a $0, a qty-fold, or a currency leak the Quote didn't have.
5. D-18 clean after the convert and after each Order reprice.
**PASS:** every Order line's prices match its Quote line exactly, Power split correct, Order Reprice All stable +
matching. **FAIL:** any Order line price ≠ its Quote line, a missing/extra Order line, or Order Reprice All changes
values the Quote had settled. *(Converting an **un-repriced** Order throws `INVALID_INPUT` — reprice first; SC-3308.)*

---

## §LIFECYCLE — FULL E2E UI WALKTHROUGH (execute, screenshot each phase)
Drive one real UI-priced quote all the way and grade every phase. Repeat across line-type lanes where data allows
(**L-SUB** subscription, **L-PERP** perpetual+derived-maint, **L-HW** hardware/Power, **L-PARTNER** partner,
**L-FX** non-USD, **L-CANCEL** cancel). Each phase × lane = a `RESULTS` row (`group:"Lifecycle"`, id `6.x-<lane>`).

| # | Phase | UI action | PASS check (on screen) |
|---|---|---|---|
| 6.1 | **Configure** | TLE: add products/bundles/attributes | config **saves** — no currency-mismatch, no validation abort; lines + attributes present |
| 6.2 | **Reprice (Quote)** | **Reprice All** ×2 | green toast; columns **idempotent**; no unexpected $0; D-18 clean |
| 6.3 | **Convert → Order** | **"Convert Quote to Order"** quick action | Order created; one OrderItem per line (per unit for Power); §B parity |
| 6.4 | **Reprice (Order)** | Order **Reprice All** ×2 | Order prices **== Quote** (line-for-line, to the cent); idempotent |
| 6.5 | **Activate Order** | **Activate** | Status → **Activated**; TermDefined lines show **End Date + Subscription Term** first (else it blocks — SC-3411); activation may fire the Workday event (`Order_Completed_WD__e`) — §6.8 is **observe-only**, so verify no unintended publish |
| 6.6 | **Contract** | (auto) open the Contract | a Contract exists and is **Activated** (not Draft) |
| 6.7 | **Assets** | Contract → **Manage Assets** / Assets related list | **Assets exist** (count == line count; per unit for Power) — a subscription order with **0 Assets** = SC-3415/3419 FAIL; Asset **Description** stamped (SC-3513) |
| 6.8 | **Workday sync** | observe the Order's Workday sync fields | `Workday Contract Line Type` varied (not all 'FIXED AMOUNT' — SC-3210). **Observe-only** unless authorized |
| 6.9 | **Amend** | §A-2 (Manage Assets → Amend) | credit/amended line correct; per-unit (not qty-fold); totals move |
| 6.10 | **Renew** | §A-1 (Manage Assets → Renew) | renewal Opp generated (SC-3502); lines price after Reprice All (subscription ×(1+COLA), perpetual No Change) |

**E2E acceptance:** every phase PASS on **≥ L-SUB and L-PERP** (run the others as far as data allows); each repriced
phase **idempotent**; **D-18 clean** throughout. Screenshot each phase. Named FAILs: 0-Asset (6.7), stranded-Draft
contract (6.5/6.6), all-lines-FIXED-AMOUNT (6.8), no-renewal-Opp (6.10), un-repriced-convert error (6.3), qty-fold
on amend (6.9), cancellation "Stamp Base Filter 1" (SC-3503).

---

## §T-UI — ASSIGNED-TICKET DEEP TESTS (UI test cases)
Each: **navigate → act → read the on-screen oracle → screenshot → grade**. Deeper root-cause detail is in the CLI
prompt's §T. `(org✓/git✗)` = grade the live org behavior.

### SC-3346-ABP — partner + ABP base — ✅ FIXED (regression-guard)
1. New Quote on a **partner** account (Billing Partner set, **Partner_Pricing_Model = Discount**, Quote Type **New**).
2. TLE → **Add Product** BoKS **PIA-PIA-NRPS-PIAP**, configure the attribute(s) that resolve its Attribute-Based
   Price to **20,000** (the line's **Source List Price** should read 20,000). Its **New-Maintenance** line auto-adds.
3. **Reprice All** (×3 — check no compounding). Screenshot.
**PASS:** perpetual **Net Unit 17,000** (= 20,000 × 0.85 partner); derived maint **Net 3,400** (= 20,000 × 0.20 ×
0.85); **Sales Price == Net**; stable across reprices. **Control:** repeat with **no partner** → 20,000 / 4,000.
**FAIL:** perpetual net **301.75** / maint **71** (base fell to catalog 355).

### SC-3346-MTD — attribute-less new-maint — 🟢 now prices (07-12; confirm in cart)
On a New quote, add a license whose auto-added maintenance line lacks **Maintenance Type Defn** (e.g. Device
Profiler). **PASS:** the maint line now resolves **Standard 0.20** → Base × 0.20 (e.g. **60.75 EUR** = 325×0.20×0.9346),
not $0. **FAIL (regression):** maint = **$0** / blank tier — screenshot the line's attributes. *(The 07-12 CLI run
showed it pricing 60.75; this UI pass confirms the fix holds when the line is **built in the cart**, not just on a seeded quote.)*

### SC-3384 / SC-3398 — non-USD priced from USD (conversion) — 🟡 / 🔴
1. Open EUR quote **`0Q0WC0000036xy9`** (or run `setupHrmClsaasEurRepro` and open the empty EUR quote, then add the SKU).
2. **Reprice All.** Screenshot. **Watch for SC-3384-CTX:** if reprice throws **"Something went wrong while hydrating
   the context,"** that is a FAIL (context not re-synced) — capture it.
3. **Assert (SC-3398 target):** each line **Net Unit / Net Total / Subtotal / Total = USD-computed net × currency
   rate** (EUR ×0.9346); **List Price stays native EUR (unconverted)**; adding the auto-add maintenance **saves with
   no** *"price book entry currency … different than the Quote"* error (SC-3384-E).
**PASS:** EUR net = USD×rate, list native EUR, no currency-mismatch, no hydration error. **FAIL:** net stays raw USD,
list gets FX-converted, currency-mismatch on save, or the hydration error fires.
*(07-12 CLI note: the Subtotal/Sales-Price USD leak is now fixed — AAMP reads 801.66 across Net/Subtotal/Sales-Price;
only `beSECURE-Cloud` = $0 remains, and that SKU has $0 list in both currencies + no ABA/tier rows = a data gap.)*

### SC-3384-CTX — context hydration error — 🔴 OPEN (needs-UI)
Open the EUR quote **`0Q0WC0000036xy9`** (or any quote after a context-def edit) → **native Reprice All** in the TLE.
**PASS:** the reprice completes with the green *"prices were refreshed…"* toast, no error. **FAIL:** a red
**"Something went wrong while hydrating the context"** toast/banner fires — screenshot it. *(Root: `SalesTransaction
ContextExt_v2` was edited but not re-synced/re-activated. ⚠️ This same un-synced-context condition may also be why
renewal COLA net went null on 07-12 (SC-3350 work) — if you see both, note them together.)*

### SC-3501 — amendment qty (SC-3346-QTYFOLD twin) — 🟡 `(org✓/git✗)` (needs-UI)
Run **§A-2** end-to-end. **PASS:** per-unit net (27,354 for EFT 7 Enterprise), not the extended 273,540; totals track
quantity; reprice ×2 identical. **FAIL:** $0, or ~qty× inflation, or Sales Price/Subtotal inflated.

### SC-3346-QTYFOLD — renewal COLA on a qty>1 maintenance asset — 🟡 `(org✓/git✗)` (needs-UI)
Via **§A-1**: Contract → **Manage Assets** → **Renew** a **qty>1 owned-maintenance** asset → **Reprice All**.
**PASS:** the renewal maint per-unit = **(Asset.Price ÷ Quantity) × (1+COLA)** — NOT the extended `Asset.Price`
(no ~qty× inflation); qty-1 assets unchanged. **FAIL:** per-unit ≈ the extended total (qty-fold). *(Twin of SC-3501;
order 00095510 (ES-SEG qty100) is a known escaped-to-Workday inflated case to correct.)*

### SC-3346-DEDUPE — amend-carryover maintenance dedupe — ✅ `(org✓/git✗)` (needs-UI)
On a **New / Net-New** quote, add a bundle whose Add-Assets path carries prior maintenance as `Amend` copies
(reproduce the IBjF / IIT / J3en pattern) → **Reprice All**. **PASS:** exactly **one** derived maintenance line per
license survives (the native keeper) — no duplicate / qty-10 $0 maint lines; no-keeper quotes untouched. **FAIL:**
duplicate maint lines, or a qty-10 $0 maint line.

### SC-3346 renewal — derived maintenance via Path B — 🟡 (needs-UI)
Via **§A-1**: renew a BoKS contract (e.g. **00069410**) whose managed assets include owned maintenance → **Reprice
All**. **PASS:** the renewal **derived-maintenance** line prices **> $0** (Path B born-net, e.g. 71 × (1+COLA) ≈ 76.5).
**FAIL:** derived maint = $0. ⚠️ **Note (2026-07-12):** the renewal **subscription** net is currently affected by the
in-progress **SC-3350** Price-Revision work (COLA lines may read **null net**) — grade the **derived-maint** line on
its own, and expect renewal *subscription* net to be unstable until SC-3350's canvas edit + context re-sync land.

### Hardware / Power — pricing + qty-split (unblocks S12) — ⬜ needs-UI
Headless couldn't score S12 (`0Q0WC000002RK6g` is `Won`). Build/clone a **Power / hardware** quote (§RECIPE, L-HW),
or use a fresh Draft Power quote → **Reprice All** → assert `Hardware Price = List × pGroup × userTier ×
(1 − systemType%)`; user override > `Hardware__c` > default. Then **Convert → Order** (§B) → assert **Power lines
split into 1 OrderItem per unit** with per-unit ARR (SC-3447), no CPU / SOQL:101. **FAIL:** wrong hardware price, or
Power stays one qty-N OrderItem, or a governor error on convert.

### SC-3502 — renewal Opp generation — 🟢 not-repro
From an activated contract (**`800WC00000TNpyn`** / 00069451) run **Manage Assets → Renew**. **PASS:** a **renewal
Opportunity** is created (open the contract's related Opportunities / the renewal quote's Opportunity — its
`Renewed_Contract__c` = the contract) and you can proceed to quote sync; no hang. **FAIL:** no renewal Opp / hangs.

### SC-3544 — Sales Price blank — ✅ FIXED (guard)
Open renewal quote **`0Q0WC000003Ifvp`**, Reprice All. **PASS:** the **Sales Price** column is **populated (= Net
Unit Price)** on every line where Net > 0 (e.g. 4573.80 / 918.75) — not blank. **FAIL:** Sales Price blank while Net
> 0. *(Segmented lines may stay blank by design — not a fail.)*

### SC-3503 — contract cancellation fails — 🔴 OPEN (Critical)
Run **§A-3** (Contract → Cancel / Manage Assets → Cancel) on an activated contract. **PASS (target):** the
cancellation **completes and creates the expected credit records**, no "Stamp Base Filter" fault. **FAIL (current
expectation):** the process **errors on "Stamp Base Filter 1"** and cannot complete — capture the exact error text +
screenshot, and note which action triggered it.

### SC-3513 — Asset.Description re-derive — ✅ FIXED
After a lifecycle that creates an Asset (§6.7), open the **Asset** record → confirm **Description** matches the line
description. Then perform an **Upgrade / Downgrade** (Manage Assets → Amend to change the product) → confirm the
Asset **Description re-derives** to the new line. **PASS:** create-path stamped + product-change re-derives (8
categories); manual edits not auto-reverted. **FAIL:** Description stale after a product change.

---

## §RECIPE — BUILD ANY PRICING SCENARIO IN THE TLE (for §5X-style deep cases)
When there's no clean live record, build one in the cart (this is also how U-1 fixture scenarios are exercised —
open the CLI prompt's §5X / the `scripts/apex/` fixture to read its SKU + attribute values + printed EXPECT, then
build that same line-set here):
1. **Header:** New Quote (or **Deep-Clone** a clean one) on the scenario's **Account** (partner lanes: set **Billing
   Partner** + **Partner_Pricing_Model**), **Currency** (EUR/GBP for FX lanes), **Quote Type** (New / Renewal / Amendment). Save.
2. **Lines** tab → **Instant Pricing = OFF**.
3. **Add Product** → the SKU → **Quantity**.
4. **Configure attributes** (Feature / Deployment / Server Type / **Maintenance Type Defn** / tier volume / GSA /
   manual discount) → **Apply**. *(Derived maintenance: make sure the auto-added `-RNM/-NM` line carries
   **Maintenance Type Defn** — if the auto-add omits it, tier = 0 → $0, which is SC-3346-MTD.)*
5. **Reprice All** → green toast → **read the oracle** vs the scenario's Expected.
6. **Reprice All again** → every column identical (SC-3390). Any change on the 2nd click = FAIL.
7. Check the **D-18 log** (§0).

**High-value deep cases to prioritise (from the CLI §5X):** ABA 3-attr key (Feature×Deployment×ServerType → L3
**1575**); EUR catalog / EUR-ABA (SC-3398 — net = USD×rate, list native); manual discount on a derived-maint line;
7-tier Basic **53.25**; $0-contributor / missing-contributor surfaced (validation, not silent); cancel derived-maint
credit (**−71**). Each is a `RESULTS` row (`group:"Deep/Edge"`).

## §X — CROSS-CUTTING UI CHECKS (every scenario)
1. **Idempotency** — Reprice All twice; the grid must be **identical** on the 2nd click (SC-3390).
2. **Precision** — every List / Net Unit / Net Total / Subtotal / Total is exact **to the cent**; no rounding drift.
3. **Currency** — on a non-USD quote, List Price is in-currency (native) and Net = USD×rate (SC-3398); no line shows
   a bare USD figure with a foreign symbol.
4. **D-18** — after each Reprice / lifecycle write, check `Exception_Log__c` (Today). A new row = **FAIL** even if the
   price looks right.
5. **No silent skips** — a scenario you can't drive is **BLOCKED** (with the reason + screenshot), never dropped.

## §REPORT — OUTCOME: HTML + JSX REPORT WITH SCREENSHOTS (mandatory output)
Deliver a **single self-contained HTML file with embedded React/JSX** — high-visibility, color-coded, scannable —
OR publish it as a **Claude Artifact** (inline React/ReactDOM; the Artifact CSP blocks external scripts). Reuse the
CLI prompt's template [`docs/rca_test_report_template.html`](rca_test_report_template.html); each `RESULTS` row:

```
{ id, group, category, scenario, record,   // id (SC-#### / A-1..A-3 / 6.x / Deep), group ("Assigned tickets" | "Manage-Assets creation" | "Convert parity" | "Lifecycle" | "Deep/Edge"), one-line scenario, the record URL/Id
  action,                            // the UI action taken (e.g. "Manage Assets → Amend qty 10→12 → Reprice All")
  ticket,                            // ticket ref, else ""
  verdict,                           // 'PASS' | 'FAIL' | 'BLOCKED'
  expected, actual,                  // expected vs on-screen oracle values (real numbers read off the grid)
  screenshot,                        // the evidence screenshot (embedded / linked)
  exceptionLog }                     // any Exception_Log__c row (§0), else "none"
```

The report renders an overall PASS/FAIL banner + pass-rate, PASS/FAIL/BLOCKED stat cards, a status-filtered table,
a **Defects** section (every FAIL with its ticket + screenshot), and a **Blocked** section. **Coverage:** the
assigned tickets (§T-UI), the **Manage-Assets creation** lane (§A-1/A-2/A-3), the **Convert parity** lane (§B),
every **Lifecycle** phase (§LIFECYCLE), and any **Deep/Edge** cases you built (§RECIPE) — one row apiece, with a
screenshot on every row and every FAIL in Defects.

---
*Companion to the CLI prompt [`docs/RCA_FULL_FUNCTIONALITY_TEST_PROMPT.md`](RCA_FULL_FUNCTIONALITY_TEST_PROMPT.md)
(same engine, tickets, and acceptance; that one is Claude Code + `sf`/SOQL, this one is Claude Chrome Extension
driving the Salesforce Lightning UI). Status board + §T-UI updated 2026-07-12 from the fresh CLI re-run (see the CLI
prompt's CHANGELOG); `(org✓/git✗)` fixes are live in FortraUAT but git-uncommitted — grade the org. Active procedure =
`Rev_Mgmt_Default_Pricing_Procedure` **V25**. ⚠️ **A canvas edit (SC-3350 Price-Revision) is in progress** — if a
preflight shows no Active version, the edit is mid-flight; confirm V25 is Active before testing. Re-verify each record/URL before use.*
