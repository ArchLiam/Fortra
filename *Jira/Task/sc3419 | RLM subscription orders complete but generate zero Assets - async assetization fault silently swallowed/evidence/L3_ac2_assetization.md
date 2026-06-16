# SC-3419 — L3 evidence: AC2 (normally-built orders assetize 1:1, incl. future-dated)

**Org:** FortraUAT | **Date:** 2026-06-16 | **Mode:** read-only (`sf data query` / describe only)

**AC2 (target):** On a normally-built order (Quantity, not duplicate lines), activation generates
Assets for EVERY subscription line, INCLUDING future-dated lines.

**Verdict: AC2 is currently MET.** Pipeline is alive; 8 normally-built activated orders (1–18 lines)
each show exact 1:1 OrderItem→AssetActionSource coverage, including a future-dated subscription line
that assetized (AssetAction Type=Change).

---

## Measurement method (and the caveat that the prompt flagged is now resolved)

The prompt noted subscription Assets link to the account (AccountId+Product2Id), not directly to the
OrderItem, so account-level Asset counts only approximate coverage. That caveat is **avoided here**:
`AssetActionSource.ReferenceEntityItemId` is a direct reference to **OrderItem** (polymorphic over
OrderItem / OrderItemDetail / WorkOrderLineItem). So one AssetActionSource row per assetized
OrderItem = an exact, line-level 1:1 measure of assetization. We join through
`AssetAction` (`AssetActionId`) to get the resulting `AssetId` and the action `Type`.

This is the platform-canonical "did this line produce an asset transaction" signal — strictly better
than account-level Asset counts.

---

## 1. Org-wide pipeline health (last 7 days)

| Metric | Count |
|---|---|
| Assets created (`Asset`, LAST_N_DAYS:7) | **110** |
| AssetActionSource created (LAST_N_DAYS:7) | **127** |

Pipeline is actively producing assets and asset-action sources → assetization is alive org-wide.

---

## 2. Normally-built activated orders — 1:1 line→asset coverage

Sampled recently-activated orders (ActivatedDate ≥ 2026-06-09) plus the SC-3415 known-good contrasts
(all still present). Coverage measured by `AssetActionSource.ReferenceEntityItemId` = the order's
`OrderItem` Ids.

| Order | Lines | AAS rows | Generate | Change | Future-dated lines | 1:1? |
|---|---|---|---|---|---|---|
| 00095325 | 18 | 18 | 18 | 0 | 0 | YES |
| 00095377 | 14 | 14 | 14 | 0 | 0 | YES |
| 00095468 | 3 | 3 | 3 | 0 | 0 | YES |
| 00095471 | 2 | 2 | 2 | 0 | 0 | YES |
| 00095472 | 3 | 3 | 3 | 0 | 0 | YES |
| 00095475 | 3 | 3 | 2 | 1 | 1 | YES |
| 00095489 | 1 | 1 | 1 | 0 | 0 | YES |
| 00095530 | 4 | 4 | 4 | 0 | 0 | YES |

**Totals: 48 OrderItems → 48 AssetActionSource rows = exact 1:1.** The SC-3415 known-good contrasts
re-confirm: 00095325 (18→18), 00095377 (14→14), 00095471 (2→2), 00095475 (3→3). 00095472/00095468/
00095489/00095530 are additional fresh activations spanning 1–4 lines.

(Note: 00095325 and 00095471 are in `Order Complete` status, 00095377/00095475/etc. in `Activated`;
both states show full asset coverage — assetization is independent of which downstream status label
the order lands on.)

Order Ids for reference:
- 00095325 = 801WC00000k2pjwYAA (acct 001WC00000WiR9YYAV)
- 00095377 = 801WC00000kM73cYAC (acct 001WC00000gVLfxYAG)
- 00095468 = 801WC00000kXyMIYA0
- 00095471 = 801WC00000kYphnYAC
- 00095472 = 801WC00000kZELqYAO
- 00095475 = 801WC00000kaGBpYAM (acct 001WC00000kZKNxYAO)
- 00095489 = 801WC00000ke1J7YAI
- 00095530 = 801WC00000ksZvxYAE

---

## 3. CRITICAL for AC2 — future-dated subscription line DID assetize (concrete proof)

Order **00095475** (801WC00000kaGBpYAM), line `VM-BSL-RSL-BESECB` "beSECURE - Cloud-Based":

| Field | Value |
|---|---|
| OrderItem Id | **802WC00000OgsuFYAR** |
| ServiceDate | **2027-06-11** (≈1 year in the future) |
| → AssetActionSource StartDate / EndDate | **2027-06-11 → 2028-06-10** (future term window) |
| → AssetAction.Type / Subtype | **Change** / (none) |
| → AssetAction.ActionDate | 2026-06-11T18:40:34Z (action booked at activation) |
| → Resulting Asset Id | **02iWC000008FcLaYAK** |
| → Asset.Name / Status / ProductCode | beSECURE - Cloud-Based / **Installed** / VM-BSL-RSL-BESECB |
| Asset CreatedDate | 2026-06-11T15:47:35Z |

The future-dated line produced an Asset and the asset still exists (Status=Installed). The
AssetActionSource carries the **future** term window (2027→2028), and the AssetAction is booked as
**Change** rather than Generate — exactly the SC-3415 observation, re-verified today.

The other two lines on 00095475 (PIA-PIA-RRM-PIAM RenewalMaintenance, ServiceDate null; and
HRM-HRM-RSL-10L50CS, ServiceDate 2026-06-11 present-dated) both assetized as `Generate` → 3/3 lines
covered.

---

## 4. AssetAction Type pattern (present-dated vs future/renewal)

Across the 48 assetized lines:

| Type | Subtype | Count |
|---|---|---|
| Generate | (none) | 47 |
| Change | (none) | 1 |

Pattern holds: **present-dated / new-sale lines → AssetAction Type = `Generate`**; the single
**future-dated line (beSECURE, svc 2027-06-11) → Type = `Change`** (the renewals/future-term branch).
This matches the SC-3415 finding and explains why future-dated lines still produce assets but are
booked as Change actions on the asset timeline rather than initial Generate.

---

## Conclusion for AC2

- Pipeline alive: 110 Assets + 127 AssetActionSource in the last 7 days.
- 8 normally-built activated orders (1–18 lines): **exact 1:1** OrderItem→AssetActionSource coverage
  (48/48), measured at the line level via `ReferenceEntityItemId`.
- Future-dated subscription line **provably assetized**: OrderItem 802WC00000OgsuFYAR
  (svc 2027-06-11) → Asset 02iWC000008FcLaYAK (Installed), AssetAction Type=Change, future term
  window 2027→2028.

**AC2 is MET for normally-built orders today.** The SC-3419/SC-3415 defect is specific to the
duplicate-line + maintenance-decomposition collision path (00095470's 32 dup lines colliding on one
AccountId+Product2Id Asset); it does NOT affect normally-built (Quantity-based, non-duplicate) orders,
which assetize 1:1 including future-dated lines.

---

### Raw query artifacts (this folder)
- `orderitems_raw.json` — 48 OrderItems for the 8 sampled orders (Id, OrderId, Product2Id, ServiceDate, Quantity)
- `aas_by_orderitem_raw.json` — 48 AssetActionSource rows keyed by those OrderItem Ids (AssetAction Type/Subtype, AssetId, Asset Name/Status, StartDate/EndDate)
