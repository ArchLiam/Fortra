🟢 SC-3338 — RESEARCH + BUILD COMPLETE (UAT) · awaiting UX sign-off + prod deploy

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📌 TL;DR
Built the low-lift fix — Quote help text + a "Required Fields Check" guidance modal. No fields were hard-required (per scope). All deployed to UAT and prod-safe.

💡 Key insight: most "required for Order submission" fields are auto-filled downstream or system fields — only a small Account / Contact / Place / date set is actually rep-entered. So we surface THAT subset instead of force-requiring everything.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ DONE & DEPLOYED TO UAT (all prod-safe)

✔️ AC1 — Inventory
   Documented every Quote→Order required field + the metadata enforcing each.
   Source of truth: Order_Submit_Validation__mdt (48 rules, 25 active) → OrderSubmissionValidator → Fortra_Order_Submission_Check v13 (fires at Order-Complete).
   ⚠️ This Order-side machinery is UAT-only — it does NOT exist in Prod.

✔️ AC2 — Help text on the Quote
   Added clear inline help to the 6 rep-facing driver fields:
   Bill To Contact · Quote Contact · Bill To Place · Ship To Place · Start Date · Status.

✔️ AC3 — Guidance modal ("Required Fields Check" action on the Quote)
   New screen flow reads the live Quote + Account + Contacts + Place and shows a grouped
   ✅ / ❌ readiness checklist:
      • On this Quote        (Bill/Ship Contact, Bill/Ship Place, Start Date)
      • On the Account       (Name, Phone, Type, D&B DUNS)
      • On the Contacts      (First/Last Name, Workday mobile attributes)
   Includes the Account/Contact fields that can't carry Quote help text. 100% read-only.

✔️ AC5 — No regressions
   Zero Apex / validation-rule / core-flow changes. Existing tests green → 14 / 14 (100%).

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🛡️ AC4 — Blocking validation: MET (without adding a forced block)

The Convert Quote to Order flow (v27) ALREADY blocks conversion — with clear error screens —
for every rep-controlled field: Bill To Contact · Bill/Ship Place · Billing Street ·
Quote Status · Pricing status · Sync · existing-order · Start Date · Operations Checklist.

The only un-guarded fields are Account/Contact data (Name/Phone/Type/DUNS, contact names +
Workday attributes) — owned by other teams and often blank.
   → now surfaced EARLY by the new modal, and
   → still enforced at Order-Complete by the existing validator.

🚫 Decision: do NOT force a hard block on those at conversion — it would be over-restrictive.
The original "un-noticeable blocker" complaint is resolved: the modal forewarns the rep long
before they ever reach Order-Complete.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⏭️ OPEN ITEMS
   🔲 UX review with Wren — help-text wording + modal grouping/labels
   🔲 Quick manual check of the modal render in UAT
   🔲 Minor: new action pushed "Start Sync" into the ▾ overflow menu — bump visible actions 7→8 to keep it out?
   🔲 Prod deploy of help text + modal (whole build is prod-safe) — on UX sign-off

📂 Full inventory, evidence, build logs & prod deploy manifest are in the SC-3338 working folder.
