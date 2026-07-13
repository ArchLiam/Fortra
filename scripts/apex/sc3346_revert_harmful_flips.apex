// SC-3346 — revert the harmful 2026-07-06 default flips on maintenance SKUs.
//
// The 07-06 change flipped these products' DEFAULT selling model OneTime -> TermDefined, but the
// derived-pricing seed lives on the (now demoted) OneTime PBE while the new TermDefined default PBE is
// $0 / IsDerived=false. Result: NEW-business pricing resolves the non-derived $0 entry and commits $0.
// (Latent today — no new business sold since 07-06 — but the next sale of each SKU prices $0.)
//
// FIX (additive-safe): restore OneTime as the default (new business prices via derived pricing again),
// and set the Term-Based-Annual TermDefined option back to NON-default. The TermDefined option STAYS on
// the product, so renewal-as-itself via RenewalMaintenanceProvisionService is unaffected.
//
// Scope = an explicit ALLOWLIST of confirmed regressions only — NOT a blanket revert. Idempotent
// (skips any product already OneTime-default). DRY_RUN default true. READ the debug before committing.
//
//   EXCLUDED deliberately:
//     FIM-FIM-RNM-TACWIN  — priced $0 as OneTime-default BEFORE the flip (pre-existing gap; revert won't help)
//     115 RRM + 9 USD-risk — 'Renewal Maintenance' prices in renewal (COLA) context; pending the runtime probe

Boolean DRY_RUN = true;                               // <-- flip to false to commit

Set<String> TARGET_CODES = new Set<String>{
    'GS-GSE-RNM-ECBM',                                // ~$44k realized; historically derived non-$0
    'GS-GSE-RNM-ACSYNM'                               // ~$2.3k realized; historically derived non-$0
};

Id ONETIME_PSM     = '0jPWC00000005yz2AA';            // "One Time"
Id TERM_ANNUAL_PSM = '0jPWC000000060b2AA';            // "Term Based - Annual"

Map<String, Id> idByCode = new Map<String, Id>();
for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode IN :TARGET_CODES]) {
    idByCode.put(p.ProductCode, p.Id);
}

Map<Id, List<ProductSellingModelOption>> byProduct = new Map<Id, List<ProductSellingModelOption>>();
for (ProductSellingModelOption o : [
        SELECT Id, Product2Id, Product2.ProductCode, ProductSellingModelId,
               ProductSellingModel.SellingModelType, IsDefault
        FROM ProductSellingModelOption
        WHERE Product2Id IN :idByCode.values()]) {
    if (!byProduct.containsKey(o.Product2Id)) {
        byProduct.put(o.Product2Id, new List<ProductSellingModelOption>());
    }
    byProduct.get(o.Product2Id).add(o);
}

List<ProductSellingModelOption> toUpdate = new List<ProductSellingModelOption>();
List<String> report = new List<String>();

for (String code : TARGET_CODES) {
    Id pid = idByCode.get(code);
    if (pid == null) { report.add(code + ' : NOT FOUND'); continue; }

    ProductSellingModelOption oneTime;
    ProductSellingModelOption termAnnual;
    for (ProductSellingModelOption o : byProduct.get(pid)) {
        if (o.ProductSellingModelId == ONETIME_PSM)     { oneTime = o; }
        if (o.ProductSellingModelId == TERM_ANNUAL_PSM) { termAnnual = o; }
    }

    if (oneTime == null)          { report.add(code + ' : SKIP (no OneTime option to restore)'); continue; }
    if (oneTime.IsDefault == true) { report.add(code + ' : already OneTime-default, no-op'); continue; }

    oneTime.IsDefault = true;                          // restore OneTime as default
    toUpdate.add(oneTime);
    String note = 'REVERT -> OneTime default';
    if (termAnnual != null && termAnnual.IsDefault == true) {
        termAnnual.IsDefault = false;                  // demote the flipped TermDefined option (kept, just non-default)
        toUpdate.add(termAnnual);
        note += ' (Term-Annual -> non-default, kept for renewal)';
    }
    report.add(code + ' : ' + note);
}

System.debug(LoggingLevel.ERROR, '===== SC-3346 revert harmful flips (' + (DRY_RUN ? 'DRY-RUN' : 'COMMIT') + ') =====');
System.debug(LoggingLevel.ERROR, 'targets: ' + TARGET_CODES.size() + ' | PSMO updates staged: ' + toUpdate.size());
System.debug(LoggingLevel.ERROR, 'PER-PRODUCT:\n  ' + String.join(report, '\n  '));

if (!DRY_RUN) {
    if (!toUpdate.isEmpty()) {
        // Single DML so the end-state carries exactly one default per product (OneTime true, Term-Annual false).
        update toUpdate;
        System.debug(LoggingLevel.ERROR, 'COMMITTED — ' + toUpdate.size() + ' PSMO rows updated.');
    } else {
        System.debug(LoggingLevel.ERROR, 'nothing to update (all targets already OneTime-default).');
    }
} else {
    System.debug(LoggingLevel.ERROR, 'DRY-RUN only — no DML. Flip DRY_RUN=false to commit.');
}
System.debug(LoggingLevel.ERROR, '=================================================');
