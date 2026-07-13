# Wave 1 — dead-code cleanup, verified delete-sets (read-only re-proof 2026-07-06)

All deletions are the team's action (Setup → Apex Classes). Proof method: org-wide MetadataComponentDependency
(Dependency API) + repo grep + wiring check. Gate after each retirement: reprice the 11 stable anchors → `diff.py` 0-delta.

| Item | Dependency-API verdict | Safe to delete? | Delete-set |
|---|---|---|---|
| **PartnerPricingPrehook** (V1) | only its own test | ✅ yes | `PartnerPricingPrehook` + `PartnerPricingPrehookTest` |
| **SourceListPricePrehook** | ZERO dependents | ✅ yes | `SourceListPricePrehook` + `SourceListPricePrehookTest` |
| **SourceListPriceResolver** | only its own test | ✅ yes | `SourceListPriceResolver` + `SourceListPriceResolverTest` |
| **RenewalMaintenanceFlip** | own test **+ Flow `Fortra_Create_Renewal_Quote` v7 (OBSOLETE)** | ⚠️ **blocked** | runtime-dead (active flow = v8, no ref), but the obsolete v7 reference **blocks class deletion** — delete/prune obsolete flow v7 first, or leave the class in place |
| **scratch_v210.xml** | n/a (repo file) | ✅ done | quarantined → `Data/pricing-refactor-scratch/quarantine/` |

## Notes / plan corrections
- **RenewalMaintenanceFlip corrects plan DC-5 / INV-10** ("zero references"): the active renewal flow dropped it in v8,
  but the obsolete v7 still references it (repo flow copy was stale, hid this). It is *runtime-dead* but not *freely deletable*.
  Lowest-value item — recommend leaving it until the obsolete flow versions are pruned in a separate housekeeping pass.
- SourceListPrice* are self-documented disabled no-ops (bodies return "disabled"); live path = `Stamp_Source_List_Price` flow.
- These cleanups are **hygiene, not necessary** — they change no runtime behavior. Priority remains DEF-1 (S5).
