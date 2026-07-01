/**
 * Utility class for publishing Platform Event notifications
 * Publishes events when License Key email status changes
 */
public class LicenseKeyNotificationPublisher {
  /**
   * Publish Platform Events for License Key email notifications
   * This allows any LWC component to receive real-time notifications via streaming API
   *
   * @param licenseKeys List of License Keys with updated email status
   */
  public static void publishEmailNotifications(List<License_Key__c> licenseKeys) {
    System.debug('=== LicenseKeyNotificationPublisher.publishEmailNotifications ===');
    System.debug('Publishing Platform Events for ' + licenseKeys.size() + ' license key(s)');

    // Query full License Key details needed for notification
    List<License_Key__c> fullKeys = [
      SELECT Id, Name, Account__c, Email_Status__c, Email_Error_Message__c, Last_Email_Sent_Date__c
      FROM License_Key__c
      WHERE Id IN :licenseKeys
    ];

    // Create Platform Event records
    List<License_Key_Email_Event__e> events = new List<License_Key_Email_Event__e>();

    for (License_Key__c key : fullKeys) {
      System.debug('Creating event for License Key: ' + key.Name);
      System.debug('  Account: ' + key.Account__c);
      System.debug('  Email Status: ' + key.Email_Status__c);

      License_Key_Email_Event__e event = new License_Key_Email_Event__e(
        License_Key_Id__c = key.Id,
        License_Key_Name__c = key.Name,
        Account_Id__c = key.Account__c,
        Email_Status__c = key.Email_Status__c,
        Error_Message__c = key.Email_Error_Message__c,
        Last_Email_Date__c = key.Last_Email_Sent_Date__c
      );

      events.add(event);
    }

    // Publish Platform Events
    if (!events.isEmpty()) {
      List<Database.SaveResult> results = EventBus.publish(events);

      // Check results
      for (Integer i = 0; i < results.size(); i++) {
        if (results[i].isSuccess()) {
          System.debug('Successfully published event for: ' + fullKeys[i].Name);
        } else {
          for (Database.Error error : results[i].getErrors()) {
            System.debug('Error publishing event for ' + fullKeys[i].Name + ': ' + error.getMessage());
          }
        }
      }
    }

    System.debug('Platform Event publishing completed.');
  }
}