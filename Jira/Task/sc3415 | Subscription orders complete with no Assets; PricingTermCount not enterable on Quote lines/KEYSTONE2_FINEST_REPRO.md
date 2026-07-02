# SC-3415 Keystone-2 — FINEST repro runbook (pin the asset-creation collision)

**Goal:** capture the exact asset and operation where `createOrUpdateAssetFromOrder` throws `INVALID_API_INPUT: "the asset was updated by another process"` on **00095470**, so the remediation can be chosen (Fortra-side serialization / data restructure / Salesforce platform case). This is the blocker for **AC3 (collision case)** and **AC4 (recover 00095470)**.

## What we already know (read-only, done)
- The fault is **deterministic** (rollback diagnostic ×3, `1 SOQL / 534ms` — not a governor limit).
- 00095470 has **2 Order Product Detail records** (`OrderItemDetail`) → **maintenance decomposition** is involved (PIA-PIA-RNM-PIAMBK ×10). Same fragile path SC-3411 §4.1 flagged for `OrderRepriceInvocable`.
- **Existing assets** already exist on account `001WC00000XiZP4YAN` for **3 of the 4 products** (PIAMBK, PIAP, CLSAAS) → the action takes the **update-existing-asset** path, where the lock conflict arises.
- Plain duplication does NOT cause it (synthetic OneTime 2-/12-line and subscription 6-line all assetized) — so it is the **decomposed-maintenance + existing-asset** combination, not line count or duplication.

## Repro procedure (owner-authorized — mutates 00095470)

### A. Synchronous capture (preferred first — no flow, full debug log, safe rollback)
Run this anonymous Apex with the org's debug log at **FINEST** (the `sf apex run` log already returns FINEST for the running user). It invokes the exact action, captures the failing asset, and **rolls back**:

```apex
// Snapshot existing assets + versions BEFORE
Map<Id,Asset> before = new Map<Id,Asset>([SELECT Id, Name, Product2.ProductCode, Status, SystemModstamp
  FROM Asset WHERE AccountId='001WC00000XiZP4YAN'
  AND Product2Id IN ('01tWC00000DD1bsYAD','01tWC00000DD1btYAD','01tWC00000DD1fiYAD','01tWC00000DD17PYAT')]);
for (Asset a : before.values()) System.debug('PREASSET '+a.Id+' '+a.Product2.ProductCode+' modstamp='+a.SystemModstamp);

Savepoint sp = Database.setSavepoint();
try {
    Invocable.Action act = Invocable.Action.createStandardAction('createOrUpdateAssetFromOrder');
    act.setInvocationParameter('orderId','801WC00000kYmw8YAC');
    for (Invocable.Action.Result r : act.invoke())
        System.debug('RESULT success='+r.isSuccess()+' errors='+r.getErrors());
} catch (Exception e) {
    System.debug('EX '+e.getTypeName()+': '+e.getMessage());
}
Database.rollback(sp);
```
In the returned FINEST log, look for the **Asset Id** in the error context and the **DML/SOQL on Asset** immediately before the failure — that names the contended asset.

### B. Async capture (the real flow path — confirms it matches A)
1. Create a `TraceFlag` (DebugLevel = FINEST on all categories) for the activating user **and** the Automated Process user, ~30 min window (Tooling API).
2. Re-fire: `Order.Status → 'Activated'` on 00095470 (verified Workday-safe: `Workday_Sync_Status='Pending'`).
3. Wait ~15s for the `AsyncAfterCommit` `Fortra_Assetize_Order` interview; the action faults (now visibly via V14 → `Order_Integration_Error_Messages__c`).
4. Restore `Order.Status → 'Order Complete'`.
5. Pull the `ApexLog` for that async transaction (filter by user + timestamp) and confirm the same contended asset as (A).

## Analysis targets
- **Which Asset Id** raises the optimistic lock, and is it an **existing** asset (update) or a sibling line's freshly-created one?
- **How many operations** touch that asset in one action invocation (the contending "other process")?
- Does the contention map to the **maintenance parent↔decomposed-child** pair (Order Product Detail), i.e. parent + child both writing the same maintenance asset?

## Remediation decision tree (pick after the log)
- **Multiple order lines updating ONE shared asset concurrently** → serialize asset creation (process non-contending batches) **or** consolidate the duplicate same-product maintenance lines (data/process). For real orders, prefer Quantity over duplicate lines.
- **Native platform concurrency bug in `createOrUpdateAssetFromOrder` for decomposed lines** → open a **Salesforce platform case** with the FINEST repro.
- **Fortra maintenance-decomposition writes the asset out-of-band** → fix in the decomposition/asset path (Fortra-owned).
- Then **recover 00095470** (re-fire after the fix → expect 32 assets) or rebuild it correctly.

## Status
Runbook drafted; read-only pre-work done. Execution of (A)/(B) is **owner-authorized** (mutates 00095470 for the async path; the sync path rolls back). Not yet run.
