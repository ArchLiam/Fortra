Id quoteId = '0Q0WC000003KX7l';
List<Operations_Checklist_Config__mdt> cfg = [
    SELECT Item_Label__c, Sort_Order__c
    FROM Operations_Checklist_Config__mdt
    WHERE Is_Active__c = true
    ORDER BY Sort_Order__c ASC
];
Integer existing = [SELECT COUNT() FROM Quote_Checklist_Item__c WHERE Quote__c = :quoteId];
System.debug('existing items = ' + existing);
List<Quote_Checklist_Item__c> items = new List<Quote_Checklist_Item__c>();
if (existing == 0) {
    for (Operations_Checklist_Config__mdt c : cfg) {
        items.add(new Quote_Checklist_Item__c(
            Quote__c = quoteId,
            Item_Name__c = c.Item_Label__c,
            Sort_Order__c = c.Sort_Order__c,
            Is_Checked__c = true
        ));
    }
    insert items;
    System.debug('inserted ' + items.size() + ' checked items');
} else {
    System.debug('items already exist; skipping');
}
