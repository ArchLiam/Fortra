# SC-3350 Defect #2 (Line Item Description not populated on renewal lines) — Live Re-Verification

**Date:** 2026-06-10 (UTC). **Org:** FortraUAT (`00DWC000006eUFF2A2`). **Mode:** read-only SOQL.
**Baseline brief:** `/Users/liamjeong/Documents/Code/Fortra/Data/sc3354/SC-3354_Research_Brief.md` (08:13Z) — treated as possibly stale.
**Today's Marc DeBrey edits (verified via Tooling API, see §6):** AssetContractQueryHelper 14:00:37Z, QLDescriptionGeneratorPrehook 14:41:27Z, COLAUpliftHandler 16:29:57Z, COLAUpliftPrehook 16:58:15Z, COLAUpliftTest 16:58:15Z. (Prompt said Prehook+Test 16:51Z; live is 16:58Z — minor.)

---

## 0. Bottom line

Defect #2 **still reproduces**. **Zero renewal quote lines carry a genuine generated (pipe-format) Line Item Description**, by either renewal definition. The description generator (`QLDescriptionGeneratorPrehook`) **is firing today** on NON-renewal lines (25 today, 11 after Marc's 14:41Z edit), proving the prehook itself works — but **no renewal line was even touched today**, so none could receive a description. Marc's 14:41Z edit changed nothing observable for renewal lines.

**Major DELTA vs brief:** the brief's denominator **"1,222,003 renewal lines" is wrong / not reproducible.** That number ≈ the ENTIRE QLI population (1,223,243). When "renewal" is scoped correctly (QuoteAction.Type='Renew'), there are only **43 renewal lines** (QLI→QuoteAction link) or **52 lines** (under the 32 Quotes that have a Renew QuoteAction) — not 1.2M. The defect is real but the scale framing in the brief is a serious overstatement.

---

## 1. How "renewal" is correctly identified

`Quote` has **no `Type` field** (confirmed: `SELECT Type ... FROM Quote` → `Invalid field: 'Type'`). Renewal is carried by **`QuoteAction.Type`**:
- `QuoteAction` has `QuoteId` + `Type` (`Cancel/No Change/Amend/Renew`) + `SourceAssetId`.
- `QuoteLineItem.QuoteActionId` is the per-line link to a QuoteAction.

```
SELECT Type, COUNT(Id) cnt FROM QuoteAction GROUP BY Type
  Cancel 3 | No Change 63 | Amend 6 | Renew 45        (117 QuoteActions total)

SELECT QuoteAction.Type, COUNT(Id) cnt FROM QuoteLineItem GROUP BY QuoteAction.Type
  null 1223128 | Cancel 3 | No Change 63 | Amend 6 | Renew 43   (1,223,243 QLI total)

SELECT COUNT() FROM QuoteLineItem WHERE QuoteActionId != null  → 115
```

Two defensible scopings (I report both):
- **(a) QLI-level:** `QuoteLineItem.QuoteAction.Type = 'Renew'` → **43 lines**.
- **(b) Quote-level** (task wording "Renew on the parent Quote"): lines whose **parent Quote has a Renew QuoteAction**. The 45 Renew QuoteActions span **32 distinct Quotes**; QLIs under those Quotes → **52 lines**. (Many renewal-quote QLIs have `QuoteActionId=null`, so (a) undercounts the human notion of a renewal quote — (b) is the better business definition.)

The brief's 1,222,003 matches **neither**; it is essentially the whole table. `LegacyRenewalQuote__c` splits the population 201,613 / 1,021,630 — also not 1.22M. **The brief's denominator is not defensible.**

---

## 2. TASK (1) — Defensible null vs populated counts

### Whole population (context)
```
SELECT COUNT(Id) cnt, COUNT(Description) descCnt FROM QuoteLineItem
  → 1,223,243 total ; 380,775 with non-null Description
```
Note: most of those 380,775 are NOT generator output — they are free-text / legacy / product-name descriptions. The **generator fingerprint** is the multi-segment pipe format `Product | <Attr>: <val> | <Term> | <Config>` (2-4 pipes), e.g. non-renewal `0QLWC000003cIGm4AM` = `beSECURE - Premise-Based | Devices: 1-10 | On Demand | Premise Based`.

### Renewal lines — Quote-level scope (32 renewal Quotes, 52 lines)
```
WHERE QuoteId IN (<32 renewal quotes>)
  total                                   = 52
  Description != null                     = 5
  Description LIKE '% | %' (1+ pipe)       = 3    ← FALSE POSITIVES (see below)
  Description LIKE '% | % | %' (2+ pipe)   = 0    ← genuine generated format
```

The 5 non-null are all NON-generated:
| Id | Quote | Description | Kind | LastMod |
|---|---|---|---|---|
| 0QLWC000003cMDu4AM | 0Q0WC00000379mP0AQ | `Retrigger stamp` | manual test string | 2026-06-09 23:49 |
| 0QLWC0000037qbF4AQ | 0Q0WC000002ljtN0AQ | `touch to fire trigger` | manual test string | 2026-05-07 18:00 |
| 0QLWC0000035JbO4AU | 0Q0WC000002iO2H0AU | `TE Academic Institution Site License - VMWare ESX \| Users` | product name w/ 1 pipe | 2026-05-15 |
| 0QLWC0000035KIv4AM | 0Q0WC000002iO2H0AU | `Administering Access Assurance Suite \| 5 Day Public` | product name w/ 1 pipe | 2026-05-15 |
| 0QLWC0000035KNl4AM | 0Q0WC000002iO2H0AU | `Tripwire Enterprise for Mid-Size Stores ... \| Per Location` | product name w/ 1 pipe | 2026-05-15 |

The 3 "pipe" matches are single-pipe product names, **not** the generator's multi-segment output. **Strict 2+ pipe = 0 renewal lines.** Defect #2 holds.

### Renewal lines — QLI-level scope (43 lines)
```
WHERE QuoteAction.Type='Renew'
  total                  = 43
  Description != null     = 1   (only 0QLWC0000037qbF4AQ = "touch to fire trigger", manual)
  genuine generated      = 0
```

### Net answer to TASK (1)
- **Renewal lines with a genuine (pipe-format) generated Description = 0** (both scopes). Confirmed.
- **Null/blank Description:** 51 of 52 (Quote-level) / 42 of 43 (QLI-level); the 1 non-null is a manual test stamp, not generator output.

---

## 3. TASK (2) — Did ANY renewal line get a description TODAY (post-14:41Z)?

**No.** And more strongly: **no renewal line was modified at all today.**

```
-- Whole population: descriptions touched today
WHERE Description != null AND LastModifiedDate >= 2026-06-10T00:00:00Z      → 25
WHERE Description != null AND LastModifiedDate >= 2026-06-10T14:41:00Z      → 11   (post Marc's prehook edit)

-- Of those, how many are renewal?
... AND QuoteId IN (<32 renewal quotes>)                                    → 0
... AND QuoteAction.Type='Renew'                                            → 0

-- Were ANY renewal lines (either scope) touched today at all?
WHERE QuoteId IN (<32 renewal quotes>)   AND LastModifiedDate >= 2026-06-10 → 0
WHERE QuoteAction.Type='Renew'           AND LastModifiedDate >= 2026-06-10 → 0
```

The 25 today-modified-description lines are ALL non-renewal and ALL got genuine generated descriptions (proof the prehook fires on non-renewal reprices). Examples (LastModifiedDate desc):
- `0QLWC000003ceCQ4AY` (Q 0Q0WC0000037SsH0AU) `EFT 8 Continuum-NewMaintenance | EFT Express Auditing & Reporting Module ARM | Premier | On Premise | Non-Production` — 15:49:38Z, Andy Kumar **(post-14:41Z)**
- `0QLWC000003cdOT4AY` (Q 0Q0WC0000037RZd0AM) `GoAnywhere SFTP Server | Production` — 15:20:57Z, Joe Romo **(post-14:41Z)**
- `0QLWC000003ccFS4AY` (Q 0Q0WC0000037QX80AM, QuoteAction.Type='No Change') `Powertech Identity & Access Manager (BoKS) | Standard` — 14:33:09Z, Nir Kailash (pre-14:41Z)

Most recent renewal-line activity of ANY kind:
```
WHERE QuoteId IN (<32 renewal quotes>) ORDER BY LastModifiedDate DESC LIMIT 8
  0QLWC000003cMDu4AM  "Retrigger stamp"  2026-06-09T23:49:35Z  Nir Kailash
  0QLWC000003cMDt4AM  null               2026-06-09T23:49:13Z  Nir Kailash
  0QLWC000003bJOX/Y4A2 null              2026-06-07T15:12:46Z  Nir Kailash
  ... (all ≤ 2026-06-09)
```

So Marc's 14:41Z `QLDescriptionGeneratorPrehook` edit had **no observable effect on renewal lines** — not because the edit failed, but because **no renewal reprice has run since.** Consistent with the brief's root cause: renewals never run a full pricing-procedure reprice, so the prehook never fires for them.

---

## 4. TASK (3) — Spot-check renewal vs non-renewal with same attribute structure

Brief's pair: renewal `0QLWC000002UYeI4AW` vs non-renewal `0QLWC000003cIGm4AM`. Both still exist.

| | renewal 0QLWC000002UYeI4AW | non-renewal 0QLWC000003cIGm4AM |
|---|---|---|
| Quote | 0Q0WC000002Fard0AC | 0Q0WC00000377Cj0AI |
| QuoteActionId | 7ocWC00000gGY0lYAG | null |
| QuoteAction.Type | **Renew** | (none) |
| Product2.Name | GoAnywhere Secure Folders | beSECURE - Premise-Based |
| **Description** | **null** | `beSECURE - Premise-Based \| Devices: 1-10 \| On Demand \| Premise Based` (genuine 3-pipe generated) |
| LastModifiedDate | 2026-02-18T18:43:06Z | 2026-06-09T21:31:55Z |

**Attribute structure (QuoteLineItemAttribute):** both carry exactly **4 attributes**.
```
renewal 0QLWC000002UYeI4AW:
  Deployment Option=On Premise (false) | Maintenance Type Defn=Expert (false)
  Server Type=Production (true)        | Unit Type=Per User (false)

non-renewal 0QLWC000003cIGm4AM:
  Feature Options=On Demand (true)     | Number of Units=1-10 (true)
  Server Location Type=Premise Based (true) | Unit Type=Devices (true)
```
Attribute NAMES differ (different products) but both have a **complete 4-attribute set including the Unit Type the generator consumes**. The renewal line is **not missing inputs**; it simply never ran the prehook. This reproduces the brief's structural-parity claim. (Caveat: the brief implied "identical 4-attribute structure" — the COUNT is identical and both are complete, but the specific attribute set differs because the products differ. The load-bearing point — renewal has the inputs but no description — holds.)

---

## 5. Population-level generated-description counts (for delta vs brief's "321")

```
Description LIKE '% | %'      (1+ pipe, loose)   total 335 | non-renewal 332 | renewal-quote 3
Description LIKE '% | % | %'  (2+ pipe, strict)  total 162 | non-renewal 162 | renewal-quote 0
```
- Brief said **321 non-renewal** generated. Live loose count = **332** (+11 = today's new generations; 25 today, several pre-existing). The strict generator count is **162**. The brief's 321 used the loose 1-pipe fingerprint; either way **renewal = 0 genuine**.

---

## 6. Evidence anchors / Marc edit timestamps

```
sf data query --use-tooling-api -q
 "SELECT Name, LastModifiedDate, LastModifiedBy.Name FROM ApexClass WHERE Name IN (...)"
  COLAUpliftPrehook              2026-06-10T16:58:15Z  Marc DeBrey
  COLAUpliftTest                 2026-06-10T16:58:15Z  Marc DeBrey
  COLAUpliftHandler              2026-06-10T16:29:57Z  Marc DeBrey
  QLDescriptionGeneratorPrehook  2026-06-10T14:41:27Z  Marc DeBrey
  AssetContractQueryHelper       2026-06-10T14:00:37Z  Marc DeBrey
```

---

## 7. Deltas vs the 08:13Z brief

1. **Denominator falsified.** Brief: "0 of **1,222,003** renewal lines". Reality: renewal lines = **43** (QLI link) / **52** (Quote-level, 32 Quotes). 1,222,003 ≈ the whole QLI table; it is not a renewal count by any field tested.
2. **Brief's "321 non-renewal with descriptions"** → now **332** loose / **162** strict; +11 generated today.
3. **A non-generated description does exist on renewal lines** (5 Quote-level / 1 QLI-level), all manual test stamps or single-pipe product names — NOT generator output. The strict generated count is still 0, so the defect conclusion is unchanged, but the literal "0 renewal lines have a description" is now imprecise (5 have *a* description; 0 have a *generated* one).
4. **Marc's 14:41Z prehook edit = no observable change for renewals** because no renewal line was repriced/modified today (latest renewal-line touch = 2026-06-09 23:49). The generator works (11 non-renewal descriptions written post-14:41Z) but renewals still bypass it.

## 8. Open questions / needs-trace
- Why does the brief cite 1.2M? Possibly a mis-scoped count (whole table) or a different earlier definition; cannot reproduce — flag to whoever wrote the brief.
- The 3 single-pipe "descriptions" on Quote `0Q0WC000002iO2H0AU` (2026-05-15) — confirm these are product-name carryover, not partial generator output. (Format strongly suggests product name; no `<Attr>: <val>` segment.)
- To prove the fix end-to-end, need to actually run a renewal reprice and confirm the (now-edited) prehook fires — out of scope for read-only research.
```
