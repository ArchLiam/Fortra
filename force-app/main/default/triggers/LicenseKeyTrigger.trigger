trigger LicenseKeyTrigger on License_Key__c(after insert, after update) {
  // Process only License Keys where Send_Email__c checkbox was checked
  // Collect IDs of License Keys that need email processing
  List<Id> keyIdToProcess = new List<Id>();

  if (Trigger.isInsert) {
    // On insert, process if Send_Email__c is checked
    for (License_Key__c newKey : Trigger.new) {
      if (newKey.Send_Email__c == true) {
        keyIdToProcess.add(newKey.Id);
        System.debug('License key selected for email processing (insert): ' + newKey.Id);
      }
    }
  } else if (Trigger.isUpdate) {
    // On update, process if Send_Email__c was just checked (changed from false to true)
    for (License_Key__c newKey : Trigger.new) {
      License_Key__c oldKey = Trigger.oldMap.get(newKey.Id);

      if (newKey.Send_Email__c == true && oldKey.Send_Email__c == false) {
        keyIdToProcess.add(newKey.Id);
        System.debug('License key selected for email processing (update): ' + newKey.Id);
      }
    }
  }

  // Delegate to handler class for processing
  if (keyIdToProcess != null && !keyIdToProcess.isEmpty()) {
    LicenseKeyEmailHandler.ProcessLicenseKeyEmailFromIds(keyIdToProcess);
  }
}