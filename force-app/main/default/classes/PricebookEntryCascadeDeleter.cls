public with sharing class PricebookEntryCascadeDeleter {

    public class Input {
        @InvocableVariable(required=true label='PricebookEntry Id')
        public Id pricebookEntryId;
    }

    public class Output {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Message')
        public String message;
        @InvocableVariable(label='Product Name')
        public String productName;
        @InvocableVariable(label='Assets Deleted')
        public Integer assetsDeleted;
    }

    @InvocableMethod(label='Cascade Delete Pricebook Entry' description='Deletes a PricebookEntry and all dependent records (OpportunityLineItem, AssetActionSource, AssetAction, Asset and Asset children)')
    public static List<Output> cascadeDelete(List<Input> inputs) {
        List<Output> results = new List<Output>();
        for (Input inp : inputs) {
            results.add(runOne(inp.pricebookEntryId));
        }
        return results;
    }

    private static Output runOne(Id pbeId) {
        Output out = new Output();
        out.assetsDeleted = 0;
        Savepoint sp = Database.setSavepoint();
        try {
            List<PricebookEntry> pbes = [SELECT Id, Product2.Name, IsActive FROM PricebookEntry WHERE Id = :pbeId LIMIT 1];
            if (pbes.isEmpty()) {
                out.success = false;
                out.message = 'PricebookEntry not found: ' + pbeId;
                return out;
            }
            PricebookEntry pbe = pbes[0];
            out.productName = pbe.Product2 != null ? pbe.Product2.Name : null;

            List<OpportunityLineItem> olis = [SELECT Id FROM OpportunityLineItem WHERE PricebookEntryId = :pbeId];
            if (!olis.isEmpty()) Database.delete(olis, false);

            Set<Id> assetIds = new Set<Id>();
            Set<Id> assetActionIds = new Set<Id>();
            for (AssetActionSource aas : [SELECT Id, AssetActionId, AssetAction.AssetId FROM AssetActionSource WHERE PricebookEntryId = :pbeId]) {
                if (aas.AssetActionId != null) assetActionIds.add(aas.AssetActionId);
                if (aas.AssetAction != null && aas.AssetAction.AssetId != null) assetIds.add(aas.AssetAction.AssetId);
            }

            List<AssetActionSource> aasOnPbe = [SELECT Id FROM AssetActionSource WHERE PricebookEntryId = :pbeId];
            if (!aasOnPbe.isEmpty()) Database.delete(aasOnPbe, false);

            if (!assetIds.isEmpty()) {
                List<AssetActionSource> otherAas = [SELECT Id FROM AssetActionSource WHERE AssetActionId IN :assetActionIds];
                if (!otherAas.isEmpty()) Database.delete(otherAas, false);

                List<AssetAction> assetActions = [SELECT Id FROM AssetAction WHERE AssetId IN :assetIds];
                if (!assetActions.isEmpty()) Database.delete(assetActions, false);

                List<AssetStatePeriod> asps = [SELECT Id FROM AssetStatePeriod WHERE AssetId IN :assetIds];
                if (!asps.isEmpty()) Database.delete(asps, false);

                List<AssetRelationship> rels = [SELECT Id FROM AssetRelationship WHERE AssetId IN :assetIds OR RelatedAssetId IN :assetIds];
                if (!rels.isEmpty()) Database.delete(rels, false);

                List<AssetContractRelationship> acrs = [SELECT Id FROM AssetContractRelationship WHERE AssetId IN :assetIds];
                if (!acrs.isEmpty()) Database.delete(acrs, false);

                List<AssetFulfillmentDecomp> afds = [SELECT Id FROM AssetFulfillmentDecomp WHERE FulfillmentSourceAssetId IN :assetIds OR FulfillmentTargetAssetId IN :assetIds];
                if (!afds.isEmpty()) Database.delete(afds, false);

                List<AppUsageAssignment> auas = [SELECT Id FROM AppUsageAssignment WHERE RecordId IN :assetIds];
                if (!auas.isEmpty()) Database.delete(auas, false);

                List<Asset> assets = [SELECT Id FROM Asset WHERE Id IN :assetIds];
                if (!assets.isEmpty()) {
                    Database.DeleteResult[] dres = Database.delete(assets, false);
                    Integer ok = 0;
                    for (Database.DeleteResult dr : dres) if (dr.isSuccess()) ok++;
                    out.assetsDeleted = ok;
                }
            }

            if (pbe.IsActive) {
                pbe.IsActive = false;
                update pbe;
            }
            delete pbe;

            out.success = true;
            out.message = 'PBE deleted (' + out.assetsDeleted + ' assets removed)';
        } catch (Exception e) {
            Database.rollback(sp);
            out.success = false;
            out.message = e.getTypeName() + ': ' + e.getMessage();
        }
        return out;
    }
}