# SC-3350 — Code/B1: AssetContractQueryHelper multi-asset collapse + rates

**Stream:** Code/B1 (multi-asset contract override + rate plumbing)
**Date:** 2026-06-10 (research conducted ~17:00Z+)
**Org:** FortraUAT (read-only)
**Author of class under review:** Marc DeBrey (re-edited TODAY 14:00:37Z)
**Grounding brief:** `Data/sc3354/SC-3354_Research_Brief.md` (08:13Z) — B1 row, section 5

---

## TL;DR (the answer to the assigned questions)

1. **Did Marc's 14:00Z rework FIX B1? → NO.** The rework is a **pure structural refactor** (extract-method into two `@TestVisible` helpers for testability). The defective keying is preserved **byte-for-byte semantically**: the contract→asset relationship is STILL stored in a `Map<Id, Id> contractToAssetMap` **keyed by `ContractId`** (current line 104-107), so a contract with N assets collapses to ONE surviving asset (last ACR wins the `.put`). B1 is **still HIGH and still live.**
2. **Other behavior changes: NONE that affect output.** Only additions: null-guards on `contractId` (in `collectContractIds`) and empty-list guards (in `buildResults`). These are defensive no-ops on the happy path; they do not change which assets get wrappers. Output of `queryAssetContracts` is identical for any real input.
3. **Live multi-asset shape STILL EXISTS** — re-verified against the org: contract `800WC00000PCpoMYAT`, `Activated`, `COLA_Override_Percent__c=4`, persist `2028-05-15` (future → VALID), **4 ACRs → 4 distinct assets**. The bug actively mis-prices 3 of 4.

---

## 1. Files diffed & provenance

| Role | Path | Live LastModified |
|---|---|---|
| CURRENT (today) | `Data/sc3350/live/unpackaged/classes/AssetContractQueryHelper.cls` (123 lines) | `2026-06-10T14:00:37Z` Marc DeBrey |
| PRIOR (08:04 snapshot) | `Data/cola-renewal-review/live/classes/AssetContractQueryHelper.cls` (80 lines) | — |

**Provenance confirmation:** I pulled the live org `ApexClass.Body` via Tooling API and diffed against the `sc3350/live/unpackaged` snapshot → **byte-identical** except a trailing newline. So the snapshot I analyzed IS current org truth. Live `ApiVersion=66`, `LengthWithoutComments=3063`, Id `01pWC000001wN3hYAE`.

SOQL used:
```
SELECT Body FROM ApexClass WHERE Name='AssetContractQueryHelper'   (--use-tooling-api)
SELECT Name, LastModifiedDate, LastModifiedBy.Name FROM ApexClass WHERE Name IN (...) ORDER BY LastModifiedDate
```
The 5 COLA classes' live LastModified timestamps line up with the task framing:
AssetContractQueryHelper 14:00:37Z · QLDescriptionGeneratorPrehook 14:41:27Z · COLAUpliftHandler 16:29:57Z · COLAUpliftPrehook 16:51:20Z · COLAUpliftTest 16:51:20Z. All Marc DeBrey.

> NOTE on "+62/-19, nearly doubled": the line growth is almost entirely **new doc-comments + extract-method scaffolding + @TestVisible helpers**, NOT new logic. `LengthWithoutComments` is only 3063 chars. The doubling is testability plumbing, not a behavior rewrite.

---

## 2. The keying logic — quoted from CURRENT source

The collapse happens in the NEW `buildResults` helper (current lines 103-107):

```apex
// Map each ContractId to the Asset its relationship points at.
Map<Id, Id> contractToAssetMap = new Map<Id, Id>();
for (SObject acr : relationships) {
    contractToAssetMap.put((Id)acr.get('ContractId'), (Id)acr.get('AssetId'));   // <-- keyed by ContractId
}

for (Contract c : activatedContracts) {            // iterates CONTRACTS, not ACRs
    if (!contractToAssetMap.containsKey(c.Id)) { continue; }
    AssetContractData data = new AssetContractData();
    data.assetId = contractToAssetMap.get(c.Id);   // <-- exactly ONE assetId per contract
    ...
    results.add(data);                              // <-- ONE wrapper per activated contract
}
```

For contract `800WC00000PCpoMYAT` with 4 ACRs, the loop calls `.put(sameContractId, assetId)` four times; the map ends with a SINGLE entry whose value is whichever ACR was iterated LAST (SOQL order, non-deterministic but typically last-created). Then the contract loop runs once and emits ONE wrapper. → 3 of 4 assets get **no AssetContractData row at all.**

### How the OLD (08:04) version did it — same bug, inline

Old lines 46-72 had the identical `Map<Id,Id> contractToAssetMap` keyed by `contractId`, populated in the ACR loop, then read once per contract in the `for (Contract c : contracts)` build loop. The refactor lifted lines 46-53 into `collectContractIds(...)` and lines 64-72 into `buildResults(...)`. **The map type, key, and one-wrapper-per-contract emission are unchanged.**

### Unified diff (semantic summary)

- REMOVED: inline `Set<Id> contractIds` + inline `contractToAssetMap` build loop (old 46-53) → REPLACED by `collectContractIds(relationships)` call.
- REMOVED: inline `for (Contract c : contracts)` wrapper-build loop (old 64-72) → REPLACED by `buildResults(relationships, contracts)` call.
- ADDED: `collectContractIds(List<SObject>)` `@TestVisible` — builds the contractId set, NEW null-guard `if (contractId != null)`.
- ADDED: `buildResults(List<SObject>, List<Contract>)` `@TestVisible` — rebuilds `contractToAssetMap` (still keyed by ContractId!), NEW empty-list guards, NEW `containsKey` skip for contracts no ACR references.
- ADDED: ~40 lines of doc-comments.

**No fix. The extract-method even RE-CREATES the same `Map<Id,Id>` keyed by ContractId inside `buildResults`.**

---

## 3. Downstream consumer confirms the collapse propagates (COLAUpliftHandler 16:29Z)

`COLAUpliftHandler.getContractOverrides` (current lines 410-424) calls `queryAssetContracts(assetIds)` then `buildContractOverrideMap(contractDataList)`.

`buildContractOverrideMap` (current lines 436-482) keys its output `Map<Id, ContractOverride> overrideMap` **by `contractData.assetId`** (line 475-476):
```apex
// Only use the first valid activated Contract per Asset
if (!overrideMap.containsKey(contractData.assetId)) {
    overrideMap.put(contractData.assetId, colaOverride);
}
```
Because only ONE assetId ever arrives from `queryAssetContracts` for a multi-asset contract, the override map has **one asset key**, not four. The other three assets miss the override lookup downstream and fall to the CMDT rate path (and `COLA_Source__c` is then mislabeled `CMDT Lookup` instead of `Contract Override` — consistent with the brief's B1 description; COLA_Source labeling is set further down the handler, not re-verified line-by-line in this stream).

The handler comment at line 473-474 even ASSERTS the false invariant: *"In practice, there should only be one active Contract per Asset"* — but the data violates the **inverse** (one Contract → MANY assets), which is the actual collapse axis. The comment guards the wrong direction.

---

## 4. Live data verification — multi-asset shape STILL present

SOQL:
```
SELECT Id, Status, COLA_Override_Percent__c, COLA_Override_Persist_Until__c
  FROM Contract WHERE Id='800WC00000PCpoMYAT'
```
→ `Activated | COLA_Override_Percent__c=4 | persist 2028-05-15`. Persist date is in the FUTURE → `buildContractOverrideMap` marks it `isValid=true` (line 460 `persistUntil >= today`). So this override is LIVE and SHOULD apply to all 4 assets but reaches only 1.

```
SELECT Id, AssetId, ContractId FROM AssetContractRelationship
  WHERE ContractId='800WC00000PCpoMYAT' ORDER BY AssetId
```
→ 4 rows:
| ACR Id | AssetId |
|---|---|
| 12VWC000001RSyv2AG | 02iWC000007RVDNYA4 |
| 12VWC000001RSyw2AG | 02iWC000007RVDOYA4 |
| 12VWC000001RSyx2AG | 02iWC000007RVDPYA4 |
| 12VWC000001RSyy2AG | 02iWC000007RVDQYA4 |

(The brief cited the asset IDs as `02iWC000007RVDN/DO/DP/DQ` — confirmed exactly.)

```
SELECT Id, Name, Price, Product2Id, Product2.Name FROM Asset
  WHERE Id IN (the 4) ORDER BY Id
```
→ all 4 are the SAME product `5250 Integrator` (`01tWC00000DD119YAD`), but prices DIFFER:
| AssetId | Price |
|---|---|
| 02iWC000007RVDNYA4 | 6063.75 |
| 02iWC000007RVDOYA4 | 6063.75 |
| 02iWC000007RVDPYA4 | 6063.75 |
| 02iWC000007RVDQYA4 | 2021.25 |

**Dollar-impact note:** since 3 assets share 6063.75 and one is 2021.25, the @4% contract override (vs whatever CMDT rate the `5250 Integrator` solution-category carries) is mis-applied to 3 of 4 lines on every renewal of this contract. The mis-priced delta is per-asset Price × (CMDT% − 4%). Which single asset is "saved" is SOQL-order-dependent and therefore non-deterministic across reprices.

---

## 5. Deltas vs the 08:13 brief

- **B1 line cite moved.** Brief cited `AssetContractQueryHelper.cls:47-52` (old inline build). In CURRENT source the collapse is in the new `buildResults` helper at **lines 104-107** (map build) + **109-121** (one-wrapper-per-contract loop). Anyone fixing must target the new method, not line 47.
- **B1 status UNCHANGED by today's rework.** Brief flagged B1 HIGH and OPEN; the 14:00Z edit did NOT close it. The rework's value is +2 `@TestVisible` seams (`collectContractIds`, `buildResults`) that make the fix unit-testable in-memory — but the fix itself was not made. (Companion: handler's `buildContractOverrideMap` is also now `@TestVisible`, edited 16:29Z, same purpose.)
- **Live data delta: none** — the `800WC00000PCpoMYAT` 4-asset shape persists exactly as the brief recorded; override is still VALID (persist 2028-05-15 future).
- **New observation not in brief:** all 4 collapsed assets are the SAME Product2 at TWO price points (6063.75 ×3, 2021.25 ×1), which quantifies the mis-pricing surface and shows the collapse is non-deterministic in *which* asset survives.

---

## 6. Recommended fix (for the rework, NOT applied — read-only)

Re-key per-ACR, not per-Contract. The relationship cardinality is Contract 1→N Asset, so the join row (ACR) is the correct grain. Minimal change inside `buildResults`:
- Iterate the **relationships** (ACRs), look up each ACR's ContractId in a `Map<Id,Contract>` of activated contracts, and emit one `AssetContractData` per ACR (per asset). Replace the `contractToAssetMap` + contract-loop with: build `Map<Id,Contract> activatedById`; `for (acr : relationships) { Contract c = activatedById.get(acr.ContractId); if (c==null) continue; emit wrapper with assetId=acr.AssetId, contractId=c.Id, ... }`.
- This is exactly how `COLAUpliftPrehook` already keys (per-ACR), per the brief — so the prehook path is NOT affected by B1; only the trigger/handler path is. Aligning the helper to per-ACR makes both engines consistent.
- The new `@TestVisible buildResults(relationships, contracts)` seam is the right place to unit-test a 4-ACR/1-contract input asserting 4 wrappers out. Currently it would assert 1 (the bug).

**Open for Marc/German (brief Q7):** is "one active Contract per Asset" a real invariant, or do we re-key per-ACR? Live data (`800WC00000PCpoMYAT`, 1 contract → 4 assets) says the per-Contract assumption is wrong; per-ACR re-key is the fix.

---

## 7. Confidence

- B1 not fixed / keying still per-ContractId: **HIGH** (direct quote of current source + byte-identical live-org body diff).
- Multi-asset live shape persists: **HIGH** (3 live SOQL queries this session).
- COLA_Source mislabeling as downstream effect: **MEDIUM** (collapse → missing override is HIGH/proven; the exact `COLA_Source__c='CMDT Lookup'` string stamping was carried from brief, not re-traced line-by-line in this stream).
- Dollar magnitude per asset: **MEDIUM** (Prices confirmed live; the CMDT comparison rate for `5250 Integrator`'s solution category was not re-queried in this stream).
