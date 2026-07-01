# SC-3473 — Diagnostic Reproduction Runbook

**Goal:** capture the native stack frame + null map key (and a Salesforce `referenceId`) for the `Map.get(Object).toString()` NPE, to (a) settle whether it is delete-specific vs every-reprice and (b) strengthen the Salesforce case.

**Staged already (2026-06-28, reversible):** `DebugLevel SC3473_Diag` (`7dlWC0000001zPdYAI`, ApexCode=FINEST) + `TraceFlag` (`7tfWC000000g9YLYAY`) on user `005WC00000MgTN2YAN` (liam.jeong.c@…uat), ~45-min window. Re-create with a fresh window before use (see §Cleanup to remove).

**Constraints:** RLM blocks direct Quote/QLI DML (`project_rlm_quote_dml_lock`) — all mutation must go through the Place/flow pipeline. The live quote `0Q0WC000002U2020AC` is `IsSyncing=true` to **test** opp `006WC00000NMOODYA5` (acct "Fortra, LLC - Test").

---

## Option 1 — Reprice-only on the live (test) quote *(cheapest; answers the gate's #1 question)*
A reprice **never deletes the group**, so it preserves the canonical repro. Expected failure case is a **no-op** (quote already `SaveFailedOrIncomplete`). A success would un-wedge it and may push recomputed pricing to the **test** opp.

```bash
echo '{"inputs":[{"QuoteId":"0Q0WC000002U2020AC"}]}' > /tmp/sc3473_reprice.json
sf api request rest "/services/data/v62.0/actions/custom/flow/Fortra_Quote_Reprice" \
  --method POST --body /tmp/sc3473_reprice.json --target-org FortraUAT
# then pull the FINEST log:
sf data query --use-tooling-api --target-org FortraUAT \
  -q "SELECT Id,Operation,Status,LogLength,StartTime FROM ApexLog WHERE LogUserId='005WC00000MgTN2YAN' ORDER BY StartTime DESC LIMIT 3"
sf apex log get --log-id <Id> --target-org FortraUAT > evidence/reverify/repro/reprice_finest.log
```
- **Same NPE thrown ⇒** every-reprice/data defect; the delete path is incidental (big result; the malformed term line is the operative trigger).
- **Clean ⇒** the delete path is the structural trigger; proceed to Option 2/3.

## Option 2 — Faithful clone + Delete-Group repro *(most complete; higher effort/risk)*
Build a standalone clone via the RLM transaction API (create context → add group → add the 2 lines incl. the malformed Abstract term state), then POST the `DeleteGroup` graph with `pricingPref:Force`, capturing the response body (raw NPE + `referenceId`). Requires careful payload construction and cleanup of created records; do in a sandbox change window.

## Option 3 — Human QLE repro with debug logs *(faithful, lowest-risk; needs a person in the browser)*
1. Setup → Debug Logs → add a TraceFlag (FINEST Apex; FINE Database/System; FINEST pricing where exposed) on the user who will click.
2. Open the Quote Line Editor on `0Q0WC000002U2020AC`; open the **Network** tab (preserve log).
3. Click the **Test HW1** group caret → **Delete Group** once.
4. Capture: the `POST …/sales-transaction/actions/place` **response body** (the `PlaceQuoteErrorResponse` / raw NPE + any `referenceId`), the browser console, and the ApexLog (expect none for the native throw — that absence is itself the H6 datum). Save under `evidence/reverify/repro/`.

---

## Cleanup (remove the staged trace flag)
```bash
sf data delete record --use-tooling-api --target-org FortraUAT --sobject TraceFlag  --record-id 7tfWC000000g9YLYAY
sf data delete record --use-tooling-api --target-org FortraUAT --sobject DebugLevel --record-id 7dlWC0000001zPdYAI
```
