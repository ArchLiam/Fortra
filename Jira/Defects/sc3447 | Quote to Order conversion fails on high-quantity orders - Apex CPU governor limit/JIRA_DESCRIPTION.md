Paste into the Jira description editor in "Wiki / Text" mode.

----

{panel:title=⚠️ TL;DR|borderColor=#FF5630|titleBGColor=#FFEBE6}
Converting a quote with a high-quantity *Power* Solution-Group line fails with a CPU governor limit. The conversion clones the line into one OrderItem per unit (+ Hardware + Partition each), then runs 3 flows on every clone, blowing the 10-second Apex limit → order rolls back. *Not* an org/license cap; *not* the earlier convert defect. Trigger is high qty on a *Power*-group product specifically — Joe's Endpoint DLP @ 750k is *Defensive Security*, so it does **not** split and would convert fine.
{panel}

h2. 🔴 Symptom
Convert Quote to Order fails with *"Limit Exceeded — exceeded the maximum limit for this feature"* (or *"An unhandled fault has occurred in this flow"*). **Order is never created — full rollback.**

h2. 🧪 Repro
* Quote {{0Q0WC000003AuQb0AK}} (Q-00781200, FortraUAT)
* Line *Abstract* — Solution Group *Power*, qty *456* → splits into 455 clones
* Convert Quote to Order → fails every time

h2. 🔍 Root Cause
Confirmed from FINEST log {{07LWC00000PCXmd2AH}} (19.5 MB). Real exception:
{code}System.LimitException: Apex CPU time limit exceeded
error.cause = FLOW_INTERVIEW_LIMIT_EXCEEDED{code}
Governor limit, *not* a license/entitlement cap (all 72 org limits healthy). Chain:
# Convert runs *"Fortra Quote to Order Conversion"* flow *synchronously* (10,000 ms CPU ceiling)
# Calls {{PowerOrderSplittingService.splitPowerOrderLines}} → for {{Solution_Group='Power' AND Quantity>1}}, clones the line into *(qty − 1)* qty=1 OrderItems (+ Hardware + Partition each)
# Each clone re-runs 3 autolaunched flows → CPU exhausted at ~400 clones

h2. 📊 Evidence (one sync transaction, ~400 clones in)
|| Flow firing per clone || Interviews || Note ||
| Fortra \| OrderItem \| Set Dates | 409 | active |
| *(Deprecated)* Autolaunched \| Set Workday Contract Line Type | 408 | ❌ redundant duplicate (also flagged in SC-3366) |
| Fortra \| OrderItem \| Set Workday Contract Line Type (V11) | 209 | active |
| *TOTAL flow interviews* | *~1,293* | + 480 DML rows / ~401 clones |
Last checkpoint {{Maximum CPU time: 8277 / 10000 *** CLOSE TO LIMIT}} → then breaches 10,000 ms.

h2. 🎯 Scope / blast radius
Split is hardcoded-gated to {{Solution_Group__c = 'Power' AND Quantity > 1}}. High quantity *alone* is safe:
|| Line || Solution Group || Qty || Splits? ||
| Abstract | *Power* | 456 | ✅ blows CPU |
| Accelerated | Managed File Transfer | 3,425 | ❌ |
| Endpoint DLP (Joe's example) | Defensive Security | 750,000 | ❌ converts fine |

h2. ✅ Roadmap
* *P1 (biggest win):* remove deprecated Autolaunched Workday line-type subflow; stamp derived fields on clones in Apex + guard per-record flows to skip {{Is_Split_Line__c=true}} → removes ~1,000+ interviews from sync path
* *P2:* move splitting to async (Queueable/Batch, chunked DML) + hard cap with a catchable message instead of a raw governor fault
* *P3 (business decision):* confirm realistic max qty for Power lines; re-tag/validate or re-represent — persisting 100k+ OrderItems is infeasible regardless (10,000 DML-row hard ceiling)
* *P4:* Apex tests at qty boundaries + async; E2E matrix incl. negative test (Endpoint DLP @ 750k must pass without splitting)

h2. 🔗 Related
* SC-3366 — order-completion SOQL governor blowout (same family, same deprecated subflow)
* Evidence: {{Data/sc3447/convert_logs/MAIN_07LWC00000PCXmd2AH.log}}, {{PowerOrderSplittingService.cls}}
