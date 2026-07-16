*Root cause identified — fix is a 2-minute in-org re-activation (no code deploy).*

h4. What's happening
"Generate Document" on a Quote fails for all users on all quotes with:
* Modal: _"OmniScript 'DocumentGeneration / Quote / English' is not active…"_
* Console: {{"forceGenerated/omniScript_DocumentGeneration___Quote___English___lightning___false___DefaultLabel___brand___ltr" was not found}}

It is *not* a permission or per-quote issue — it's global.

h4. Root cause
The *OmniStudio managed package was upgraded to 262.5.0 "Summer 2026" on 2026-06-04*. That upgrade changes how the runtime loads the compiled OmniScript component (it now imports an internal {{forceGenerated/…}} module).

Our Document-Generation OmniScript ("Fortra Quote Generate Document", DocumentGeneration/Quote/English, *v3*) was *last activated 2026-04-20 — before the upgrade*. So the org only has the old-format compiled component ({{documentGenerationQuoteEnglish}}); the new {{forceGenerated/…}} artifact the upgraded runtime looks for was never generated → "was not found" → the wrapper shows the misleading "not active" modal. The record's Active flag is genuinely true; the runtime just can't find the compiled module.

This matches Salesforce's own guidance: components activated before the runtime change _"run in standard runtime the next time they're reactivated,"_ and DocGen's post-upgrade steps explicitly require _"Activate the Latest Document Generation OmniScripts."_

h4. Fix (Admin, OmniStudio Designer — do in a maintenance window)
# Open OmniStudio → OmniScripts → *Fortra Quote Generate Document* (DocumentGeneration / Quote / English).
# Select the active *Version 3* → *Deactivate Version* → *Activate Version* (wait ~30–60s for it to recompile).
# Hard-refresh the browser, then test "Generate Document" on a Quote.

No metadata deploy or data change; the OmniProcess Id/version don't change, so the button keeps working.
_Fallback if v3 won't deactivate:_ create + activate a new Version 4 (same effect).

h4. Important follow-up
This is an org-wide upgrade side effect. *Every OmniScript and FlexCard last activated before 2026-06-04 has the same risk* and should be re-activated (Integration Procedures / DataRaptors are unaffected). And plan the *identical re-activation in Production* when it takes the Summer '26 (v262) OmniStudio upgrade.
