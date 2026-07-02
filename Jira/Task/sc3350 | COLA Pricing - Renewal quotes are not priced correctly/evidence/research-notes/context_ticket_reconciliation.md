# SC-3350 — Context / Ticket-Number Reconciliation (COLA renewal pricing cluster)

**Stream:** Context/Ticket reconciliation
**Date run:** 2026-06-10 (read-only research)
**Org:** FortraUAT (`00DWC000006eUFF2A2`)
**Grounding brief (treated as possibly stale):** `Data/sc3354/SC-3354_Research_Brief.md` (08:13 UTC)
**Method:** `grep -ri` / `find … -exec grep` across repo root, `Data/`, `Confluence/`, `docs/`, and `*Jira/` (the dir name literally starts with `*`, which breaks shell globs — had to use `find` and quoted paths). No Jira CLI/MCP is available in this environment (`jira`/`acli` not found, no `JIRA_*` env), so the **live Jira thread itself cannot be read** — the Jomil/Leah/Nir comment context is NOT captured in any repo file and is inferred from secondary artifacts only.

---

## 0. TL;DR reconciliation

| Ticket | What it actually is | Evidence strength |
|---|---|---|
| **SC-3350** | **THE canonical defect Task ticket** = "COLA Pricing - Renewal quotes are not priced correctly" (the two stated defects: #1 priced at list, #2 no description). It is ALSO the ticket the manager summary tags "(Peer Review)" / awaiting Nir. So SC-3350 carries **both** the defect AND the peer-review state. | HIGH (dedicated `*Jira/Task/` folder + manager summary) |
| **SC-3354** | **Same work item as SC-3350 — an alias number**, used as the title of the prior research brief and in the COLA memory note's body. No `*Jira` folder, no daily-report status line. Not a distinct ticket. | MEDIUM-HIGH (alias, not a separate folder) |
| **SC-3346** | **A third number the same COLA work was referenced under** — the daily report's "SC-3346 (review)" line, the memory note's description ("per thread"), and (per the task prompt) Jomil's "relevant to SC-3346" comment on the Leah waterfall image. Most likely the **parent Story/Feature or an earlier/originating ID** of the COLA work, not a separate defect. | MEDIUM (3 weak secondary refs; no folder) |
| **SC-3349** | **A SEPARATE, already-closed ticket** = "Line Item Description Issues" (the beSECURE `Devices: 36-65` fix in `QLDescriptionGeneratorPrehook`). Peer-review subtask = **SC-3352** (reviewer Liam). Subject-matter overlaps SC-3350 defect #2 but is a different scope (general SKU description vs. renewal-path description). | HIGH (full README + folder) |
| **SC-3352** | Peer-review **subtask of SC-3349** (NOT of COLA). Assignee Liam, reporter Nir. | HIGH (README §Details) |

**Bottom line on the user's questions:**
- **Defect ticket = SC-3350.**
- **SC-3350 and SC-3354 are the SAME work item** (SC-3354 is a stale/alias number from the brief + memory; SC-3350 is the live one per the Task folder and current board).
- **Peer-review ticket = SC-3350 itself** — the repo provides **no separate peer-review ticket number** for COLA. The only peer-review *subtask number* found anywhere is **SC-3352**, and that belongs to **SC-3349 (descriptions)**, not COLA. If Nir's "Peer Review ticket" is a distinct number, it lives only in Jira and is **not in the repo** → mark UNKNOWN, do not invent one.
- **Waterfall image = SC-3346** (per Jomil's comment, as relayed in the task). The "waterfall" hits inside the brief (lines 75/80) are the *pricing-procedure* waterfall mechanism, NOT the Leah Guenther image — do not conflate.
- **Descriptions ticket = SC-3349** (closed/approved 2026-06-07), distinct from SC-3350 defect #2.

---

## 1. The single strongest fact: the Task folder

```
*Jira/Task/sc3350 | COLA Pricing - Renewal quotes are not priced correctly/
    evidence/              (empty)
```
- This is the **only** `*Jira` folder for the COLA work, and it is filed as a **Task** under the ticket number **SC-3350** with the exact ticket title from the prompt. No `*Jira/.../sc3354` or `.../sc3346` folder exists.
- The folder is **empty** (only an empty `evidence/` dir, created 2026-06-10 11:57) — i.e., this research session is the first to populate SC-3350's workspace; prior COLA artifacts live under `Data/sc3354/`, `Data/cola-renewal-review/`, and now `Data/sc3350/research/`.

This is the tiebreaker: **SC-3350 is the operative ticket number.** SC-3354 was the working alias before the Task was (re)filed/renumbered to SC-3350.

---

## 2. SC-3350 ≡ SC-3354 (same work item) — evidence

- **Memory note** `project_cola_renewal_pricing_review.md`: body opens *"COLA … feature = ticket **SC-3354**"* but the YAML `description` says *"COLA renewal pricing ticket (**SC-3346** per thread)…"*. The single note thus uses **two different numbers** for one feature — the literal source of the user's confusion.
- **Prior brief** is titled `SC-3354_Research_Brief.md` and lives in `Data/sc3354/`, yet every downstream research file in `Data/sc3350/research/` (written today) cites that same brief as its grounding for **SC-3350**. The two numbers point at one body of work, one set of classes (`COLAUpliftHandler/Prehook/Test`, `AssetContractQueryHelper`, `QLDescriptionGeneratorPrehook`), one set of repro records.
- **No status divergence:** there is no daily-report or board line where SC-3350 and SC-3354 are tracked as two separate items. SC-3354 never appears in any status table; SC-3350 does (manager summary). They are not parallel tickets.
- **Confidence:** MEDIUM-HIGH that they are the same item. The residual uncertainty: I cannot rule out that SC-3354 is a *sibling subtask* (e.g., a peer-review or rework subtask) under the same epic, because I can't read Jira. But nothing in the repo treats them as distinct, and the Task folder only exists for SC-3350.

---

## 3. SC-3346 — the "third number" / likely parent or origin

Three independent secondary references, all to the **same COLA work**, all under **SC-3346**:
1. **Daily report 2026-06-09** line 48: *"21:04 | **SC-3346 (review)** | COLA uplift price fix verified, but Line Item Description still null on renewal lines + COLAUpliftPrehook at 3% coverage + not in force-app → **NOT good to go**."* — this is verbatim the SC-3350 verdict, filed under 3346.
2. **Daily report** line 70 (open follow-ups): *"**SC-3346** — blocked on renewal-line description + COLAUpliftPrehook coverage before sign-off."*
3. **Memory note** YAML description: *"COLA renewal pricing ticket (**SC-3346** per thread)…"* — explicitly says the **thread** uses 3346.
4. **Task prompt** (the user): Jomil Bell said the Leah Guenther waterfall image is *"relevant to SC-3346."*

**Interpretation (MEDIUM confidence):** SC-3346 is most plausibly the **parent Story/Feature (or the original/originating ticket)** of the COLA renewal-pricing effort, with **SC-3350** the specific defect Task carved out of it (and **SC-3354** a transient alias). The "(review)" tag on the 3346 daily line and the "per thread" note suggest 3346 is where the design-level discussion + Leah's waterfall image live, while SC-3350 is the actionable defect. This is **not provable from the repo** (no SC-3346 folder, no Jira access) — flag as needs-Jira-confirm.

**The Leah waterfall image is NOT in the repo** — searched `Jomil|Leah|waterfall` across all non-log docs; the only "waterfall" hits are the *pricing-procedure waterfall* (brief lines 75/80, an unrelated mechanism). So the image and Jomil's comment exist only in Jira.

---

## 4. SC-3349 (+ subtask SC-3352) — the DESCRIPTIONS ticket, distinct from SC-3350

Source: `*Jira/testing/SC-3349 Line Item Description Issues/README.md` (full, byte-cited below).
- **SC-3349** = Story, "Line Item Description Issues." The bug: beSECURE - Cloud-Based SKU rendered `Devices` but dropped the count `36-65` in `QuoteLineItem.Description` (feeds Workday + Legacy CRM). Fix = `QLDescriptionGeneratorPrehook.resolveUnitQuantity()` `Number_of_Units` fallback (Nir) + move `DescriptionLinePrehook` LAST in the RLM chain.
- **Status:** PEER REVIEW COMPLETE / approved 2026-06-07; 35/35 tests pass. (README lines 1-8, 60-64.)
- **Peer-review subtask = SC-3352** (README line 5, 63): Assignee Liam Jeong, Reporter Nir Kailash. This is the only concrete "peer review" *ticket number* in the entire repo — and it is SC-3349's, **not** COLA's.
- **Relationship to SC-3350 defect #2:** OVERLAPPING SUBJECT, DIFFERENT SCOPE. SC-3349 fixed *which attribute supplies the count* on a specific SKU (a content bug in the description builder). SC-3350 defect #2 is that **renewal lines get NO description at all** because the description prehook never *fires* on the headless renewal path (0 of 1.22M renewal lines have one). Same class (`QLDescriptionGeneratorPrehook`), different failure mode (wrong content vs. never-runs). The brief's §2 / `code_description.md` already note that SC-3350 defect #2 "lives in `QLDescriptionGeneratorPrehook`, NOT a COLA class" — so SC-3349 and SC-3350#2 touch the same file but are separate defects.

---

## 5. The "Peer Review ticket" question — resolved as far as the repo allows

- **Manager summary 2026-06-09** (`Data/daily-reports/2026-06-09-manager-summary.md`):
  - line 36 (Blocked table): `| **SC-3350** (Peer Review) | Peer review | Awaiting reviewer (Nir Kailash). |`
  - line 46: `**SC-3350** peer review needs a reviewer to keep it moving.`
- So in the current board, **SC-3350 itself is in/awaiting Peer Review** (reviewer = Nir Kailash). The flow per the memory note is: Marc built it → **Liam reworks → hands back to Nir for peer testing** (Jomil asked to keep it in-team). The "peer review" is therefore a **state of SC-3350**, surfaced on the board as a parenthetical, not necessarily a separate ticket.
- **Nir's "Peer Review ticket" (from the task prompt):** if Nir is referring to a **distinct Jira issue/subtask** (analogous to how SC-3352 is the peer-review subtask of SC-3349), that number is **NOT present anywhere in the repo**. The only peer-review subtask number that exists is SC-3352 (SC-3349's). → **Answer: UNKNOWN / needs Jira.** Do NOT assume it is SC-3354 or SC-3346; do NOT borrow SC-3352. Most likely SC-3350 *is* the peer-review vehicle, but a dedicated subtask number cannot be confirmed read-only.

---

## 6. Why grep "found nothing" at first (method caveat, for reproducibility)

- The top-level dir is literally named `*Jira` (leading asterisk). A bare `grep -ril "SC-3350" .` returns nothing useful / errors because the unquoted `*` and the recursive walk interact badly, and the `.cls`/log files dominate. **Use `find . -type f … -exec grep -l … \;` or quote the path** (`"…/*Jira/…"`).
- The `Data/sc3347/*-file.txt` and `fault_log.txt` "hits" for SC-3346/3349/3354 are **FALSE POSITIVES** — they are RLM debug-log dumps (`FLOW_VALUE_ASSIGNMENT` records) where the 4-digit substrings appear inside record Ids / GUIDs / field values (`COLACalculatedPrice__c`, etc.), not ticket references. Excluded from the frequency count.

**Repo-wide SC-33xx reference frequency (non-log):** SC-3308 (200), SC-3347 (127), SC-3339 (94), SC-3345 (85), SC-3359 (60), SC-3371 (48), SC-3372 (44), SC-3374/3366 (35), SC-3335 (28), SC-3360 (13), **SC-3350 (13)**, **SC-3354 (9)**, SC-3349 (7), SC-3352 (4), SC-3368 (3), **SC-3346 (2)**, SC-3375 (1), SC-3338 (1). → SC-3350 is the dominant COLA number; 3354 second; 3346 barely present (consistent with 3346 being a parent/thread-level ID rather than the working ticket).

---

## 7. Deltas vs the 08:13 brief

- The brief is **titled SC-3354** and never mentions SC-3350 or SC-3346 at all — so the brief itself is a contributor to the numbering confusion. The **current truth is SC-3350** (per the Task folder + board), which the brief predates/mislabels. DELTA: rename the work to SC-3350 in all going-forward artifacts; treat SC-3354 as a dead alias.
- Brief said COLAUpliftPrehook + COLAUpliftTest edited **16:51Z**; live `ApexClass.LastModifiedDate` now shows **16:58:15Z** (Marc DeBrey) — Marc saved the prehook/test **again** after the brief was written. (AssetContractQueryHelper 14:00:37Z, QLDescriptionGeneratorPrehook 14:41:27Z, COLAUpliftHandler 16:29:57Z all match the prompt.) Confirms the COLA classes are under active same-day rework — consistent with SC-3350 being the live ticket, and means code-level brief claims must be re-verified against the 16:58 prehook.

---

## 8. Confidence + open questions

**HIGH confidence:**
- SC-3350 is the canonical defect Task (dedicated folder + exact title + board entry).
- SC-3349 is a separate, approved descriptions ticket with peer-review subtask SC-3352.
- The Leah waterfall image + Jomil/Nir thread comments are NOT in the repo (Jira-only).
- Marc DeBrey re-edited all COLA classes today (live ApexClass timestamps).

**MEDIUM confidence:**
- SC-3350 ≡ SC-3354 (same work item; 3354 = alias). Can't 100% exclude 3354 being a sibling subtask without Jira.
- SC-3346 = parent/origin/thread-level ID of the COLA work.

**UNKNOWN / needs Jira (out of read-only repo scope):**
1. Is there a **distinct** "Peer Review ticket" number (Nir's phrasing) separate from SC-3350? Repo says no; only SC-3352 exists and it's SC-3349's. → confirm in Jira.
2. Exact parent/child links: is SC-3346 the parent Story of SC-3350? Is SC-3354 a subtask of 3346/3350 or just a renumber? → confirm in Jira issue hierarchy.
3. What does Leah Guenther's waterfall image (attached to SC-3346 per Jomil) actually show, and does it change the COLA pricing-base decision? → fetch from Jira.
