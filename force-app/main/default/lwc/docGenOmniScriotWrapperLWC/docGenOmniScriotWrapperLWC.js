/**
  @description       : Wrapper LWC wrapping Fortra Quote Generate Document(DocumentGeneration_Quote)
  @author            : LJ: liam.jeong.c@fortra.com
  @created on        : 2026-04-08
  @last modified on  : 2026-04-11
  @last modified by  : LJ: liam.jeong.c@fortra.com
 */
import { LightningElement, api } from "lwc";

export default class DocGenOmniScriotWrapperLWC extends LightningElement {
	@api recordId;

	get prefillData() {
		return JSON.stringify({
			ContextId: this.recordId,
			ObjectId: this.recordId,
			QuoteId: this.recordId,
		});
	}

	renderedCallback() {
		// eslint-disable-next-line @lwc/lwc/no-async-operation
		setTimeout(() => {
			const modal = document.querySelector(".slds-modal__container");
			if (modal) {
				modal.style.maxWidth = "90vw";
				modal.style.width = "90vw";
			}
		}, 300);
	}
}