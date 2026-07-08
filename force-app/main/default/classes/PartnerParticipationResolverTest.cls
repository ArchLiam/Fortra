@IsTest
private class PartnerParticipationResolverTest {

    static final Id BILLING = '001000000000001AAA';
    static final Id RESELLER = '001000000000002AAA';
    static final Id DISTRIB = '001000000000003AAA';
    static final Id REFERRAL = '001000000000004AAA';

    @IsTest
    static void collectPartnerIds_discountModelBillingOnly() {
        Set<Id> ids = PartnerParticipationResolver.collectPartnerIds(BILLING, false, RESELLER, DISTRIB, REFERRAL);
        System.assertEquals(new Set<Id>{ BILLING }, ids, 'non-GM -> billing partner only');
    }

    @IsTest
    static void collectPartnerIds_guaranteedMarginIncludesAllPresent() {
        Set<Id> ids = PartnerParticipationResolver.collectPartnerIds(BILLING, true, RESELLER, null, REFERRAL);
        System.assertEquals(new Set<Id>{ BILLING, RESELLER, REFERRAL }, ids,
            'GM -> billing + present downstream partners (null distributor skipped)');
    }

    @IsTest
    static void collectPartnerIds_nullBillingEmpty() {
        System.assertEquals(0,
            PartnerParticipationResolver.collectPartnerIds(null, true, RESELLER, DISTRIB, REFERRAL).size(),
            'no billing partner -> empty');
    }

    @IsTest
    static void resolvePartnerRole_mapsEachRoleElseUnknown() {
        System.assertEquals('Billing Partner', PartnerParticipationResolver.resolvePartnerRole(BILLING, BILLING, RESELLER, DISTRIB, REFERRAL));
        System.assertEquals('Reseller', PartnerParticipationResolver.resolvePartnerRole(RESELLER, BILLING, RESELLER, DISTRIB, REFERRAL));
        System.assertEquals('Distributor', PartnerParticipationResolver.resolvePartnerRole(DISTRIB, BILLING, RESELLER, DISTRIB, REFERRAL));
        System.assertEquals('Referral Partner', PartnerParticipationResolver.resolvePartnerRole(REFERRAL, BILLING, RESELLER, DISTRIB, REFERRAL));
        System.assertEquals('Unknown', PartnerParticipationResolver.resolvePartnerRole('001000000000009AAA', BILLING, RESELLER, DISTRIB, REFERRAL));
    }
}
