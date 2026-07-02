{panel:title=✅ FIXED & DEPLOYED TO UAT — READY FOR TESTING|borderStyle=solid|borderColor=#36B37E|titleBGColor=#E3FCEF|bgColor=#FFFFFF}
*Create & Select* now works on accounts of any size. Verified live on the reporter's 236-Hardware account. All acceptance criteria met. {{HardwareGroupController}} coverage *56.8% → 84.4%* (production-promotable).
{panel}

----

h2. 🔍 Root cause

When you clicked *Create & Select*, the Hardware record _was_ created — but the screen then re-located it by re-scanning the account's hardware list, which was *capped at 200 rows*. On accounts with *more than 200 Hardware records*, the new record fell outside that window, so:

* ❌ it never appeared in the list
* ❌ *Create Group* stayed greyed out
* ⚠️ a "success" toast fired anyway → *the failure looked like a success*

The reporter's account (_Fortra, LLC - Test_) has *236 Hardware records*, so it failed every time.

----

h2. 🛠️ What was fixed

|| # || Change || Effect ||
| 1 | New {{getHardwareById}} — fetch the new record *directly by Id* (no list re-scan) | Works regardless of record count or sort order |
| 2 | Success toast is now *gated* | Honest result: clear warning + form stays open if it can't select — *no more silent failure* |
| 3 | Existing-hardware lists no longer truncate large accounts | Hardware beyond row 200 is now selectable too |

----

h2. ✔️ Acceptance criteria — *all met*

|| Criterion || Status ||
| Create a new Hardware record from the flow | ✅ |
| New Hardware available after *Create & Select* | ✅ |
| *Create Group* enables once info is provided | ✅ |
| Create a Hardware Group using the new Hardware | ✅ |
| Clear, actionable message if it can't be selected | ✅ |

----

h2. 🧪 For QA — sample records (FortraUAT)

|| Scenario || Quote || Account (Hardware count) ||
| *Was broken* (>200) | *00781181* | _Fortra, LLC - Test_ (236) |
| Regression (<200) | *00781115* | _AB Test Account_ (8) |

*Steps:* Hardware Groups → *Create New Hardware Group* → tick _"Assign or change hardware"_ → *Create New Hardware* → fill fields → *Create & Select* → *Create Group*.
{tip}Use the *"Create New Hardware Group"* option — not _"Assign Hardware to Group"_ (that one attaches to an *existing* group).{tip}

----

h2. 📋 Notes

* *Scope:* deployed to *FortraUAT only*. 29/29 Apex tests pass.
* *Follow-up (separate):* "Assign Hardware to Group" dead-ends when a quote has no existing groups — minor UX improvement, can be its own ticket.
* *Data:* ~20 historical records left in "Quoting" status from earlier failed attempts; cleanup intentionally deferred.
