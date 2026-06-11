# SC-3350 — Platform Mechanism: How RLM Renewals & Pricing Actually Work

Companion to [README.md](README.md). Grounds the ticket's central thesis against the **Salesforce Revenue
Cloud Developer Guide v67.0 (Summer '26, updated 2026‑06‑05)** and live Fortra config. Full citations + URLs
in [evidence/research-notes/context_platform_web.md](evidence/research-notes/context_platform_web.md).

---

## The correction that reframes the whole fix

The prior brief said: *"renewal quotes are generated headlessly and never run a full pricing reprice — that's
why COLA + description prehooks never fire."* The **outcome** is right; the **mechanism** is wrong, and the
difference opens supported fix paths.

> **"Renewals can never reprice" is FALSE.** The platform makes pricing on renewal an explicit, parameterized
> option. Fortra's renewal flow simply doesn't use it. This is a **config choice, not a platform limitation.**

---

## The native levers (all first‑class, all supported)

| Lever | What it does | Relevance to SC‑3350 |
|---|---|---|
| **`initiateRenewal` → `skipPricing`** (boolean, API v64+) | "Indicates whether the pricing procedure must be skipped (true) or performed (false)." All doc samples set `false`. | Fortra's flow **omits it** → pricing outcome left to platform default + config. Setting `false` forces the procedure (→ COLA + description prehooks). |
| **`Asset.PricingSource`** (`LastTransaction` \| `PriceBookListPrice`, v60+) | "Pricing source to use when amending or renewing an asset." A fixed‑% uplift is **ignored** unless base = `LastTransaction`. | **The decisive native control for defect #1.** If Fortra renewable assets are `PriceBookListPrice`, that *alone* produces "priced at plain list." Possible near‑one‑field fix. |
| **Place Sales Transaction `pricingPref=Force`** (v65+) | "Force — reprices all lines." (Place **Quote** is **deprecated v63+** — don't use it.) | A post‑creation forced reprice runs the whole prehook chain → fixes **#1 and #2 together**. |
| **`UnitPriceUplift`** (QLI %, v65+) | Native per‑line percentage uplift; carries to the asset on activation. | Native equivalent of a flat COLA %. |
| **`PriceRevisionPolicy` + `IndexRate` + `PriceRevision` element** (v65+) | Native **CPI/index‑based uplift** built into the standard pricing procedure (e.g. `MAX(PriceIndex + 5, 8)`). | **COLA is a textbook CPI uplift on renewal** — Salesforce has a purpose‑built native mechanism. Fortra reimplemented it in custom Apex + CMDT. Worth a "use native?" architecture review. |
| **`OriginalActionType`** (`Amend\|Cancel\|Renew\|Transfer`, v61+) | Procedure Plans route by transaction type. | Correct gate for a renewal‑only uplift (Fortra's V10 already gates the COLA step on `ActionType='Renew'`). |
| **Get Renewable Assets Summary** note | "Doesn't support providing a summary with procedure plans. As a result, renewal line items may return a price of zero." | A documented **native $0 footgun** for renewal lines — independent of Fortra code; relevant to the $0 rollups seen. |

---

## Salesforce's recommended architecture (and why the trigger is the anti‑pattern)

Salesforce's guidance is unambiguous: **do renewal uplift in the pricing layer**, never a trigger.

- **Custom Apex uplift** belongs in a pricing‑procedure **prehook** — `RevSignaling.SignalingApexProcessor`
  attached to a **Procedure Plan** (requires the *Procedure Plan Orchestration for Pricing* toggle). Prehooks
  operate on the pricing **context instance**, run **inside** a pricing pass, and can participate in the
  waterfall. cloud‑update: prehooks *"avoid trigger complexities."*
- A **trigger** fires on QLI insert/update DML — the path a **headless** renewal takes — but runs **outside**
  pricing orchestration. It can't see the context, can't join the waterfall, and **does not cause the
  registered prehook chain (including `QLDescriptionGeneratorPrehook`) to run.**

> This is the structural reason **defect #2 tracks defect #1**: both the COLA prehook *and* the description
> prehook live in the procedure layer, which the trigger‑only headless renewal never enters. One real pricing
> pass fires both. That is exactly why "force a reprice on renewal" is the unifying fix — and now it's grounded
> in supported APIs, not a workaround.

---

## Live Fortra config (the decisive facts)

- **Two active renewal flows** — and it's unresolved which the live "Renew" button uses:
  - `Fortra_Create_Renewal_Quote` **v6** (Marc DeBrey, overrides `quotingAI__createRenewalQuote`): calls
    `initiateRenewal` passing only asset/output/opportunity/contract/dates — **`skipPricing` absent**, and
    **no** Place Quote / Place Sales Transaction / Reprice / pricing subflow after the call. → renewal pricing
    is entirely unforced.
  - `Fortra_Renewal_Quote_Creation` **v1** (Joe Martinez): **bypasses `initiateRenewal`**, manually inserts
    QLIs with `UnitPrice = ContractLineItem.UnitPrice` and relies on the `COLAUpliftHandler` trigger. Its
    success screen literally says *"COLA pricing will be automatically applied … via the COLAUpliftHandler."*
    This is the literal trigger‑only path.
- The **V10 pricing procedure** already has the correct COLA wiring (Path A gated on `ActionType='Renew'` +
  `DerivedPricingAttribute=false` + `ItemPricingSource='LastTransaction'`, writing `COLACalculatedPrice__c →
  InputUnitPrice`; Path B for MDT/maintenance lines). The wiring isn't the problem — **nothing forces the
  procedure to run on a renewal.**

---

## What this means for the fix (the recommended sequence)

1. **First, the cheap diagnostics** (see [01_OPEN_QUESTIONS_AND_RECOMMENDATION.md](01_OPEN_QUESTIONS_AND_RECOMMENDATION.md) §B):
   `Asset.PricingSource` distribution; which renewal flow is live; a debug‑log trace of one fresh renewal to
   see whether the procedure runs at all (the `skipPricing`‑omitted **default is undocumented** — the single
   highest‑value unknown).
2. **Then the architectural fix** (pending Marc/German, §A1): make the renewal **actually run pricing** —
   `skipPricing=false` on `initiateRenewal` and/or a post‑creation **Place Sales Transaction `pricingPref=Force`**,
   with `Asset.PricingSource=LastTransaction` as the base. One pricing pass → COLA applied **and** description
   generated → both defects resolved, and the `COLAUpliftHandler` trigger can be retired (closing the
   split‑brain).
3. **Open architecture question worth raising:** should Fortra adopt the **native** `PriceRevisionPolicy` /
   `IndexRate` / `PriceRevision` CPI mechanism instead of the bespoke Apex COLA stack? It's purpose‑built for
   exactly this, but is v65+ and may not cover Fortra's 3‑tier override + multi‑year compounding without work.

---

## Sources

Revenue Cloud Developer Guide v67.0 (PDF, primary) + Salesforce Help "Apex Hooks", cloud‑update "Apex Hooks"
and "Renewal Uplift", arraytrail "Procedure Plans" and "When to Refresh/Reprice." Exact line cites and URLs:
[evidence/research-notes/context_platform_web.md](evidence/research-notes/context_platform_web.md) §Sources.
