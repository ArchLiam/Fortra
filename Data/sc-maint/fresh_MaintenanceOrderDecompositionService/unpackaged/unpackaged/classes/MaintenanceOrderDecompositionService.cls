/**
 * @description FORTRA-PRODUCT-018 Step 5: persists maintenance dollar decomposition
 *              (Base, Partner$, Discretionary$) onto OrderItem at quote-to-order conversion
 *              so renewal pricing can carry real dollars forward.
 */
public with sharing class MaintenanceOrderDecompositionService {

    private static final Set<String> NEW_BUSINESS_QUOTE_TYPES = new Set<String>{
        'New', 'Net-New'
    };

    @TestVisible
    private static final String MAINTENANCE_TIER_ATTRIBUTE = 'Maintenance Type Defn';

    public class Decomposition {
        public Decimal maintenanceBase;
        public Decimal partnerDiscount;
        public Decimal discretionaryDiscount;
    }

    /**
     * @description Bulk-loaded order context shared by seed / patch operations so reprice
     *              does not repeat the same SOQL in a single transaction.
     */
    @TestVisible
    public class OrderMaintenanceWork {
        public Id orderId;
        public Boolean isNewBusiness = false;
        public List<OrderItem> allOrderItems = new List<OrderItem>();
        public Map<Id, QuoteLineItem> qliById = new Map<Id, QuoteLineItem>();
        public Set<Id> derivedPbeIds = new Set<Id>();
        public Map<Id, String> tierByQliId = new Map<Id, String>();
    }

    /**
     * @description Loads all order-line and quote-line data needed for derived maintenance
     *              seeding and decomposition in one pass.
     */
    @TestVisible
    public static OrderMaintenanceWork loadWork(Id orderId) {
        OrderMaintenanceWork work = new OrderMaintenanceWork();
        work.orderId = orderId;

        if (orderId == null) {
            return work;
        }

        Order ord = [
            SELECT Id, Quote.QuoteTypeText__c
            FROM Order
            WHERE Id = :orderId
            LIMIT 1
        ];
        work.isNewBusiness = NEW_BUSINESS_QUOTE_TYPES.contains(ord.Quote.QuoteTypeText__c);

        work.allOrderItems = [
            SELECT Id, QuoteLineItemId, PricebookEntryId, Quantity,
                   Hardware__c, Hardware_ID__c, Partition_Record__c, Ship_To_Address__c
            FROM OrderItem
            WHERE OrderId = :orderId
        ];

        Set<Id> qliIds = new Set<Id>();
        Set<Id> pbeIds = new Set<Id>();
        for (OrderItem oi : work.allOrderItems) {
            if (oi.QuoteLineItemId == null) {
                continue;
            }
            qliIds.add(oi.QuoteLineItemId);
            if (oi.PricebookEntryId != null) {
                pbeIds.add(oi.PricebookEntryId);
            }
        }

        if (qliIds.isEmpty()) {
            return work;
        }

        work.qliById = new Map<Id, QuoteLineItem>([
            SELECT Id, Base_Price__c, UnitPrice, NetUnitPrice, PartnerUnitPrice,
                   Fortra_Product_Type__c, PricebookEntryId,
                   Hardware__c, Hardware_ID__c, Partition_Reference__c,
                   Quote.Ship_To_Place__c
            FROM QuoteLineItem
            WHERE Id IN :qliIds
        ]);

        if (!work.isNewBusiness) {
            return work;
        }

        work.derivedPbeIds = loadDerivedPricebookEntryIds(pbeIds);
        work.tierByQliId = loadMaintenanceTierByQliId(qliIds);

        return work;
    }

    /**
     * @return OrderItem patches keyed by OrderItem Id (Id-only stubs with decomposition fields set).
     */
    public static Map<Id, OrderItem> buildPatches(Id orderId) {
        return buildPatchesFromWork(loadWork(orderId));
    }

    @TestVisible
    public static Map<Id, OrderItem> buildPatchesFromWork(OrderMaintenanceWork work) {
        Map<Id, OrderItem> patches = new Map<Id, OrderItem>();

        if (work == null || !work.isNewBusiness || work.allOrderItems.isEmpty()) {
            return patches;
        }

        for (OrderItem oi : work.allOrderItems) {
            if (oi.QuoteLineItemId == null) {
                continue;
            }

            QuoteLineItem qli = work.qliById.get(oi.QuoteLineItemId);
            if (qli == null || qli.Base_Price__c == null) {
                continue;
            }
            if (!work.derivedPbeIds.contains(qli.PricebookEntryId)) {
                continue;
            }

            Decomposition decomp = compute(
                qli.Base_Price__c,
                qli.UnitPrice,
                qli.PartnerUnitPrice,
                qli.NetUnitPrice,
                work.tierByQliId.get(qli.Id)
            );

            if (decomp.maintenanceBase == null || decomp.maintenanceBase <= 0) {
                continue;
            }

            Decimal commercialNet = resolveNetPrice(
                qli.UnitPrice,
                qli.NetUnitPrice,
                decomp.maintenanceBase
            );
            Decimal quantity = oi.Quantity != null && oi.Quantity > 0 ? oi.Quantity : 1;

            patches.put(oi.Id, new OrderItem(
                Id = oi.Id,
                Base_Price__c = decomp.maintenanceBase,
                Prior_Partner_Discount__c = decomp.partnerDiscount,
                Prior_Discretionary_Discount__c = decomp.discretionaryDiscount,
                UnitPrice = commercialNet,
                NetUnitPrice = commercialNet,
                PartnerUnitPrice = qli.PartnerUnitPrice,
                TotalLineAmount = (commercialNet * quantity).setScale(2, RoundingMode.HALF_UP)
            ));
        }

        return patches;
    }

    /**
     * @description Re-applies quote commercial net on every linked order line after reprice.
     *              Merges derived-maintenance decomposition fields when present.
     */
    @TestVisible
    public static Map<Id, OrderItem> buildCommercialPatchesFromWork(OrderMaintenanceWork work) {
        Map<Id, OrderItem> patches = new Map<Id, OrderItem>();

        if (work == null || !work.isNewBusiness || work.allOrderItems.isEmpty()) {
            return patches;
        }

        Map<Id, OrderItem> decompositionPatches = buildPatchesFromWork(work);

        for (OrderItem oi : work.allOrderItems) {
            if (oi.QuoteLineItemId == null) {
                continue;
            }

            QuoteLineItem qli = work.qliById.get(oi.QuoteLineItemId);
            if (qli == null) {
                continue;
            }

            OrderItem decompPatch = decompositionPatches.get(oi.Id);
            Decimal commercialNet = decompPatch != null && decompPatch.UnitPrice != null
                ? decompPatch.UnitPrice
                : resolveCommercialUnitPrice(qli);
            if (commercialNet == null || commercialNet <= 0) {
                continue;
            }

            Decimal quantity = oi.Quantity != null && oi.Quantity > 0 ? oi.Quantity : 1;
            Decimal lineTotal = (commercialNet * quantity).setScale(2, RoundingMode.HALF_UP);
            Decimal partnerUnit = qli.PartnerUnitPrice != null && qli.PartnerUnitPrice > 0
                ? qli.PartnerUnitPrice
                : commercialNet;

            patches.put(oi.Id, new OrderItem(
                Id = oi.Id,
                UnitPrice = commercialNet,
                NetUnitPrice = commercialNet,
                PartnerUnitPrice = partnerUnit,
                TotalLineAmount = lineTotal
            ));
        }

        for (Id orderItemId : decompositionPatches.keySet()) {
            OrderItem decompPatch = decompositionPatches.get(orderItemId);
            if (patches.containsKey(orderItemId)) {
                OrderItem patch = patches.get(orderItemId);
                patch.Base_Price__c = decompPatch.Base_Price__c;
                patch.Prior_Partner_Discount__c = decompPatch.Prior_Partner_Discount__c;
                patch.Prior_Discretionary_Discount__c = decompPatch.Prior_Discretionary_Discount__c;
            } else {
                patches.put(orderItemId, decompPatch);
            }
        }

        return patches;
    }

    @TestVisible
    private static Decimal resolveCommercialUnitPrice(QuoteLineItem qli) {
        if (qli == null) {
            return null;
        }
        if (qli.PartnerUnitPrice != null && qli.PartnerUnitPrice > 0) {
            return qli.PartnerUnitPrice;
        }
        if (qli.UnitPrice != null && qli.UnitPrice > 0) {
            return qli.UnitPrice;
        }
        if (qli.NetUnitPrice != null && qli.NetUnitPrice > 0) {
            return qli.NetUnitPrice;
        }
        return null;
    }

    /**
     * @description Copies quote commercial pricing onto order lines before RCA reprice so
     *              PartnerNetPricePosthook can align TotalPrice with quote net during pricing.
     */
    public static Integer seedOrderItemsFromQuote(Id orderId) {
        return seedFromWork(loadWork(orderId));
    }

    @TestVisible
    public static Integer seedFromWork(OrderMaintenanceWork work) {
        if (work == null || !work.isNewBusiness || work.allOrderItems.isEmpty()) {
            return 0;
        }

        List<OrderItem> seeds = new List<OrderItem>();
        for (OrderItem oi : work.allOrderItems) {
            if (oi.QuoteLineItemId == null) {
                continue;
            }

            QuoteLineItem qli = work.qliById.get(oi.QuoteLineItemId);
            if (qli == null) {
                continue;
            }

            OrderItem seed = new OrderItem(Id = oi.Id);
            Boolean changed = false;

            if (qli.PartnerUnitPrice != null && qli.PartnerUnitPrice > 0) {
                seed.PartnerUnitPrice = qli.PartnerUnitPrice;
                changed = true;
            }
            if (qli.NetUnitPrice != null && qli.NetUnitPrice > 0) {
                seed.NetUnitPrice = qli.NetUnitPrice;
                seed.UnitPrice = qli.NetUnitPrice;
                changed = true;
            } else if (qli.UnitPrice != null && qli.UnitPrice > 0) {
                seed.UnitPrice = qli.UnitPrice;
                changed = true;
            }
            if (String.isNotBlank(qli.Fortra_Product_Type__c)) {
                seed.Fortra_Product_Type__c = qli.Fortra_Product_Type__c;
                changed = true;
            }

            if (changed) {
                seeds.add(seed);
            }
        }

        if (seeds.isEmpty()) {
            return 0;
        }
        update seeds;
        return seeds.size();
    }

    /**
     * @description Re-applies derived maintenance decomposition and commercial net prices.
     *              Called after order reprice so RCA Force pricing cannot leave the line total
     *              at the discount-immune maintenance base instead of the quote net.
     */
    public static Integer persistPatches(Id orderId) {
        return persistFromWork(loadWork(orderId));
    }

    @TestVisible
    public static Integer persistFromWork(OrderMaintenanceWork work) {
        Map<Id, OrderItem> patches = buildCommercialPatchesFromWork(work);
        if (patches.isEmpty()) {
            return 0;
        }
        update patches.values();
        return patches.size();
    }

    /**
     * @description Single-transaction reprice helper: load once, seed, return work for persist after reprice.
     */
    @TestVisible
    public static OrderMaintenanceWork prepareForReprice(Id orderId) {
        OrderMaintenanceWork work = loadWork(orderId);
        seedFromWork(work);
        return work;
    }

    @TestVisible
    private static Set<Id> loadDerivedPricebookEntryIds(Set<Id> pbeIds) {
        Set<Id> derivedPbeIds = new Set<Id>();
        if (pbeIds.isEmpty()) {
            return derivedPbeIds;
        }

        for (PriceBookEntryDerivedPrice dp : [
            SELECT PricebookEntryId
            FROM PriceBookEntryDerivedPrice
            WHERE PricebookEntryId IN :pbeIds
        ]) {
            derivedPbeIds.add(dp.PricebookEntryId);
        }
        return derivedPbeIds;
    }

    /**
     * @description QuoteLineItemAttribute.AttributeValue is not reliably filterable in SOQL;
     *              load all attributes for the lines and resolve tier in Apex.
     *              Prefer "Maintenance Type Defn" over other tier-like attributes (e.g. Feature Options).
     */
    @TestVisible
    private static Map<Id, String> loadMaintenanceTierByQliId(Set<Id> qliIds) {
        Map<Id, String> tierByQliId = new Map<Id, String>();
        if (qliIds.isEmpty()) {
            return tierByQliId;
        }

        for (QuoteLineItemAttribute qlia : [
            SELECT QuoteLineItemId, AttributeName, AttributeValue
            FROM QuoteLineItemAttribute
            WHERE QuoteLineItemId IN :qliIds
        ]) {
            String tierValue = normalizeTierValue(qlia.AttributeValue);
            if (tierValue == null) {
                continue;
            }

            if (tierByQliId.containsKey(qlia.QuoteLineItemId)) {
                if (qlia.AttributeName != MAINTENANCE_TIER_ATTRIBUTE) {
                    continue;
                }
            }

            tierByQliId.put(qlia.QuoteLineItemId, tierValue);
        }
        return tierByQliId;
    }

    @TestVisible
    private static String normalizeTierValue(String attributeValue) {
        if (String.isBlank(attributeValue)) {
            return null;
        }

        String normalized = attributeValue.trim();
        if (normalized.equalsIgnoreCase('Premier')) {
            return 'Premier';
        }
        if (normalized.equalsIgnoreCase('Standard')) {
            return 'Standard';
        }
        if (normalized.equalsIgnoreCase('Professional')) {
            return 'Professional';
        }
        return null;
    }

    /**
     * Mirrors Rev Mgmt Default Pricing V9 new-business formula tier mapping.
     */
    @TestVisible
    public static Decimal resolveTierRate(String attributeValue) {
        String tierValue = normalizeTierValue(attributeValue);
        if (tierValue == 'Premier') {
            return 0.30;
        }
        if (tierValue == 'Standard' || tierValue == 'Professional') {
            return 0.20;
        }
        return 0;
    }

    @TestVisible
    public static Decomposition compute(
        Decimal sourceBase,
        Decimal unitPrice,
        Decimal partnerUnitPrice,
        Decimal netUnitPrice,
        String tierAttributeValue
    ) {
        Decomposition result = new Decomposition();
        result.partnerDiscount = 0;
        result.discretionaryDiscount = 0;

        if (sourceBase == null || sourceBase <= 0) {
            return result;
        }

        Decimal tierRate = resolveTierRate(tierAttributeValue);
        result.maintenanceBase = (sourceBase * tierRate).setScale(2, RoundingMode.HALF_UP);

        if (result.maintenanceBase <= 0) {
            return result;
        }

        Decimal netPrice = resolveNetPrice(unitPrice, netUnitPrice, result.maintenanceBase);
        Decimal afterPartnerPrice = partnerUnitPrice != null && partnerUnitPrice > 0
            ? partnerUnitPrice
            : result.maintenanceBase;

        if (afterPartnerPrice < result.maintenanceBase) {
            result.partnerDiscount = (result.maintenanceBase - afterPartnerPrice)
                .setScale(2, RoundingMode.HALF_UP);
        }

        Decimal discretionaryBase = result.partnerDiscount > 0 ? afterPartnerPrice : result.maintenanceBase;
        if (netPrice < discretionaryBase) {
            result.discretionaryDiscount = (discretionaryBase - netPrice)
                .setScale(2, RoundingMode.HALF_UP);
        }

        return result;
    }

    @TestVisible
    private static Decimal resolveNetPrice(Decimal unitPrice, Decimal netUnitPrice, Decimal maintenanceBase) {
        if (unitPrice != null && unitPrice > 0) {
            return unitPrice;
        }
        if (netUnitPrice != null && netUnitPrice > 0) {
            return netUnitPrice;
        }
        return maintenanceBase;
    }
}