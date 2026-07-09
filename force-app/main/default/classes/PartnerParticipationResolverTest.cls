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

    @IsTest
    static void collectPartnerIds_guaranteedMarginAllPresentIncludesAllFour() {
        Set<Id> ids = PartnerParticipationResolver.collectPartnerIds(BILLING, true, RESELLER, DISTRIB, REFERRAL);
        System.assertEquals(new Set<Id>{ BILLING, RESELLER, DISTRIB, REFERRAL }, ids,
            'GM with every downstream partner present -> all four');
    }

    @IsTest
    static void collectPartnerIds_guaranteedMarginAllDownstreamNullBillingOnly() {
        Set<Id> ids = PartnerParticipationResolver.collectPartnerIds(BILLING, true, null, null, null);
        System.assertEquals(new Set<Id>{ BILLING }, ids,
            'GM but no downstream partners -> billing partner only');
    }

    @IsTest
    static void collectPartnerIds_guaranteedMarginDedupsSharedId() {
        // Billing partner also acts as the reseller -> Set dedups to a single Id.
        Set<Id> ids = PartnerParticipationResolver.collectPartnerIds(BILLING, true, BILLING, DISTRIB, null);
        System.assertEquals(new Set<Id>{ BILLING, DISTRIB }, ids,
            'billing==reseller collapses to one entry (Set dedup)');
    }

    @IsTest
    static void collectPartnerIds_nullBillingNonGuaranteedEmpty() {
        System.assertEquals(0,
            PartnerParticipationResolver.collectPartnerIds(null, false, RESELLER, DISTRIB, REFERRAL).size(),
            'no billing partner (non-GM) -> empty');
    }

    @IsTest
    static void resolvePartnerRole_billingWinsWhenSharedWithReseller() {
        // partnerId matches both billing and reseller -> first match (Billing Partner) wins.
        System.assertEquals('Billing Partner',
            PartnerParticipationResolver.resolvePartnerRole(BILLING, BILLING, BILLING, DISTRIB, REFERRAL),
            'billing precedence over reseller when the same Id fills both roles');
    }

    @IsTest
    static void resolvePartnerRole_distributorWinsWhenSharedWithReferral() {
        // partnerId matches both distributor and referral -> distributor is checked first.
        System.assertEquals('Distributor',
            PartnerParticipationResolver.resolvePartnerRole(DISTRIB, BILLING, RESELLER, DISTRIB, DISTRIB),
            'distributor precedence over referral when the same Id fills both roles');
    }

    @IsTest
    static void resolvePartnerRole_nullPartnerWithNonNullBillingIsUnknown() {
        System.assertEquals('Unknown',
            PartnerParticipationResolver.resolvePartnerRole(null, BILLING, RESELLER, DISTRIB, REFERRAL),
            'null partnerId against a non-null billing partner -> Unknown');
    }
}
