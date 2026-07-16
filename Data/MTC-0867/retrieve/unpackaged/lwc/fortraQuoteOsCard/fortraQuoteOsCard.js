/**
 * FortraQuoteOsCard
 *
 * Multi-template LWC used inside the Fortra Quote DocumentGeneration OmniScript.
 * Renders one of three variants based on the `variant` @api property:
 *   - step1         → Recipient intro card
 *   - step2         → Review and confirm card (with PDF preview modal)
 *   - confirmation  → Post-send success card
 *
 * Used as a Custom LWC element in OmniScript to replace Text Blocks, bypassing
 * the managed-package sanitizer that strips styled HTML with merge fields.
 *
 * @author  5S Infusion Corp
 */
import { LightningElement, api } from "lwc";

import routerTemplate from "./fortraQuoteOsCard.html";
import step1Template from "./fortraQuoteOsCardStep1.html";
import step2Template from "./fortraQuoteOsCardStep2.html";
import confirmTemplate from "./fortraQuoteOsCardConfirm.html";

export default class FortraQuoteOsCard extends LightningElement {
	/** Which template to render. Accepts: step1, step2, confirmation. */
	@api variant = "step1";

	/** Signer's display name. Used by step2 and confirmation. */
	@api signerName = "";

	/** Signer's email address. Used by step2. */
	@api signerEmail = "";

	/** Email subject line DocuSign will use. Used by step2. */
	@api emailSubject = "";

	/** PDF document title. Used by step2 and the preview modal. */
	@api documentTitle = "";

	/** DocuSign envelope ID returned from send. Used by confirmation. */
	@api envelopeId = "";

	/** DocuSign envelope status (e.g., "sent"). Used by confirmation. */
	@api envelopeStatus = "";

	/** ISO timestamp of the send event. Used by confirmation. */
	@api statusDateTime = "";

	/** Detected PDF page count. Used by confirmation. */
	@api pageCount = "";

	/**
	 * ContentVersion Id of the generated PDF. When present on step2, renders
	 * a "Preview PDF" button that opens an inline modal with the PDF embedded.
	 */
	@api pdfId = "";

	/** Tracks whether the PDF preview modal is open. */
	showPdfModal = false;

	render() {
		switch ((this.variant || "").toLowerCase()) {
			case "step2":
			case "review":
				return step2Template;
			case "confirmation":
			case "confirm":
			case "success":
				return confirmTemplate;
			case "step1":
			case "recipient":
				return step1Template;
			default:
				return routerTemplate;
		}
	}

	// ── Preview modal handlers ─────────────────────────────────────────────

	handleOpenPreview() {
		this.showPdfModal = true;
	}

	handleClosePreview() {
		this.showPdfModal = false;
	}

	handleStopPropagation(event) {
		event.stopPropagation();
	}

	/**
	 * Salesforce same-origin URL that streams the ContentVersion PDF for INLINE
	 * rendering in the iframe. The rendition endpoint always returns
	 * Content-Disposition: inline; the /version/download/ endpoint can return
	 * Content-Disposition: attachment in some orgs, forcing a download instead.
	 */
	get pdfPreviewUrl() {
		return this.pdfId
			? `/sfc/servlet.shepherd/version/renditionDownload?rendition=ORIGINAL_PDF&versionId=${this.pdfId}`
			: "";
	}

	/** True when pdfId is populated (controls Preview PDF button visibility). */
	get hasPdfId() {
		return !!this.pdfId && String(this.pdfId).trim().length > 0;
	}
}