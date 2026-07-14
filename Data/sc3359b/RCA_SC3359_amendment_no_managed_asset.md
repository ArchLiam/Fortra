# RCA — "Amendment Order does not create Managed Asset for newly added subscription product"

**Ticket label given:** SC-3359 (⚠️ number conflicts with the known partner-pricing SC-3359; see note).
**Org:** FortraUAT (`00DWC000006eUFF2A2`). **Investigated:** 2026-07-14. **Method:** read-only live-data forensics + repo/SDD.

## Example records
- Order **00095740** = `801WC00000mr9CvYAI` (the amendment). Status **Order Complete**, ActivatedDate 2026-07-12T13:56:26, `Order_Integration_Error_Messages__c = null`.
- Contract **00069476** = `800WC00000TYZVhYAP` (Activated, 2026-07-12 → 2027-07-11).
- Account `001WC00000WiR9YYAV`.
- Missing product: **ARC for On Prem DLP** (`DP-DLP-RSL-ARCO`), Subscription / Term-Based Annual, amendment line 0000568227, Qty 10.

---

## ROOT CAUSE (confirmed)

The amendment order **never transitioned to `Order.Status = "Activated"`.** Its status path was
`Draft → Provisioned → Order Complete` (13:56:26 → 13:56:35), **skipping "Activated" entirely.**

Every downstream fulfillment automation in this org is a record-triggered flow whose **entry criteria = `Status EqualTo "Activated"`**:
- `Fortra_Assetize_Order` (creates Assets — the Managed Assets)
- `Fortra_Order_to_Billing_Schedule` (creates Billing Schedules)
- `Order_Submission_to_Revenue_Orchestrator` (submits to the RLM orchestrator)

Because "Activated" was skipped, **none of these fired.** The amendment produced **0 Assets** and **0 Billing Schedules** for **all 8 lines** (6 Amend + 2 Add), not just ARC. No error was stamped because the flows never executed — there was nothing to fault. AUA (`AppUsageAssignment`) is present, so this is **not** the AUA silent-exit gate.

### The ticket's framing is a perceptual artifact
"CCM (existing SKU) succeeded, ARC (new SKU) failed" is how it *looks* in the contract's managed-asset grid, but the data shows **neither** succeeded from the amendment:
- CCM (`FIM-FIM-RSS-CCMMSF`) already existed as a Managed Asset from the **original** order 00095739 → it *appears* present.
- ARC had never been on this contract → it's the only genuinely-new SKU, so it's the only visibly-absent one.
- The amendment's CCM-add (line 224, +5) created **no** additional CCM asset either — only one CCM asset exists (Qty 10, from the original order).

---

## Evidence

### Two orders on the contract
| Order | Role | Status path | Assets | Billing Schedules |
|---|---|---|---|---|
| 00095739 `801WC00000mrKRaYAM` | original (net-new, 8 Add lines) | Draft → **Activated** → Provisioned → Order Complete | **8** (Initial Sale/Generate @13:36:03) | **8** |
| 00095740 `801WC00000mr9CvYAI` | amendment (6 Amend + 2 Add) | Draft → Provisioned → Order Complete (**no Activated**) | **0** | **0** |

### Amendment line → OrderAction map
| Line | Product | Qty | OrderAction | Type |
|---|---|---|---|---|
| 220 | GS-GSE-NRPS-E8EP | 1 | ...cg0J | Amend (src 02i…oE) |
| 221 | GS-GSE-NRPS-E8EP | 2 | ...cg0I | Amend (src 02i…oF) |
| 222 | FIM-FIM-RSS-CCMMSF | 2 | ...cg0H | Amend (src 02i…oJ) |
| 223 | PIA-PIA-RSS-PIAS | 2 | ...cg0L | Amend (src 02i…oI) |
| 224 | FIM-FIM-RSS-CCMMSF | 5 | ...cg0K | **Add** (shared) |
| 225 | VM-VLM-RSL-FVSS | 2 | ...cg0N | Amend (src 02i…oK) |
| 226 | GS-GSE-NRPS-E8EP | 2 | ...cg0M | Amend (src 02i…oD) |
| 227 | **ARC (DP-DLP-RSL-ARCO)** | 10 | ...cg0K | **Add** (shared) |

- The single Add OrderAction shared by CCM-add + ARC-add is **normal**: the original order had all 8 lines under one Add OrderAction and assetized perfectly. Shared OrderAction is **not** the defect.
- The 6 Amend source-assets are **untouched** (all still LastModified 13:36:06 — the original activation), confirming no amend processed.

### Ruled out
- **AUA gate** — both orders have an `AppUsageAssignment` (`RevenueLifecycleManagement`). Not the cause.
- **Shared/malformed OrderAction** — proven normal by the original order.
- **Systemic to amendments** — a healthy amendment (`801WC00000mksBUYAY`, has an Amend action) went Draft→**Activated**→Provisioned→Order Complete and assetized. Amendments are not inherently broken. Of 70 recent orders, only **2** skipped Activated.

### Independent corroboration (billing pipeline)
Billing is a **separate** Activated-gated flow. Prediction: amendment should also have 0 billing schedules. **Confirmed: amendment 0 BS, original 8 BS.** This proves the miss is the shared upstream status gate, not assetization logic.

---

## WHY did it skip "Activated"?
- Q2O (`Fortra_Quote_to_Order_Conversion`) sets Status only to **Draft** or **Activated** (never Provisioned); it has amendment handling ("Amend" ×20, "Convert" ×25).
- **No repo flow or Apex sets "Provisioned"** — it is set by the native RLM fulfillment orchestration (post-Activated) or a manual/scripted status update.
- Therefore 00095740 was moved to "Provisioned" via a path that **bypassed the standard "Activated" activation** that Q2O/orchestrator submission would have produced. This is the upstream item to close (a specific amendment-activation path or a test-harness/direct status set). Driven by user "Joe Romo"; order created 13:55:21, jumped Draft→Provisioned 65s later.

---

## SDD alignment
`docs/RCA Solution Guide/kb/Revenue_Cloud_Order_to_Asset_Lifecycle.md`:
- Phase 2 assetization = "Record-Triggered, async on `Order.Status = "Activated"`" — matches.
- Phase 1 step 7: "Automatic → `Order.Status = Activated` → triggers Phase 2 + 3." Design intends activation to set **Activated**.
- Rule 12: amendments go through the same Q2O/Assetization/Billing pipeline; `createOrUpdateAssetFromOrder` **updates existing** assets on amend.
- Design already flags "silent-failure by design … requires external monitoring to catch missed Assets/Billing Schedules" — this incident is exactly that failure mode, one level up (the status gate itself).

---

## Recommended solution (best practice)

**1. Root fix — guarantee amendment activation sets `Status="Activated"`.**
Repair whatever moved 00095740 directly to "Provisioned". Amendments must pass through "Activated" (a committed, distinct state) so the existing assetize/billing/submission triggers fire. If an amendment-activation branch or integration sets "Provisioned" directly, correct it to set "Activated" first and let the orchestrator progress it.

**2. Defense-in-depth — stop a single transient status silently dropping fulfillment.**
Three critical, silently-failing pipelines keyed on one transient value is fragile. Best practice:
- Add an **idempotent reconciliation** (scheduled flow/Apex) that flags any Order in a terminal state (`Order Complete`/`Provisioned`) with **0 Assets or 0 Billing Schedules**, and re-drives assetization. `createOrUpdateAssetFromOrder` is create-or-**update** (idempotent), so re-running is safe.
- OR broaden the trigger entry criteria to also catch the terminal transition, guarded for idempotency (never double-assetize).

**3. Recover 00095740 (owner-authorized).**
Re-trigger assetization — either set `Status="Activated"` (fires the flow) or invoke `createOrUpdateAssetFromOrder(orderId='801WC00000mr9CvYAI')`. Expect the 6 amend updates + 2 new assets (CCM add + **ARC**).

**Confirmation available (non-committing):** savepoint-rollback re-invocation of `createOrUpdateAssetFromOrder` against 00095740 — proves the missing assets (incl. ARC) would be created and rules out any secondary structural defect. Held pending authorization per the UAT-DML guardrail.

---

## ⚠️ Ticket-number note
Local memory records **SC-3359** as a *partner-pricing net* defect (German Wren, 2026-06-07, procedure V9/V10). This ticket describes *amendment assetization*. Either the number was reused or is mistyped. This RCA is filed under `Data/sc3359b/` to avoid clobbering the partner-pricing artifacts under `Data/sc3359/`. Confirm the correct Jira key before commenting.
