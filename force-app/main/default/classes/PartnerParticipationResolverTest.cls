/**
 * @description Unit tests for PartnerParticipationResolver, covering partner-Id
 * collection under discount-model vs guaranteed-margin scenarios and partner-role
 * resolution precedence.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
@IsTest
private class PartnerParticipationResolverTest {

    static final Id BILLING = '001000000000001AAA';
    static final Id RESELLER = '001000000000002AAA';
    static final Id DISTRIB = '001000000000003AAA';
    static final Id REFERRAL = '001000000000004AAA';

    /**
     * @description Verifies that under a non-guaranteed-margin (discount) model only the
     * billing partner is collected, ignoring downstream reseller/distributor/referral.
     */
    @IsTest
    static void collectPartnerIds_discountModelBillingOnly() {
        Set<Id> ids = PartnerParticipationResolver.collectPartnerIds(BILLING, false, RESELLER, DISTRIB, REFERRAL);
        System.assertEquals(new Set<Id>{ BILLING }, ids, 'non-GM -> billing partner only');
    }

    /**
     * @description Verifies that under guaranteed margin the billing partner plus all present
     * downstream partners are collected, while a null distributor is skipped.
     */
    @IsTest
    static void collectPartnerIds_guaranteedMarginIncludesAllPresent() {
        Set<Id> ids = PartnerParticipationResolver.collectPartnerIds(BILLING, true, RESELLER, null, REFERRAL);
        System.assertEquals(new Set<Id>{ BILLING, RESELLER, REFERRAL }, ids,
            'GM -> billing + present downstream partners (null distributor skipped)');
    }

    /**
     * @description Verifies that a null billing partner yields an empty set even under
     * guaranteed margin with downstream partners present.
     */
    @IsTest
    static void collectPartnerIds_nullBillingEmpty() {
        System.assertEquals(0,
            PartnerParticipationResolver.collectPartnerIds(null, true, RESELLER, DISTRIB, REFERRAL).size(),
            'no billing partner -> empty');
    }

    /**
     * @description Verifies that each partner Id maps to its role label (Billing Partner,
     * Reseller, Distributor, Referral Partner) and an unmatched Id resolves to Unknown.
     */
    @IsTest
    static void resolvePartnerRole_mapsEachRoleElseUnknown() {
        System.assertEquals('Billing Partner', PartnerParticipationResolver.resolvePartnerRole(BILLING, BILLING, RESELLER, DISTRIB, REFERRAL));
        System.assertEquals('Reseller', PartnerParticipationResolver.resolvePartnerRole(RESELLER, BILLING, RESELLER, DISTRIB, REFERRAL));
        System.assertEquals('Distributor', PartnerParticipationResolver.resolvePartnerRole(DISTRIB, BILLING, RESELLER, DISTRIB, REFERRAL));
        System.assertEquals('Referral Partner', PartnerParticipationResolver.resolvePartnerRole(REFERRAL, BILLING, RESELLER, DISTRIB, REFERRAL));
        System.assertEquals('Unknown', PartnerParticipationResolver.resolvePartnerRole('001000000000009AAA', BILLING, RESELLER, DISTRIB, REFERRAL));
    }

    /**
     * @description Verifies that under guaranteed margin with every downstream partner present
     * all four distinct partner Ids are collected.
     */
    @IsTest
    static void collectPartnerIds_guaranteedMarginAllPresentIncludesAllFour() {
        Set<Id> ids = PartnerParticipationResolver.collectPartnerIds(BILLING, true, RESELLER, DISTRIB, REFERRAL);
        System.assertEquals(new Set<Id>{ BILLING, RESELLER, DISTRIB, REFERRAL }, ids,
            'GM with every downstream partner present -> all four');
    }

    /**
     * @description Verifies that under guaranteed margin with all downstream partners null
     * only the billing partner is collected.
     */
    @IsTest
    static void collectPartnerIds_guaranteedMarginAllDownstreamNullBillingOnly() {
        Set<Id> ids = PartnerParticipationResolver.collectPartnerIds(BILLING, true, null, null, null);
        System.assertEquals(new Set<Id>{ BILLING }, ids,
            'GM but no downstream partners -> billing partner only');
    }

    /**
     * @description Verifies that when the billing partner also fills the reseller role the
     * returned Set dedups the shared Id to a single entry.
     */
    @IsTest
    static void collectPartnerIds_guaranteedMarginDedupsSharedId() {
        // Billing partner also acts as the reseller -> Set dedups to a single Id.
        Set<Id> ids = PartnerParticipationResolver.collectPartnerIds(BILLING, true, BILLING, DISTRIB, null);
        System.assertEquals(new Set<Id>{ BILLING, DISTRIB }, ids,
            'billing==reseller collapses to one entry (Set dedup)');
    }

    /**
     * @description Verifies that a null billing partner under a non-guaranteed-margin model
     * yields an empty set.
     */
    @IsTest
    static void collectPartnerIds_nullBillingNonGuaranteedEmpty() {
        System.assertEquals(0,
            PartnerParticipationResolver.collectPartnerIds(null, false, RESELLER, DISTRIB, REFERRAL).size(),
            'no billing partner (non-GM) -> empty');
    }

    /**
     * @description Verifies that when one Id fills both billing and reseller roles the
     * billing-partner role takes precedence (first match wins).
     */
    @IsTest
    static void resolvePartnerRole_billingWinsWhenSharedWithReseller() {
        // partnerId matches both billing and reseller -> first match (Billing Partner) wins.
        System.assertEquals('Billing Partner',
            PartnerParticipationResolver.resolvePartnerRole(BILLING, BILLING, BILLING, DISTRIB, REFERRAL),
            'billing precedence over reseller when the same Id fills both roles');
    }

    /**
     * @description Verifies that when one Id fills both distributor and referral roles the
     * distributor role takes precedence (checked first).
     */
    @IsTest
    static void resolvePartnerRole_distributorWinsWhenSharedWithReferral() {
        // partnerId matches both distributor and referral -> distributor is checked first.
        System.assertEquals('Distributor',
            PartnerParticipationResolver.resolvePartnerRole(DISTRIB, BILLING, RESELLER, DISTRIB, DISTRIB),
            'distributor precedence over referral when the same Id fills both roles');
    }

    /**
     * @description Verifies that a null partner Id resolved against a non-null billing partner
     * returns Unknown rather than matching any role.
     */
    @IsTest
    static void resolvePartnerRole_nullPartnerWithNonNullBillingIsUnknown() {
        System.assertEquals('Unknown',
            PartnerParticipationResolver.resolvePartnerRole(null, BILLING, RESELLER, DISTRIB, REFERRAL),
            'null partnerId against a non-null billing partner -> Unknown');
    }
}