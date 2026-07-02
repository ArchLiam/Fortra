# SC-3338 — Prod vs UAT parity of the Order-submission validation machinery (independent check, 2026-06-12)

Run by main agent (cross-org auth often fails for subagents).

| Artifact | FortraUAT | FortraProd | Method |
|---|---|---|---|
| `Order_Submit_Validation__mdt` (CMDT type) | EXISTS, 48 records | **ABSENT** (not in EntityDefinition; only standard LearningItemSubmission/ApprovalSubmission* exist) | `EntityDefinition WHERE QualifiedApiName='Order_Submit_Validation__mdt'` → empty in prod |
| `Fortra_Order_Submission_Check` flow | v13 Active | **ABSENT** (no Flow rows) | Tooling `SELECT ... FROM Flow WHERE Definition.DeveloperName='Fortra_Order_Submission_Check'` → empty in prod |
| `OrderSubmissionValidator` Apex class | EXISTS | **ABSENT** | Tooling `SELECT Name FROM ApexClass` → empty in prod |
| `FieldPopulatedCheck` Apex class | EXISTS (deprecated) | **ABSENT** | same query → empty in prod |

**Conclusion:** The entire metadata-driven Order-submission validation machinery lives only in UAT. It is NOT in production. Per prior instruction (memory `sc3291_validation_uat_only`, user 2026-06-01), do NOT deploy this machinery to prod.

**Implication for SC-3338:**
- The Quote-side UX deliverables (inline help text + a Flow guidance modal) are **prod-safe** and can ship to both orgs.
- The "blocking validation" acceptance criterion, if it leans on the Order-side `OrderSubmissionValidator`/mdt, is **only enforceable in UAT today**. In prod there is currently NO metadata-driven required-data block on Order submission at all. SC-3338's blocking-validation design must either (a) be scoped UAT-only matching the existing machinery, or (b) be built as a self-contained Quote-side check that is prod-safe. This is a decision point to raise with Wren / the team.
