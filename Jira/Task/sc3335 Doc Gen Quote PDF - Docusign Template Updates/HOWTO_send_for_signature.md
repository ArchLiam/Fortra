# How to capture a signature on a Fortra Quote (SC-3335 #2)

**Short answer:** signature capture is already built — it happens through **DocuSign** at the *Send for
Signature* step of the Generate Document flow. The PDF *preview* doesn't show a signature line because
DocuSign places the signature tab on the envelope at **send** time, not on the preview.

## Steps (on a Quote record)
1. Click **Generate Document**.
2. The modal builds and shows the **PDF preview**. Review it, then click **Send Quote** (bottom of the preview step).
3. **Recipient Details** step — confirm/enter:
   - **Signer Email** (defaults to the Billing contact's email)
   - **Signer Name** — ⚠️ this **defaults to the Account/company name**, so type the actual **person's name** here before sending.
   - **Email Subject** (defaults to `[SIGNATURE REQUIRED] Fortra Quote | …`)
4. **Review and Send** step — final preview → click **Send for Signature**.
5. A **DocuSign envelope** is created and emailed to the signer. The confirmation step shows the **envelope ID / status**.
6. The signer opens the DocuSign email and signs — DocuSign presents a **Signature**, **Date**, and **Name** tab.

## What this means
- *Generate Document* alone = **preview/PDF only** (no signature — that's expected).
- *Send for Signature* = the step that actually requests the e-signature via DocuSign.
- The signed document comes back through DocuSign once the signer completes it.

## Known limitation (logged, not fixed under #2 per decision)
The DocuSign signature tab is placed at **fixed coordinates** (not anchored to a drawn signature line on
the document), so its position on the page is approximate. If the team later wants the signature to land
on an exact signature block, that's the "Option B" enhancement: add a signature block to the template +
switch `DocuSignEnvelopeService` to anchor-string tabs. **Decision (2026-06-04): leave as-is — the
function works; this was a how-to gap, not a defect.**

---
_Source: OmniScript `DocumentGeneration_Quote_English_3` → IP `Quote_SendDocuSignEnvelope` →
`DocuSignEnvelopeService.sendEnvelope`. Signer defaults: email = billTo email, name = billTo company
(`Quote_GenerateDoc_English_4`)._
