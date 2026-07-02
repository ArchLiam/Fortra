# SC-3411 — Jira comment draft (tag @Joe Romo and @Wren in Jira)

> Markdown auto-formats on paste in Jira Cloud. For a colored callout, type `/panel` on the title line.

---

@Joe Romo @Wren

## ✅ SC-3411 — RESOLVED (UAT) · Order **00095503 is Activated**

---

### 🔎 Root cause
- The order's **subscription line was missing its term `End Date` / `Term Count`** → Revenue Cloud blocks activation until those are set.
- The **"Update Status"** button hid the real reason behind a generic *"unhandled fault."*

### 🛠️ What we fixed
| # | Fix | Effect |
|---|---|---|
| 1 | "Update Status" flow | now shows the **real** error, not "unhandled fault" |
| 2 | OrderItem "Set Dates" flow | termed lines **auto-fill** End Date / Term Count (self-heal) |

💲 **Bonus:** the reprice also corrected the price → **$94,256 → $77,336** (a discount that hadn't applied).

### ▶️ Going forward
- Stuck termed order? → **Reprice All → Activate**
- ~11 older test lines self-heal on next save (ping me to bulk-backfill)

### 👀 Watching
- **Workday sync** — any hiccup there is a separate, already-known item (not this fix)

🔒 **Scope:** UAT only · prod rollout next

---
*Fixes: `Fortra_Order_Submission_Check` V14 (P0) + `Fortra_OrderItem_Set_Dates` V6 (P1), FortraUAT 2026-06-15. Full RCA in README.*
