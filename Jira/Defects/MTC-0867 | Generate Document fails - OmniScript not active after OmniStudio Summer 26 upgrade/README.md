# MTC-0867 — "Generate Document" fails: OmniScript "DocumentGeneration / Quote / English" not active

**Status:** ✅ Root cause identified & verified · Fix is a 2-minute in-org OmniScript re-activation (UI) — **not yet applied** (needs authorization; UAT change)
**Org:** FortraUAT (`fortra--uat`, `00DWC000006eUFF2A2`)
**Date:** 2026-07-15
**Severity:** High — blocks quote document generation for **all** users on **all** quotes

---

## 1. Symptom

User *Victoria Mullady* (and other users) click **Generate Document** on a Quote and get:

- **Modal:** *"OmniScript 'DocumentGeneration / Quote / English' is not active, please contact your Salesforce Administrator."*
- **Console error:** `"forceGenerated/omniScript_DocumentGeneration___Quote___English___lightning___false___DefaultLabel___brand___ltr" was not found`

Reproduces on **every** quote regardless of status (Approved included) and for **multiple users** — it is **not** quote-data-specific and **not** a per-user permission problem.

Reference quote in report: `0Q0WC000002Q1mD0AS`. Reproduced live as Victoria Mullady on quote `00488534` (*MSRP* Coterm, Approved).

---

## 2. Root cause (high confidence)

**An OmniStudio managed-package upgrade changed how the runtime loads the compiled OmniScript LWC, and the active Document-Generation OmniScript was never re-activated after the upgrade — so the compiled artifact the new runtime looks for does not exist.**

### The mechanism, step by step
1. The **Generate Document** button is the Quote QuickAction `Generate_Document` (type *LightningWebComponent*) → hosts the custom wrapper LWC **`docGenOmniScriotWrapperLWC`** → whose template renders the managed component
   `<omnistudio-omnistudio-standard-runtime-wrapper type="DocumentGeneration" subtype="Quote" language="English">`.
2. That wrapper resolves the **active** OmniScript by Type/SubType/Language and dynamically **imports its compiled LWC module**.
3. **OmniStudio was upgraded to `262.5.0` "Summer 2026" on 2026-06-04** (all 85 `omnistudio`-namespace base LWCs bear LastModified `2026-06-04T09:59Z` — the upgrade stamp). This upgrade advances the **Standard OmniStudio Runtime**: the compiled component is now resolved under a **new internal module name** — `forceGenerated/omniScript_<Type>___<SubType>___<Language>___lightning___<inline>___<label>___<variant>___<dir>`.
4. The active OmniScript **"Fortra Quote Generate Document"** (`DocumentGeneration/Quote/English`, **v3**, `0jNWC0000006ZuL2AU`, `IsActive=true`) was **last activated 2026-04-20 — before the upgrade.** Its only compiled artifact is the **legacy-named** bundle `documentGenerationQuoteEnglish` (org namespace, unmanaged, apiVersion 62, description *"Vlocity OmniScript Auto-generated - 0jNWC0000006ZuL2AU"*, LastModified `2026-04-20T23:24:17` — 2s after the v3 activation, the textbook generated-on-activation signature).
5. The **new-format `forceGenerated/…` module was never generated** (the script hasn't been re-activated since the upgrade). The runtime's dynamic import rejects → the wrapper throws its **"OmniScript … is not active"** fallback modal, while the console shows the true cause **"… was not found."**

The `IsActive=true` DB flag is genuine, but the runtime keys "active" off **finding the compiled native module**, not the flag — hence the misleading modal.

### Proof the requested name maps to *this* OmniScript
The requested module `omniScript_DocumentGeneration___Quote___English___lightning___false___DefaultLabel___brand___ltr` decodes to **Type=DocumentGeneration, SubType=Quote, Language=English** plus the v3 **target-config defaults**: `inline=false`, `inlineLabel=DefaultLabel`, `inlineVariant=brand`, `dir=ltr` — which match the generated LWC's `.js-meta.xml` exactly. The resolver is computing a **correct** name for an artifact that was **never built**.

### Why it broke *now*
This flow worked and was verified in-org on **2026-06-04** (SC-3335), i.e. at/just before the `09:59Z` upgrade stamp. The v3 activation (04-20) predates the runtime change bundled with the upgrade → it broke immediately after.

### What Salesforce documentation confirms
- *"LWCs that existed before … enabling Standard OmniStudio Runtime **will run in standard runtime the next time they're reactivated**."* (Standard OmniStudio Content and Runtime)
- *"A package-generated OmniScript or FlexCard component can run natively in your org **through deactivation and reactivation**."*
- Salesforce's **Document Generation post-upgrade guide** lists *"**Activate the Latest Document Generation OmniScripts** for OmniStudio"* as a **required** post-upgrade task.
- The literal `forceGenerated/…` string is an **internal, undocumented** native-runtime module name — its presence is the fingerprint of native-runtime module resolution, not a separate error code.

---

## 3. Alternatives ruled out (adversarial pass)

| Candidate cause | Ruled | Why |
|---|---|---|
| Missing OmniStudio PSL / permission set | **out** | The wrapper renders and reaches its resolver; a perm gap faults earlier as "insufficient privileges", not a specific module-not-found. Fails for **admins** too. |
| Missing `ContentDocumentLink` on template file (the SC-845 / Joe Romo class) | **out** | That produces *"List has no rows for assignment to SObject"* at merge time — a different, later error. Here the OmniScript never even loads. |
| FLS on referenced fields | **out (as driver)** | Fails for all users incl. admins, all quotes, immediately post-upgrade → runtime-regeneration, not FLS. *(Native runtime does enforce FLS more strictly — confirm FLS after re-activating so the component compiles cleanly.)* |
| OmniProcess genuinely inactive / corrupt / duplicate active version | **out** | Verified `v3 IsActive=true`, `v2 IsActive=false`; single active version; decoded name matches. |
| Broken custom wrapper LWC | **out** | Wrapper is unchanged (2026-04) and successfully delegates to the managed runtime component. |
| Gearset/deploy didn't ship the LWC / cache/CDN | **out** | Server-confirmed absence of the `forceGenerated` bundle across users; legacy bundle present and correct. |

---

## 4. Resolution

**Re-activate the OmniScript so the platform regenerates its compiled LWC under the current (v262) runtime.** No metadata deploy, no record-data change. The OmniProcess Id/version stay the same, so the `Generate_Document` ScreenAction (which resolves by Type/SubType/Language, not Id) keeps pointing at it.

### Click-path (OmniStudio / OmniScript Designer)
1. App Launcher → **OmniStudio** app (Summer '26 Standard Designer).
2. **OmniScripts** tab → open **"Fortra Quote Generate Document"** (Type/SubType/Language = `DocumentGeneration / Quote / English`).
3. Version dropdown → select the **active Version 3**.
4. Click **Deactivate Version** (a straight Activate is disabled while `IsActive=true`).
5. Click **Activate Version**, confirm; wait ~30–60s for the compile/regeneration to finish.

**Fallback if v3 refuses to deactivate or still emits only the legacy bundle:** create a **New Version** (v4) and **Activate** it — same regeneration effect, cleaner.

### Verify (must confirm empirically)
- **Hard-refresh** the browser (clears the cached failed import).
- As Victoria Mullady (or any user), open a Quote → **Generate Document** → the OmniScript launches (template picker / doc flow) with no modal.
- Optionally confirm a native/`forceGenerated` artifact now materializes and the console error is gone.

### ⚠️ Do this in a maintenance window
There is a brief availability gap (~30–60s) between Deactivate and Activate; a user mid-flow could hit an error during that window.

---

## 5. Blast radius & follow-up remediation

Every **OmniScript *and* FlexCard** whose **last activation predates 2026-06-04** carries the same stale-compiled-LWC risk and should be **deactivated + re-activated**. Audit, don't blindly mass-activate.

- Active non-IP OmniScripts today (all pre-upgrade): **`DocumentGeneration/Quote/English` v3** (the defect) + 3 Salesforce sample scripts `docGenerationSample/*` (likely unused — re-activate only if used).
- **FlexCards** auto-compile an LWC on activation → same risk; re-activate pre-upgrade ones (children first, dependency order).
- **Integration Procedures & DataRaptors are UNAFFECTED** — they run server-side and generate no LWC.
- **No native "Activate All" button exists.** Fleet-wide cleanup needs a scripted path (OmniStudio Build Tool / IDX `packDeploy`, or a headless compile-page driver) run in a maintenance window.
- **Do NOT change the org's OmniStudio runtime-mode setting** as part of this fix — the wrapper already requests the native `forceGenerated` name, so re-activation under the existing setting is sufficient. Toggling runtime mode is out of scope and adds risk.
- **Watch for v262 compile failures:** a script that activated cleanly under the old package can throw *new* validation errors under v262 (deprecated element/property). If activation fails, it escalates beyond a simple re-activation → Salesforce Support (known-issue path).
- **Production:** this is not prod-specific. Plan the identical audited mass re-activation for Production **when it takes the v262 upgrade**.

---

## 6. Evidence (verified via `sf` CLI against FortraUAT)

- OmniStudio installed package: **`OmniStudio` v262.5.0 "Summer 2026"**.
- All 85 `omnistudio`-ns base LWCs LastModified **2026-06-04T09:59Z** (upgrade stamp).
- `OmniProcess` `DocumentGeneration/Quote/English`: **v3 `IsActive=true`** (`0jNWC0000006ZuL2AU`), v2 inactive; v3 LastModified **2026-04-20T23:24:15Z**.
- Generated LWC `documentGenerationQuoteEnglish`: null ns, unmanaged, apiVersion 62, `OMNIDEF.sOmniScriptId=0jNWC0000006ZuL2AU`, LastModified **2026-04-20T23:24:17Z**.
- **No** `forceGenerated/omniScript_…` bundle exists in the org.
- Button = Quote QuickAction `Generate_Document` (LightningWebComponent) → `docGenOmniScriotWrapperLWC` → `omnistudio-omnistudio-standard-runtime-wrapper`.

Retrieved source used in this analysis: [`Data/MTC-0867/retrieve/`](../../../Data/MTC-0867/) (wrapper LWC, generated LWC, `fortraQuoteOsCard`).

---

## 7. References
- Salesforce Help — *Standard OmniStudio Content and Runtime* / *Enable Standard OmniStudio Runtime*
- Salesforce Help — *Document Generation: Post Install and Upgrade Steps* ("Activate the Latest Document Generation OmniScripts")
- Salesforce Help — *OmniScript Activation & Access Issues* (deactivate→activate fix; "No MODULE named markup://c:… found")
