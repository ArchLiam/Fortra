/**
 * @description Pure partner-participation resolution extracted verbatim from PartnerPricingPrehookV2
 *              (Wave-2 hook-thinning): which partner accounts participate on a line, and each
 *              partner's role. No SOQL/DML/context — deterministic over Id/boolean inputs. The hook
 *              shell owns the QuoteHeaderData DTO and passes its fields (plus the isGuaranteedMargin
 *              boolean) in, so this stays decoupled from that inner type.
 */
public with sharing class PartnerParticipationResolver {

    /**
     * @description Participating partner accounts: the billing partner always; for Guaranteed
     *              Margin, also the reseller / distributor / referral partner when present.
     */
    public static Set<Id> collectPartnerIds(
        Id billingPartnerId,
        Boolean isGuaranteedMargin,
        Id resellerId,
        Id distributorId,
        Id referralPartnerId
    ) {
        Set<Id> partnerIds = new Set<Id>();
        if (billingPartnerId == null) {
            return partnerIds;
        }
        partnerIds.add(billingPartnerId);
        if (isGuaranteedMargin) {
            if (resellerId != null) {
                partnerIds.add(resellerId);
            }
            if (distributorId != null) {
                partnerIds.add(distributorId);
            }
            if (referralPartnerId != null) {
                partnerIds.add(referralPartnerId);
            }
        }
        return partnerIds;
    }

    /** @description Role of a partner relative to the quote header (else 'Unknown'). */
    public static String resolvePartnerRole(
        Id partnerId,
        Id billingPartnerId,
        Id resellerId,
        Id distributorId,
        Id referralPartnerId
    ) {
        if (partnerId == billingPartnerId) {
            return 'Billing Partner';
        } else if (partnerId == resellerId) {
            return 'Reseller';
        } else if (partnerId == distributorId) {
            return 'Distributor';
        } else if (partnerId == referralPartnerId) {
            return 'Referral Partner';
        }
        return 'Unknown';
    }
}
