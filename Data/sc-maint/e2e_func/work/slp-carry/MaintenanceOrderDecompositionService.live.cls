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
        public Order orderRecord;
        public Map<Id, Places__c> placeById = new Map<Id, Places__c>();
        public List<OrderItem> allOrderItems = new List<OrderItem>();
        public Map<Id, QuoteLineItem> qliById = new Map<Id, QuoteLineItem>();
        public Set<Id> derivedPbeIds = new Set<Id>();
        public Map<Id, String> tierByQliId = new Map<Id, String>();
    }

    /**
     * @description Loads order-line and quote-line context for one or many orders in a single SOQL batch.
     */
    @TestVisible
    public static Map<Id, OrderMaintenanceWork> loadWorkBulk(Set<Id> orderIds) {
        Map<Id, OrderMaintenanceWork> workByOrderId = new Map<Id, OrderMaintenanceWork>();
        if (orderIds == null || orderIds.isEmpty()) {
            return workByOrderId;
        }

        for (Id orderId : orderIds) {
            if (orderId == null) {
                continue;
            }
            OrderMaintenanceWork work = new OrderMaintenanceWork();
            work.orderId = orderId;
            workByOrderId.put(orderId, work);
        }
        if (workByOrderId.isEmpty()) {
            return workByOrderId;
        }

        Set<Id> resolvedOrderIds = workByOrderId.keySet();
        Map<Id, Order> ordersById = new Map<Id, Order>([
            SELECT Id, QuoteId, Quote.QuoteTypeText__c, Quote.Quote_Type__c,
                   BillToContactId, ShipToContactId,
                   Bill_To_Account__c, Ship_To_Account__c,
                   Bill_To_Address__c, Ship_To_Address__c,
                   Quote.BillToContactId, Quote.ContactId,
                   Quote.Bill_To_Place__c, Quote.Ship_To_Place__c
            FROM Order
            WHERE Id IN :resolvedOrderIds
        ]);

        Set<Id> placeIds = new Set<Id>();
        for (Order ord : ordersById.values()) {
            OrderMaintenanceWork work = workByOrderId.get(ord.Id);
            work.orderRecord = ord;
            work.isNewBusiness = isNewBusinessQuote(ord.Quote);
            if (ord.Quote?.Bill_To_Place__c != null) {
                placeIds.add(ord.Quote.Bill_To_Place__c);
            }
            if (ord.Quote?.Ship_To_Place__c != null) {
                placeIds.add(ord.Quote.Ship_To_Place__c);
            }
        }

        Map<Id, Places__c> globalPlaceById = new Map<Id, Places__c>();
        if (!placeIds.isEmpty()) {
            globalPlaceById = new Map<Id, Places__c>([
                SELECT Id, Account__c
                FROM Places__c
                WHERE Id IN :placeIds
            ]);
        }
        for (Order ord : ordersById.values()) {
            workByOrderId.get(ord.Id).placeById = buildPlaceByIdForOrder(ord, globalPlaceById);
        }

        Map<Id, List<OrderItem>> orderItemsByOrderId = new Map<Id, List<OrderItem>>();
        Set<Id> qliIds = new Set<Id>();
        Set<Id> pbeIds = new Set<Id>();
        for (OrderItem oi : [
            SELECT Id, OrderId, QuoteLineItemId, PricebookEntryId, Quantity,
                   Hardware__c, Hardware_ID__c, Partition_Record__c, Ship_To_Address__c,
                   Source_List_Price__c
            FROM OrderItem
            WHERE OrderId IN :resolvedOrderIds
        ]) {
            if (!orderItemsByOrderId.containsKey(oi.OrderId)) {
                orderItemsByOrderId.put(oi.OrderId, new List<OrderItem>());
            }
            orderItemsByOrderId.get(oi.OrderId).add(oi);
            if (oi.QuoteLineItemId != null) {
                qliIds.add(oi.QuoteLineItemId);
            }
            if (oi.PricebookEntryId != null) {
                pbeIds.add(oi.PricebookEntryId);
            }
        }

        Map<Id, QuoteLineItem> qliById = new Map<Id, QuoteLineItem>();
        if (!qliIds.isEmpty()) {
            qliById = new Map<Id, QuoteLineItem>([
                SELECT Id, Base_Price__c, UnitPrice, NetUnitPrice, PartnerUnitPrice,
                       Fortra_Product_Type__c, Product2.Fortra_Product_Type__c, PricebookEntryId,
                       Source_List_Price__c,
                       Prior_Partner_Discount__c, Prior_Discretionary_Discount__c,
                       COLACalculatedPrice__c, COLA_Uplift_Percent__c,
                       Hardware__c, Hardware_ID__c, Partition_Reference__c,
                       Quote.Ship_To_Place__c
                FROM QuoteLineItem
                WHERE Id IN :qliIds
            ]);
        }

        Set<Id> derivedPbeIds = loadDerivedPricebookEntryIds(pbeIds);

        Set<Id> newBusinessQliIds = new Set<Id>();
        for (Id orderId : resolvedOrderIds) {
            OrderMaintenanceWork work = workByOrderId.get(orderId);
            if (!work.isNewBusiness || !orderItemsByOrderId.containsKey(orderId)) {
                continue;
            }
            for (OrderItem oi : orderItemsByOrderId.get(orderId)) {
                if (oi.QuoteLineItemId != null) {
                    newBusinessQliIds.add(oi.QuoteLineItemId);
                }
            }
        }
        Map<Id, String> tierByQliId = loadMaintenanceTierByQliId(newBusinessQliIds);

        for (Id orderId : resolvedOrderIds) {
            OrderMaintenanceWork work = workByOrderId.get(orderId);
            work.allOrderItems = orderItemsByOrderId.containsKey(orderId)
                ? orderItemsByOrderId.get(orderId)
                : new List<OrderItem>();
            work.derivedPbeIds = derivedPbeIds;

            for (OrderItem oi : work.allOrderItems) {
                if (oi.QuoteLineItemId != null && qliById.containsKey(oi.QuoteLineItemId)) {
                    work.qliById.put(oi.QuoteLineItemId, qliById.get(oi.QuoteLineItemId));
                }
            }
            if (work.isNewBusiness) {
                for (Id qliId : work.qliById.keySet()) {
                    if (tierByQliId.containsKey(qliId)) {
                        work.tierByQliId.put(qliId, tierByQliId.get(qliId));
                    }
                }
            }
        }

        return workByOrderId;
    }

    /**
     * @description Copies Bill To / Ship To header fields from the source Quote onto the Order.
     *              Uses header data already loaded on OrderMaintenanceWork (no extra SOQL).
     */
    @TestVisible
    public static Boolean applyOrderHeaderFromWork(OrderMaintenanceWork work) {
        if (work == null || work.orderRecord == null || work.orderRecord.QuoteId == null) {
            return false;
        }

        Order ord = work.orderRecord;
        Quote sourceQuote = ord.Quote;
        if (sourceQuote == null) {
            return false;
        }

        Order patch = new Order(Id = ord.Id);
        Boolean changed = false;

        if (sourceQuote.Bill_To_Place__c != null) {
            Places__c billPlace = work.placeById.get(sourceQuote.Bill_To_Place__c);
            if (billPlace != null && billPlace.Account__c != null && ord.Bill_To_Account__c != billPlace.Account__c) {
                patch.Bill_To_Account__c = billPlace.Account__c;
                changed = true;
            }
            if (ord.Bill_To_Address__c != sourceQuote.Bill_To_Place__c) {
                patch.Bill_To_Address__c = sourceQuote.Bill_To_Place__c;
                changed = true;
            }
        }

        if (sourceQuote.Ship_To_Place__c != null) {
            Places__c shipPlace = work.placeById.get(sourceQuote.Ship_To_Place__c);
            if (shipPlace != null && shipPlace.Account__c != null && ord.Ship_To_Account__c != shipPlace.Account__c) {
                patch.Ship_To_Account__c = shipPlace.Account__c;
                changed = true;
            }
            if (ord.Ship_To_Address__c != sourceQuote.Ship_To_Place__c) {
                patch.Ship_To_Address__c = sourceQuote.Ship_To_Place__c;
                changed = true;
            }
        }

        if (sourceQuote.BillToContactId != null && ord.BillToContactId != sourceQuote.BillToContactId) {
            patch.BillToContactId = sourceQuote.BillToContactId;
            changed = true;
        }

        if (sourceQuote.ContactId != null && ord.ShipToContactId != sourceQuote.ContactId) {
            patch.ShipToContactId = sourceQuote.ContactId;
            changed = true;
        }

        if (!changed) {
            return false;
        }

        update patch;
        return true;
    }

    @TestVisible
    private static Map<Id, Places__c> buildPlaceByIdForOrder(Order ord, Map<Id, Places__c> globalPlaceById) {
        Map<Id, Places__c> placeById = new Map<Id, Places__c>();
        if (ord.Quote?.Bill_To_Place__c != null && globalPlaceById.containsKey(ord.Quote.Bill_To_Place__c)) {
            placeById.put(ord.Quote.Bill_To_Place__c, globalPlaceById.get(ord.Quote.Bill_To_Place__c));
        }
        if (ord.Quote?.Ship_To_Place__c != null && globalPlaceById.containsKey(ord.Quote.Ship_To_Place__c)) {
            placeById.put(ord.Quote.Ship_To_Place__c, globalPlaceById.get(ord.Quote.Ship_To_Place__c));
        }
        return placeById;
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

        Map<Id, OrderMaintenanceWork> workByOrderId = loadWorkBulk(new Set<Id>{ orderId });
        return workByOrderId.containsKey(orderId) ? workByOrderId.get(orderId) : work;
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
            if (!isDerivedMaintenanceLine(work, qli, oi)) {
                continue;
            }

            Decomposition decomp = compute(
                qli.Base_Price__c,
                qli.UnitPrice,
                qli.PartnerUnitPrice,
                qli.NetUnitPrice,
                resolveTierForLine(work, qli)
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
     * @description Persists renewal carry-forward pricing inputs from QuoteLineItem onto OrderItem
     *              at quote-to-order conversion. The stamp flow writes these onto QLI before save;
     *              standard createOrderFromQuote does not map custom carry-forward fields.
     */
    @TestVisible
    public static Map<Id, OrderItem> buildRenewalCarryForwardPatchesFromWork(OrderMaintenanceWork work) {
        Map<Id, OrderItem> patches = new Map<Id, OrderItem>();

        if (work == null || work.isNewBusiness || work.allOrderItems.isEmpty()) {
            return patches;
        }

        for (OrderItem oi : work.allOrderItems) {
            if (oi.QuoteLineItemId == null) {
                continue;
            }

            QuoteLineItem qli = work.qliById.get(oi.QuoteLineItemId);
            if (qli == null || qli.Base_Price__c == null || qli.Base_Price__c <= 0) {
                continue;
            }
            if (!isDerivedMaintenanceLine(work, qli, oi)) {
                continue;
            }

            Decimal commercialNet = resolveRenewalCommercialUnitPrice(qli);
            if (commercialNet == null || commercialNet <= 0) {
                continue;
            }

            Decimal quantity = oi.Quantity != null && oi.Quantity > 0 ? oi.Quantity : 1;
            Decimal partnerUnit = qli.PartnerUnitPrice != null && qli.PartnerUnitPrice > 0
                ? qli.PartnerUnitPrice
                : commercialNet;

            patches.put(oi.Id, new OrderItem(
                Id = oi.Id,
                Base_Price__c = qli.Base_Price__c,
                Prior_Partner_Discount__c = qli.Prior_Partner_Discount__c,
                Prior_Discretionary_Discount__c = qli.Prior_Discretionary_Discount__c,
                UnitPrice = commercialNet,
                NetUnitPrice = commercialNet,
                PartnerUnitPrice = partnerUnit,
                TotalLineAmount = (commercialNet * quantity).setScale(2, RoundingMode.HALF_UP)
            ));
        }

        return patches;
    }

    @TestVisible
    private static Boolean isNewBusinessQuote(Quote sourceQuote) {
        if (sourceQuote == null) {
            return false;
        }
        return isNewBusinessQuoteType(sourceQuote.QuoteTypeText__c)
            || isNewBusinessQuoteType(sourceQuote.Quote_Type__c);
    }

    @TestVisible
    private static Boolean isNewBusinessQuoteType(String quoteType) {
        return String.isNotBlank(quoteType) && NEW_BUSINESS_QUOTE_TYPES.contains(quoteType.trim());
    }

    @TestVisible
    private static Boolean isMaintenanceProductType(String productType) {
        return productType == 'New Maintenance' || productType == 'Renewal Maintenance';
    }

    /**
     * @description Resolves maintenance tier from stamped QLI attributes, inferring from pricing
     *              when attributes are absent so decomposition still overwrites license base.
     */
    @TestVisible
    private static String resolveTierForLine(OrderMaintenanceWork work, QuoteLineItem qli) {
        if (work != null && work.tierByQliId.containsKey(qli.Id)) {
            return work.tierByQliId.get(qli.Id);
        }
        String inferred = inferTierFromPricing(
            qli.Base_Price__c,
            qli.UnitPrice,
            qli.PartnerUnitPrice,
            qli.NetUnitPrice
        );
        return inferred != null ? inferred : 'Standard';
    }

    /**
     * @description Picks the tier whose maintenance base best fits stamped partner/commercial net.
     *              Prefers the smallest valid maintenance base >= partner unit price.
     */
    @TestVisible
    public static String inferTierFromPricing(
        Decimal sourceBase,
        Decimal unitPrice,
        Decimal partnerUnitPrice,
        Decimal netUnitPrice
    ) {
        if (sourceBase == null || sourceBase <= 0) {
            return null;
        }

        String bestTier = null;
        Decimal bestMaintenanceBase = null;
        for (String tier : new List<String>{ 'Standard', 'Professional', 'Premier' }) {
            Decomposition candidate = compute(
                sourceBase,
                unitPrice,
                partnerUnitPrice,
                netUnitPrice,
                tier
            );
            if (candidate.maintenanceBase == null || candidate.maintenanceBase <= 0) {
                continue;
            }
            if (partnerUnitPrice != null && partnerUnitPrice > 0
                && candidate.maintenanceBase < partnerUnitPrice) {
                continue;
            }

            if (bestMaintenanceBase == null || candidate.maintenanceBase < bestMaintenanceBase) {
                bestMaintenanceBase = candidate.maintenanceBase;
                bestTier = tier;
            }
        }
        return bestTier;
    }

    @TestVisible
    private static Boolean isDerivedMaintenanceLine(
        OrderMaintenanceWork work,
        QuoteLineItem qli,
        OrderItem oi
    ) {
        Id pbeId = qli.PricebookEntryId != null ? qli.PricebookEntryId : oi.PricebookEntryId;
        if (pbeId != null && work.derivedPbeIds != null && work.derivedPbeIds.contains(pbeId)) {
            return true;
        }

        if (isMaintenanceProductType(qli.Fortra_Product_Type__c)) {
            return true;
        }
        return isMaintenanceProductType(qli.Product2?.Fortra_Product_Type__c);
    }

    @TestVisible
    private static Decimal resolveRenewalCommercialUnitPrice(QuoteLineItem qli) {
        Decimal fromQuote = resolveCommercialUnitPrice(qli);
        if (fromQuote != null && fromQuote > 0) {
            return fromQuote;
        }
        if (qli.COLACalculatedPrice__c != null && qli.COLACalculatedPrice__c > 0) {
            return qli.COLACalculatedPrice__c;
        }
        if (qli.Base_Price__c == null || qli.Base_Price__c <= 0) {
            return null;
        }

        Decimal priorPartner = qli.Prior_Partner_Discount__c != null ? qli.Prior_Partner_Discount__c : 0;
        Decimal priorDisc = qli.Prior_Discretionary_Discount__c != null ? qli.Prior_Discretionary_Discount__c : 0;
        Decimal colaPct = qli.COLA_Uplift_Percent__c != null ? qli.COLA_Uplift_Percent__c : 0;
        return ((qli.Base_Price__c - priorPartner - priorDisc) * (1 + (colaPct / 100)))
            .setScale(2, RoundingMode.HALF_UP);
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
     * @description Re-applies Base / Prior Partner$ / Prior Disc$ without touching UnitPrice.
     *              Use for backfill on activated orders that have Order Product Detail records.
     */
    public static Integer backfillCarryForwardFields(Id orderId) {
        Map<Id, Integer> counts = backfillCarryForwardFieldsBulk(new Set<Id>{ orderId });
        return counts.containsKey(orderId) ? counts.get(orderId) : 0;
    }

    public static Map<Id, Integer> backfillCarryForwardFieldsBulk(Set<Id> orderIds) {
        Map<Id, Integer> countsByOrderId = new Map<Id, Integer>();
        if (orderIds == null || orderIds.isEmpty()) {
            return countsByOrderId;
        }

        Map<Id, OrderMaintenanceWork> workByOrderId = loadWorkBulk(orderIds);
        for (Id orderId : orderIds) {
            if (orderId == null) {
                continue;
            }
            OrderMaintenanceWork work = workByOrderId.get(orderId);
            Map<Id, OrderItem> patches = buildCarryForwardFieldPatchesFromWork(work);
            if (patches.isEmpty()) {
                countsByOrderId.put(orderId, 0);
                continue;
            }
            update patches.values();
            countsByOrderId.put(orderId, patches.size());
        }
        return countsByOrderId;
    }

    @TestVisible
    public static Map<Id, OrderItem> buildCarryForwardFieldPatchesFromWork(OrderMaintenanceWork work) {
        Map<Id, OrderItem> patches = new Map<Id, OrderItem>();
        mergeCarryForwardOnlyPatches(patches, buildPatchesFromWork(work));
        mergeCarryForwardOnlyPatches(patches, buildRenewalCarryForwardPatchesFromWork(work));
        return patches;
    }

    @TestVisible
    private static void mergeCarryForwardOnlyPatches(
        Map<Id, OrderItem> target,
        Map<Id, OrderItem> additional
    ) {
        for (Id orderItemId : additional.keySet()) {
            OrderItem extra = additional.get(orderItemId);
            OrderItem patch = target.containsKey(orderItemId)
                ? target.get(orderItemId)
                : new OrderItem(Id = orderItemId);

            if (extra.Base_Price__c != null) {
                patch.Base_Price__c = extra.Base_Price__c;
            }
            if (extra.Prior_Partner_Discount__c != null) {
                patch.Prior_Partner_Discount__c = extra.Prior_Partner_Discount__c;
            }
            if (extra.Prior_Discretionary_Discount__c != null) {
                patch.Prior_Discretionary_Discount__c = extra.Prior_Discretionary_Discount__c;
            }
            target.put(orderItemId, patch);
        }
    }

    public class BackfillRequest {
        @InvocableVariable(required=true label='Order ID')
        public Id orderId;
    }

    public class BackfillResult {
        @InvocableVariable(label='Order ID')
        public Id orderId;

        @InvocableVariable(label='Items Updated')
        public Integer itemsUpdated;
    }

    @InvocableMethod(
        label='Backfill OrderItem Carry-Forward Fields'
        description='Re-applies maintenance Base / Prior Partner$ / Prior Disc$ on existing orders without changing UnitPrice'
        category='Order Management'
    )
    public static List<BackfillResult> backfillCarryForwardInvocable(List<BackfillRequest> requests) {
        List<BackfillResult> results = new List<BackfillResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        Set<Id> orderIds = new Set<Id>();
        for (BackfillRequest request : requests) {
            if (request != null && request.orderId != null) {
                orderIds.add(request.orderId);
            }
        }
        Map<Id, Integer> countsByOrderId = backfillCarryForwardFieldsBulk(orderIds);

        for (BackfillRequest request : requests) {
            BackfillResult result = new BackfillResult();
            if (request != null) {
                result.orderId = request.orderId;
                result.itemsUpdated = request.orderId != null
                    ? countsByOrderId.get(request.orderId)
                    : 0;
            }
            if (result.itemsUpdated == null) {
                result.itemsUpdated = 0;
            }
            results.add(result);
        }
        return results;
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
