# SC-3346 RN-PARTNER-DD — Resolution (2026-06-14, FortraUAT)

## Two questions, two answers
RN-PARTNER-DD has a **design question** (what value is correct?) and a **structural question** (why won't it
commit?). The design question is now **definitively resolved**; the structural one is the **SC-3404 cluster**
(already proven not code-fixable on reprice).

## 1. Design question — RESOLVED: the correct net is 67.38; 60.64 is a DOUBLE partner discount
Live canary data (all BoKS Renewal-Maintenance, Base 71, COLA% 7.85, partner model PPM-00000 = NewMaint 12 / RenewMaint 10):

| Quote | NetUnitPrice | UnitPrice | COLACalc | QuoteAction | verdict |
|---|---|---|---|---|---|
| 00781084 | **67.38** | 67.38 | 67.38 | Renew | ✅ correct (priced at birth) |
| 00781109 | **60.64** | 67.38 | 67.38 | null | ❌ = 67.38 × 0.90 |
| 00781068 (Accepted) | **60.64** | 0 | 67.38 | null | ❌ = 67.38 × 0.90 |
| 00781053 | **54.58** | 0 | 60.64 | null | ❌ = 60.64 × 0.90 |
| 00781043 | **0** | 0 | 67.38 | null | ❌ MissingContributor ($0) |

**The double-count, proven by arithmetic + config:**
- COLA net `67.38 = (71 − 8.52) × 1.0785`. The **8.52 = 12% prior partner discount** (12% × 71) — i.e. the partner
  relationship is **already embedded** in the COLA net.
- The wrong lines commit `COLA-net × 0.90` (exact 0.9000 ratio). The 0.90 = the partner model's
  **`Renewal_Maintenance_Percent__c` = 10%** (PPM-00000) re-applied to the already-net price.
- So 60.64 = (base − 12% partner) × COLA × (1 − 10% partner) = **the partner relationship discounted TWICE**.

**Answer: 67.38 is correct.** The COLA net IS the final renewal-maintenance net; the RenewMaint margin must NOT
re-apply. Confirmed three ways: (a) the spec formula (RN-COLA-MATH passes) = 67.38; (b) the only line priced at
birth via the Renew path (00781084) = 67.38 with no second factor; (c) the math shows 60.64 double-applies the
partner factor. **⚠️ `00781068` was ACCEPTED at the wrong 60.64** — a double-counted price slipped through; it
needs a business note, but it does not make 60.64 correct.

## 2. Structural question — SC-3404 cluster (NOT a reprice-layer code fix)
The wrong values are **frozen fossils**: `NetUnitPrice` is set when the line is **born** and is immutable by every
reprice layer (5 routes proven dead: prehook InputUnitPrice/ListPrice seed, prehook UnitPrice seed, posthook
net-write, in-proc formula resultIncluded=true, native-config rewrite — see `01_MULTI_ASSET_RESOLUTION.md` +
memory). The derived RM line (`ItemIsDerived__std=true`, `DerivedPricingAttribute=true`, `ListPrice=0`) is not a
priced node, so the engine never recomputes it and the posthook's correct 67.38 write is a silent no-op.

**Where the ×0.90 is actually applied:** at the **creation / default-pricing path** for lines that lack a
`Renew` QuoteAction (auto-added by the Year-2 Maintenance config rule). The `Renew`-QuoteAction path prices the
line at birth via `COLAUpliftHandler` → born Net = 67.38 (no second margin). The non-Renew path applies the
RenewMaint margin to the COLA net → born Net = 60.64, which then freezes.

## Fix path (owner-gated; same as the SC-3404 cluster — the other chat is investigating the creation mechanism)
- **Creation-path:** make auto-added / non-Renew RM lines born with the COLA net (67.38) and **no** RenewMaint
  margin re-applied — i.e. replicate `COLAUpliftHandler`'s born-net behavior for the auto-add path. Existing wrong
  lines (incl. Accepted 00781068) need re-creation / a data correction since `NetUnitPrice` is engine-owned.
- **OR de-derive** the renewal-maintenance product so the line is a writable priced node (catalog/PBE/PSM).
- Both are creation/catalog-level, not a reprice-layer code change. RN-PARTNER-DD shares this fix with
  RN-COLA-COMMIT, MAINT-ONLY, MULTI-ASSET.

## Net: RN-PARTNER-DD resolution
The "partner double-discount" is **real and now exactly characterized** (the 10% RenewMaint margin re-applied on a
COLA net that already embeds the 12% prior partner discount). Correct value = **67.38**. It cannot be fixed at the
reprice layer; the fix is the creation-path (born-net) work in the SC-3404 cluster. No standalone code change lands it.
