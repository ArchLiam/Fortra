/**
 * @description Resolves source license list price for derived maintenance PBEs.
 *
 *              DISABLED: logic commented out per request — use Stamp_Source_List_Price
 *              flow instead. Do not deploy enabled logic until re-enabled.
 */
public with sharing class SourceListPriceResolver {

    public class ResolutionResult {
        public Decimal unitPrice;
        public String skipReason;

        public Boolean isResolved() {
            return unitPrice != null;
        }
    }

    public static ResolutionResult resolve(Id maintenancePbeId, Id pricebook2Id, String currencyIsoCode) {
        ResolutionResult result = new ResolutionResult();
        result.skipReason = 'SourceListPriceResolver disabled';
        return result;
    }
}