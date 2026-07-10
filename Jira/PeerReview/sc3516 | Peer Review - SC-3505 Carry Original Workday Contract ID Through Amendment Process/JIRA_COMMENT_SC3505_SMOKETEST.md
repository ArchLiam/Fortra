# Jira comment — SC-3505 / FORTRA-CONTRACT-014 smoke test results

---

🧪 **SMOKE TEST — `Fortra_OrderItem_Stamp_Asset_Workday_ID` (FortraUAT)**

The flow had **never executed** before this (no Flow Test, no Apex test, and the source field is empty on all 230,360 order lines). I ran a manual smoke test by injecting sample values into `OrderItem.Workday_Contract_Line_Reference_ID__c`, then **reverted all test data** — org is back to 0/0 populated.

**Result: ✅ happy path works · ❌ multi-asset lines are stamped incorrectly.**

---

### ✅ Test 1 — single-asset line → PASS
| Step | Result |
|---|---|
| Set `SMOKE-WD-CLR-001` on OrderItem `802WC00000PxBQrYAN` (Order 00095709, **Activated**) | write succeeded |
| Flow fired synchronously, resolved the asset via the lineage | ✅ Asset `02iWC000008m0KUYAY` = `SMOKE-WD-CLR-001` |

The core mechanism works, resolves the correct asset, and the field **is writable even on Activated orders** (so activation locks won't block the eventual MuleSoft upsert).

### ❌ Test 2 — order line that produced TWO assets → FAIL
OrderItem `802WC00000POYdFYAX` generated **two** Assets (both `Generate`). After setting the source value:

| Asset | Outcome |
|---|---|
| `02iWC000008Yw1rYAC` | ✅ stamped |
| `02iWC000008Z7V5YAK` | ❌ **left blank** |

**The flow stamped only ONE of the two assets** and silently missed the other.

---

### 📋 Acceptance Criteria verification
| AC | Criterion | Status |
|---|---|---|
| 1 | Flow exists / Active, OrderItem `RecordAfterSave` Create+Update, requires-record-changed | ✅ Met |
| 2 | Entry condition = `Workday_Contract_Line_Reference_ID__c` IS NOT null | ✅ Met |
| 3 | On populate, resolves the Asset via lineage and stamps the same value | ✅ Met (Test 1) |
| 4 | Stamped asset is the one that order product produced — **no cross-line bleed** | ❌ **Not met** (Test 2: 1 of 2 assets stamped) |
| 5 | Write is once-per-populate (not on unrelated saves) | ✅ Met (by config: requires-changed + IS-NOT-null entry) |
| 6 | Legacy / no-source lines unaffected; flow does not fire | ✅ Met (0 of 230,360 populated) |
| 7 | Asset field is Text(255), correct label, **present in source control** | ⚠️ Partial — Text(255) + label ✅, **not in source control** ❌ |
| 8 | Source empty on all lines → 0 Asset stamps to date | ✅ Met (0 before; restored to 0 after) |

**6 of 8 fully met.** The documented flow behaves as specified for the common single-asset case. **AC #4 is not met** (multi-asset lines — see Test 2), and **AC #7 is partial** (field attributes correct, but the field is not tracked in source control; since we don't use shared source control, that clause should be dropped from the AC).

---

### 🎯 Root cause
The lineage lookup `Get_Asset_Action_Source` takes the **first** `AssetActionSource` (`getFirstRecordOnly=true`) with **no `ORDER BY` and no `AssetAction.Type` filter**. So when one order line maps to multiple asset actions, it resolves exactly one — arbitrarily — and stamps only that asset.

- This **breaks AC #4** ("the exact Asset that order product created — no cross-line bleed").
- Risk population: **~5,846 OrderItems** already have >1 `AssetActionSource`; `AssetAction.Type` in the org includes `Generate`, `Change`, and `Cancel`. The lookup can also pick a `Change`/`Cancel` action's asset instead of the `Generate` one.
- **Amendments / renewals / cancels are exactly what accrue multiple asset actions**, so this goes live the moment the Workday/MuleSoft feed populates the source field.

### 🔧 Recommended fix
1. Add `AssetAction.Type = 'Generate'` to the `Get_Asset_Action_Source` / `Get_Asset_Action` filter.
2. Add a deterministic `ORDER BY` (e.g. `CreatedDate DESC`) — the sibling Apex (`PopulateAssetLegacyFieldsAction`, `BackfillAssetHardwareBatch`) already does both.
3. Handle **1 line → N assets**: iterate all matching assets, not first-only.
4. Re-run this smoke test on a multi-asset line to confirm all produced assets receive the reference.

**Cleanup confirmed:** OrderItems `802WC00000PxBQrYAN` / `802WC00000POYdFYAX` and Assets `02iWC000008m0KUYAY` / `02iWC000008Yw1rYAC` all reverted to blank. No residual test data.
