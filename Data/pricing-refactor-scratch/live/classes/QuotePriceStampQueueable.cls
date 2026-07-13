/**
 * @description Runs after RCA persist commits so partner unit / source list stamps are not
 *              overwritten by persistContextData. Used when repricing from the Transaction Line Editor.
 */
public class QuotePriceStampQueueable implements Queueable {
    private final Id quoteId;

    public QuotePriceStampQueueable(Id quoteId) {
        this.quoteId = quoteId;
    }

    public void execute(QueueableContext context) {
        PartnerNetPricePosthook.stampAttributeListPricesForQuote(quoteId);
    }
}