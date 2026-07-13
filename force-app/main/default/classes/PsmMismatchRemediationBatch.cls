/**
 * @description One-time remediation: align ProductSellingModelOption and Fortra
 *              PricebookEntry records with All Fortra Product Mapping spreadsheet
 *              for PSM_MISMATCH products.
 */
public class PsmMismatchRemediationBatch implements Database.Batchable<String>, Database.Stateful {

    private static final Id FORTRA_PB_ID = '01sWC0000022GHFYA2';
    private static final Id ONE_TIME_PSM_ID = '0jPWC00000005yz2AA';
    private static final Id TERM_ANNUAL_PSM_ID = '0jPWC000000060b2AA';

    public Integer psmoCreated = 0;
    public Integer psmoUpdated = 0;
    public Integer stdPbeCreated = 0;
    public Integer fortraPbeCreated = 0;
    public Integer productsSkipped = 0;
    public List<String> errors = new List<String>();

    private Id standardPricebookId;
    private Map<String, Id> productIdByCode = new Map<String, Id>();
    private Map<String, String> targetModelByCode = buildTargetModelByCode();

    public Iterable<String> start(Database.BatchableContext ctx) {
        List<Pricebook2> stdPbs = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
        standardPricebookId = stdPbs.isEmpty() ? null : stdPbs[0].Id;

        Set<String> codes = targetModelByCode.keySet();
        for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode IN :codes]) {
            productIdByCode.put(p.ProductCode.toUpperCase(), p.Id);
        }
        return new List<String>(codes);
    }

    public void execute(Database.BatchableContext ctx, List<String> scope) {
        if (standardPricebookId == null) {
            errors.add('Standard Pricebook not found');
            return;
        }

        Set<Id> productIds = new Set<Id>();
        for (String code : scope) {
            Id productId = productIdByCode.get(code.toUpperCase());
            if (productId == null) {
                productsSkipped++;
                errors.add('Product not found: ' + code);
                continue;
            }
            productIds.add(productId);
        }
        if (productIds.isEmpty()) {
            return;
        }

        Map<Id, Id> targetPsmByProduct = new Map<Id, Id>();
        for (String code : scope) {
            Id productId = productIdByCode.get(code.toUpperCase());
            if (productId == null) {
                continue;
            }
            targetPsmByProduct.put(productId, resolveTargetPsmId(code, targetModelByCode.get(code.toUpperCase())));
        }

        Map<String, ProductSellingModelOption> psmoByKey = new Map<String, ProductSellingModelOption>();
        for (ProductSellingModelOption psmo : [
            SELECT Id, Product2Id, ProductSellingModelId, IsDefault
            FROM ProductSellingModelOption
            WHERE Product2Id IN :productIds
        ]) {
            psmoByKey.put(psmo.Product2Id + '|' + psmo.ProductSellingModelId, psmo);
        }

        List<ProductSellingModelOption> psmoToInsert = new List<ProductSellingModelOption>();
        List<ProductSellingModelOption> psmoToUpdate = new List<ProductSellingModelOption>();
        Set<Id> psmoUpdateIds = new Set<Id>();

        for (Id productId : targetPsmByProduct.keySet()) {
            Id targetPsmId = targetPsmByProduct.get(productId);
            String targetKey = productId + '|' + targetPsmId;
            if (!psmoByKey.containsKey(targetKey)) {
                psmoToInsert.add(new ProductSellingModelOption(
                    Product2Id = productId,
                    ProductSellingModelId = targetPsmId,
                    IsDefault = true
                ));
            }
            for (ProductSellingModelOption psmo : psmoByKey.values()) {
                if (psmo.Product2Id != productId || psmoUpdateIds.contains(psmo.Id)) {
                    continue;
                }
                Boolean shouldBeDefault = psmo.ProductSellingModelId == targetPsmId;
                if (psmo.IsDefault != shouldBeDefault) {
                    psmo.IsDefault = shouldBeDefault;
                    psmoToUpdate.add(psmo);
                    psmoUpdateIds.add(psmo.Id);
                }
            }
        }

        if (!psmoToInsert.isEmpty()) {
            Database.SaveResult[] insertResults = Database.insert(psmoToInsert, false);
            for (Integer i = 0; i < insertResults.size(); i++) {
                if (insertResults[i].isSuccess()) {
                    psmoCreated++;
                    ProductSellingModelOption inserted = psmoToInsert[i];
                    psmoByKey.put(inserted.Product2Id + '|' + inserted.ProductSellingModelId, inserted);
                } else {
                    errors.add(describeErrors('PSMO insert', insertResults[i]));
                }
            }
        }
        if (!psmoToUpdate.isEmpty()) {
            Database.SaveResult[] updateResults = Database.update(psmoToUpdate, false);
            for (Database.SaveResult sr : updateResults) {
                if (sr.isSuccess()) {
                    psmoUpdated++;
                } else {
                    errors.add(describeErrors('PSMO update', sr));
                }
            }
        }

        Map<String, Decimal> seedPriceByProductCurrency = new Map<String, Decimal>();
        for (PricebookEntry pbe : [
            SELECT Product2Id, CurrencyIsoCode, UnitPrice
            FROM PricebookEntry
            WHERE Product2Id IN :productIds
              AND Pricebook2Id = :FORTRA_PB_ID
              AND IsActive = true
        ]) {
            String key = pbe.Product2Id + '|' + pbe.CurrencyIsoCode;
            if (!seedPriceByProductCurrency.containsKey(key)) {
                seedPriceByProductCurrency.put(key, pbe.UnitPrice);
            }
        }

        Set<String> existingStdKeys = new Set<String>();
        for (PricebookEntry pbe : [
            SELECT Product2Id, CurrencyIsoCode, ProductSellingModelId
            FROM PricebookEntry
            WHERE Product2Id IN :productIds
              AND Pricebook2Id = :standardPricebookId
              AND IsActive = true
        ]) {
            existingStdKeys.add(
                pbe.Product2Id + '|' + pbe.CurrencyIsoCode + '|' + pbe.ProductSellingModelId
            );
        }

        Set<String> existingFortraKeys = new Set<String>();
        for (PricebookEntry pbe : [
            SELECT Product2Id, CurrencyIsoCode, ProductSellingModelId
            FROM PricebookEntry
            WHERE Product2Id IN :productIds
              AND Pricebook2Id = :FORTRA_PB_ID
              AND IsActive = true
        ]) {
            existingFortraKeys.add(
                pbe.Product2Id + '|' + pbe.CurrencyIsoCode + '|' + pbe.ProductSellingModelId
            );
        }

        List<PricebookEntry> stdToInsert = new List<PricebookEntry>();
        List<PricebookEntry> fortraToInsert = new List<PricebookEntry>();

        for (Id productId : targetPsmByProduct.keySet()) {
            Id targetPsmId = targetPsmByProduct.get(productId);
            Set<String> currencies = new Set<String>();
            String productPrefix = String.valueOf(productId) + '|';
            for (String seedKey : seedPriceByProductCurrency.keySet()) {
                if (seedKey.startsWith(productPrefix)) {
                    currencies.add(seedKey.substring(productPrefix.length()));
                }
            }
            if (currencies.isEmpty()) {
                currencies.add('USD');
            }

            for (String currencyCode : currencies) {
                Decimal unitPrice = seedPriceByProductCurrency.get(productId + '|' + currencyCode);
                if (unitPrice == null) {
                    unitPrice = 0;
                }

                String stdKey = productId + '|' + currencyCode + '|' + targetPsmId;
                if (!existingStdKeys.contains(stdKey)) {
                    PricebookEntry stdPbe = new PricebookEntry(
                        Product2Id = productId,
                        Pricebook2Id = standardPricebookId,
                        CurrencyIsoCode = currencyCode,
                        UnitPrice = unitPrice,
                        IsActive = true,
                        ProductSellingModelId = targetPsmId
                    );
                    stdToInsert.add(stdPbe);
                    existingStdKeys.add(stdKey);
                }

                String fortraKey = productId + '|' + currencyCode + '|' + targetPsmId;
                if (!existingFortraKeys.contains(fortraKey)) {
                    fortraToInsert.add(new PricebookEntry(
                        Product2Id = productId,
                        Pricebook2Id = FORTRA_PB_ID,
                        CurrencyIsoCode = currencyCode,
                        UnitPrice = unitPrice,
                        IsActive = true,
                        ProductSellingModelId = targetPsmId
                    ));
                    existingFortraKeys.add(fortraKey);
                }
            }
        }

        if (!stdToInsert.isEmpty()) {
            Database.SaveResult[] stdResults = Database.insert(stdToInsert, false);
            for (Integer i = 0; i < stdResults.size(); i++) {
                if (stdResults[i].isSuccess()) {
                    stdPbeCreated++;
                } else {
                    errors.add(describeErrors('Standard PBE insert', stdResults[i]));
                }
            }
        }

        if (!fortraToInsert.isEmpty()) {
            Database.SaveResult[] fortraResults = Database.insert(fortraToInsert, false);
            for (Integer i = 0; i < fortraResults.size(); i++) {
                if (fortraResults[i].isSuccess()) {
                    fortraPbeCreated++;
                } else {
                    errors.add(describeErrors('Fortra PBE insert', fortraResults[i]));
                }
            }
        }
    }

    public void finish(Database.BatchableContext ctx) {
        System.debug(LoggingLevel.INFO, 'PsmMismatchRemediationBatch complete');
        System.debug(LoggingLevel.INFO, 'PSMO created: ' + psmoCreated);
        System.debug(LoggingLevel.INFO, 'PSMO updated: ' + psmoUpdated);
        System.debug(LoggingLevel.INFO, 'Standard PBE created: ' + stdPbeCreated);
        System.debug(LoggingLevel.INFO, 'Fortra PBE created: ' + fortraPbeCreated);
        System.debug(LoggingLevel.INFO, 'Products skipped: ' + productsSkipped);
        System.debug(LoggingLevel.INFO, 'Errors: ' + errors.size());
        for (String err : errors) {
            System.debug(LoggingLevel.WARN, err);
        }
    }

    private static Id resolveTargetPsmId(String productCode, String spreadsheetModel) {
        String normalized = normalizeSpreadsheetModel(spreadsheetModel);
        if (normalized == 'one time') {
            return ONE_TIME_PSM_ID;
        }
        if (normalized == 'term based - annual') {
            return TERM_ANNUAL_PSM_ID;
        }
        String code = productCode == null ? '' : productCode.toUpperCase();
        if (code.contains('-RRM-') || code.contains('-RSS-') || code.contains('-RMS-') || code.contains('-RSP-')) {
            return TERM_ANNUAL_PSM_ID;
        }
        return ONE_TIME_PSM_ID;
    }

    private static String normalizeSpreadsheetModel(String spreadsheetModel) {
        String normalized = spreadsheetModel == null ? '' : spreadsheetModel.trim().toLowerCase();
        normalized = normalized.replace('one-time', 'one time');
        normalized = normalized.replace('term based - renew', 'term based - annual');
        return normalized;
    }

    private static String describeErrors(String context, Database.SaveResult sr) {
        List<String> parts = new List<String>();
        for (Database.Error err : sr.getErrors()) {
            parts.add(err.getStatusCode() + ': ' + err.getMessage());
        }
        return context + ' failed: ' + String.join(parts, '; ');
    }

    private static Map<String, String> buildTargetModelByCode() {
        Map<String, String> mapping = new Map<String, String>();
        for (String line : REMEDIATION_LINES.split('\n')) {
            line = line.trim();
            if (line == '') {
                continue;
            }
            List<String> parts = line.split('\t');
            if (parts.isEmpty()) {
                continue;
            }
            String code = parts[0].trim().toUpperCase();
            String model = parts.size() > 1 ? parts[1].trim() : '';
            mapping.put(code, model);
        }
        return mapping;
    }

    // ProductCode TAB SpreadsheetSellingModel (from fortra_mapping_comparison_uat.csv PSM_MISMATCH)
    private static final String REMEDIATION_LINES =
        'BI-ISA-RRM-IACRM\tTerm Based - Renew\n' +
        'BI-ISA-RRM-IAPRMRM\tTerm Based - Renew\n' +
        'BI-ISA-RRM-IAPROM\tTerm Based - Renew\n' +
        'BI-ISA-RRM-IASPRM\tTerm Based - Renew\n' +
        'BI-SDW-RRM-SDWBBERM\tTerm Based - Renew\n' +
        'BI-SDW-RRM-SDWBGERM\tTerm Based - Renew\n' +
        'BI-SDW-RRM-SDWBPERM\tTerm Based - Renew\n' +
        'BI-SDW-RRM-SDWBSERM\tTerm Based - Renew\n' +
        'BI-SDW-RRM-SDWSBERM\tTerm Based - Renew\n' +
        'BI-SDW-RRM-SDWSGERM\tTerm Based - Renew\n' +
        'BI-SDW-RRM-SDWSPERM\tTerm Based - Renew\n' +
        'BI-SDW-RRM-SDWSSERM\tTerm Based - Renew\n' +
        'BI-SQ-RRM-SSBPRM\tTerm Based - Renew\n' +
        'BI-SQ-RRM-SSBSRM\tTerm Based - Renew\n' +
        'BP-ETM-RMS-ADDITH\tTerm Based - Renew\n' +
        'CM-VCM-RRM-VSPRM\tTerm Based - Renew\n' +
        'DP-DC-RRM-CDMEBRM\tTerm Based - Renew\n' +
        'DP-DC-RRM-COUMCBRM\tTerm Based - Renew\n' +
        'DP-DC-RRM-DCDARGRM\tTerm Based - Renew\n' +
        'DP-DC-RRM-FDAUPGRM\tTerm Based - Renew\n' +
        'DP-DC-RRM-FDPUPGRM\tTerm Based - Renew\n' +
        'DP-DC-RRM-MCCDBERM\tTerm Based - Renew\n' +
        'DP-DC-RRM-MCCDBSRM\tTerm Based - Renew\n' +
        'DP-DC-RRM-TCSIICRM\tTerm Based - Renew\n' +
        'DP-DC-RSP-DCS\tOne-Time\n' +
        'DP-DLP-NRST-PSHPOP\tOne-Time\n' +
        'DP-DLP-RMS-DNAS\tTerm Based - Renew\n' +
        'ES-DMP-NRST-ONBOAR\tOne-Time\n' +
        'ES-SEG-RSP-ESRS\tOne-Time\n' +
        'FIM-FIM-NRPS-VEMEEP\t\n' +
        'FIM-FIM-RNM-TACWIN\tTerm Based - Renew\n' +
        'FIM-FIM-RRM-CCMEVRM\tTerm Based - Renew\n' +
        'FIM-FIM-RRM-CSEERM\tTerm Based - Renew\n' +
        'FIM-FIM-RRM-DEERM\tTerm Based - Renew\n' +
        'FIM-FIM-RRM-FERM\tTerm Based - Renew\n' +
        'FIM-FIM-RRM-IERM\tTerm Based - Renew\n' +
        'FIM-FIM-RRM-TECMBERM\tTerm Based - Renew\n' +
        'FIM-FIM-RRM-TEDERM\tTerm Based - Renew\n' +
        'FIM-FIM-RRM-TEDEVRM\tTerm Based - Renew\n' +
        'FIM-FIM-RRM-TEDSERM\tTerm Based - Renew\n' +
        'FIM-FIM-RRM-TEFSERM\tTerm Based - Renew\n' +
        'FIM-FIM-RRM-TENDERM\tTerm Based - Renew\n' +
        'FIM-FIM-RRM-TETRM\tTerm Based - Renew\n' +
        'FIM-FIM-RRM-TEVEERM\tTerm Based - Renew\n' +
        'FIM-FIM-RRM-TIVSSRM\tTerm Based - Renew\n' +
        'FIM-FIM-RRM-TMERM\tTerm Based - Renew\n' +
        'FIM-FIM-RRM-TSAEVRM\tTerm Based - Renew\n' +
        'FIM-FIM-RRM-TSERM\tTerm Based - Renew\n' +
        'FIM-FIM-RRM-TTBELRM\tTerm Based - Renew\n' +
        'FIM-FIM-RRM-VEMEER\t\n' +
        'FIM-FIM-RSP-TECHNI\tTerm Based - Renew\n' +
        'FIM-FIM-RSP-TWTAS4\tTerm Based - Renew\n' +
        'FIM-FML-RRM-TSSLRM\tTerm Based - Renew\n' +
        'FIM-FML-RRM-VMERM\tTerm Based - Renew\n' +
        'FIM-TLC-RRM-TLCDERM\tTerm Based - Renew\n' +
        'FIM-TLC-RRM-TLCERM\tTerm Based - Renew\n' +
        'FIM-TLC-RRM-TLCFSERM\tTerm Based - Renew\n' +
        'FIM-TLC-RRM-TLCMLERM\tTerm Based - Renew\n' +
        'FIM-TLC-RRM-TLCNDERM\tTerm Based - Renew\n' +
        'FIM-TLC-RRM-TLCSDERM\tTerm Based - Renew\n' +
        'GOA-GAM-RRM-GCBGRM\tTerm Based - Renew\n' +
        'GOA-GAM-RRM-GCBGTPRM\tTerm Based - Renew\n' +
        'GOA-GAM-RRM-GCSBTPRM\tTerm Based - Renew\n' +
        'GOA-GAM-RRM-GCSBWGRM\tTerm Based - Renew\n' +
        'GOA-GAM-RRM-GPBCRM\tTerm Based - Renew\n' +
        'GOA-GAM-RRM-GPBTPRM\tTerm Based - Renew\n' +
        'GOA-GAM-RRM-GPEBWGRM\tTerm Based - Renew\n' +
        'GOA-GAM-RRM-GPSBWGRM\tTerm Based - Renew\n' +
        'GOA-GAM-RRM-GSBGRM\tTerm Based - Renew\n' +
        'GOA-GAM-RRM-GSBGTPRM\tTerm Based - Renew\n' +
        'GS-GSE-RNM-ACSYNM\tTerm Based - Renew\n' +
        'GS-GSE-RNM-ECBM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-AAMRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-AS2CRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-AUDREPRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-AWERM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-CCARM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-COLBRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-CSBRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-DG3SSRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-DGE3MSRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-DGE3MURM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-E7EURM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-EARMRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-EAWEMRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-EBAMRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-ECBAMRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-ECBPRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-EEARMARM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-EEMTCRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-EESMERM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-EFMMFRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-EFT7ERM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-EFT7EXRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-EFT8CRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-EFT8ERM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-EFT8EXRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-EFTCMFRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-ENTACRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-ERAM(RM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-ESMAM(RM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-ESSMRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-ESW10SRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-ESW50SRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-ETEMTRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-FMRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-FSRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-HS(WCRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-MSGRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-PBRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-PGPARM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-RAARM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-REGCOMRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-SBRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-SCHEDRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-SECFRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-SSBRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-SSGRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-SSRM\tTerm Based - Renew\n' +
        'GS-GSE-RRM-TARM\tTerm Based - Renew\n' +
        'NW-INT-NRPS-ISP\tOne-Time\n' +
        'SM-MQM-NRPS-MQMPER\tOne-Time\n' +
        'SM-PN-RRM-VCPPRM\tTerm Based - Renew\n' +
        'SM-ROB-RRM-RBCANRM\tTerm Based - Renew\n' +
        'SM-ROB-RRM-RBCARM\tTerm Based - Renew\n' +
        'SM-ROB-RRM-RBSANRM\tTerm Based - Renew\n' +
        'SM-ROB-RRM-RBSARM\tTerm Based - Renew\n' +
        'SM-ROB-RRM-RBSARRM\tTerm Based - Renew\n' +
        'SM-SYM-NRST-PXS\tOne-Time\n' +
        'SM-VMC-RRM-VOARM\tTerm Based - Renew\n' +
        'SM-VMC-RRM-VSARM\tTerm Based - Renew\n' +
        'VM-DDL-NRST-FPTEOS\tOne-Time';
}