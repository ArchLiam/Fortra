/**
 * @description Pure partner-participation resolution extracted verbatim from PartnerPricingPrehookV2
 *              (Wave-2 hook-thinning): which partner accounts participate on a line, and each
 *              partner's role. No SOQL/DML/context — deterministic over Id/boolean inputs. The hook
 *              shell owns the QuoteHeaderData DTO and passes its fields (plus the isGuaranteedMargin
 *              boolean) in, so this stays decoupled from that inner type.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public with sharing class PartnerParticipationResolver {

    /**
     * @description Participating partner accounts: the billing partner always; for Guaranteed
     *              Margin, also the reseller / distributor / referral partner when present.
     * @param billingPartnerId The billing partner account; when null no partners participate.
     * @param isGuaranteedMargin Whether Guaranteed Margin applies, widening participation to the extra roles.
     * @param resellerId The reseller partner account, included only under Guaranteed Margin when non-null.
     * @param distributorId The distributor partner account, included only under Guaranteed Margin when non-null.
     * @param referralPartnerId The referral partner account, included only under Guaranteed Margin when non-null.
     * @return The set of participating partner account Ids (empty when the billing partner is null).
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

    /**
     * @description Role of a partner relative to the quote header (else 'Unknown').
     * @param partnerId The partner account whose role is being resolved.
     * @param billingPartnerId The billing partner account for the quote header.
     * @param resellerId The reseller partner account for the quote header.
     * @param distributorId The distributor partner account for the quote header.
     * @param referralPartnerId The referral partner account for the quote header.
     * @return The matched role label ('Billing Partner', 'Reseller', 'Distributor', 'Referral Partner') or 'Unknown'.
     */
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