/**
 * @description       : TBE Bulk Deletion
 * @author            : LJ: liam.jeong.c@fortra.com
 * @created on        : 2026-05-18
 * @last modified on  : 2026-05-18
 * @last modified by  : LJ: liam.jeong.c@fortra.com
**/
public class PbeTeardownBatch implements Database.Batchable<SObject>, Database.Stateful {

    public Integer totalDeleted = 0;
    public Integer totalFailed  = 0;
    public String  firstError;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator('SELECT Id FROM PricebookEntry');
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Database.DeleteResult> results = Database.delete(scope, false);
        for (Database.DeleteResult r : results) {
            if (r.isSuccess()) {
                totalDeleted++;
            } else {
                totalFailed++;
                if (firstError == null && !r.getErrors().isEmpty())
                    firstError = r.getErrors()[0].getStatusCode()
                        + ': ' + r.getErrors()[0].getMessage();
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('==== PBE TEARDOWN BATCH — FINISHED ====');
        System.debug('Total deleted: ' + totalDeleted);
        System.debug('Total failed:  ' + totalFailed
            + (firstError == null ? '' : ' -> ' + firstError));
        System.debug('PricebookEntry rows remaining: '
            + [SELECT COUNT() FROM PricebookEntry]);
    }
}