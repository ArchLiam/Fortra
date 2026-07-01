public class LicenseKeyEmailHandler {
  /**
   * Process License Key Email based on IDs
   * This method queries the license keys, processes them, and updates the results
   * @param keyIds List of License Key IDs to process
   */
  public static void ProcessLicenseKeyEmailFromIds(List<Id> keyIds) {
    System.debug('=== ProcessLicenseKeyEmailFromIds Method Called ===');

    if (keyIds == null || keyIds.isEmpty()) {
      System.debug('No License Key IDs to process');
      return;
    }

    System.debug('Number of License Key IDs to process: ' + keyIds.size());

    // Query license keys with all required fields
    List<License_Key__c> keysToProcess = [
      SELECT
        Id,
        Name,
        Brand__c,
        Key_Type__c,
        License_Key__c,
        Hardware__c,
        Silo__c,
        Start_Date__c,
        End_Date__c,
        Send_Email__c,
        Add_Ons__c,
        Features__c,
        Instances__c,
        License_Key_Serial_Number__c,
        Number_Of_Users__c,
        License_Key_Product_Name__c,
        Contact_1__c,
        Contact_2__c,
        Contact_1__r.Id,
        Contact_1__r.Name,
        Contact_1__r.FirstName,
        Contact_1__r.LastName,
        Contact_1__r.Email,
        Contact_2__r.Id,
        Contact_2__r.Name,
        Contact_2__r.FirstName,
        Contact_2__r.LastName,
        Contact_2__r.Email,
        Account__c,
        Account__r.Name,
        Account__r.AccountNumber,
        CreatedById,
        LPAR_Feature_Code__c,
        LPAR_Number__c,
        LPAR_Model_Number__c,
        LPAR_Number_Concatenate__c,
        LPAR_Serial_Number__c,
        LPAR_System_Name__c,
        Number_of_Processors__c,
        Processor_Type__c,
        iASP_Name__c,
        Points__c,
        Legacy_End_Date__c,
        Hardware_ID__c,
        LKG_Product_Identifier_Name__c,
        Create_License_Key_File__c
      FROM License_Key__c
      WHERE Id IN :keyIds
    ];

    if (keysToProcess.isEmpty()) {
      System.debug('No License Keys found for the provided IDs');
      return;
    }

    // Process emails and get results
    Map<Id, EmailResult> emailResults = ProcessLicenseKeyEmail(keysToProcess);

    // Update records based on results
    List<License_Key__c> keysToUpdate = new List<License_Key__c>();

    for (License_Key__c key : keysToProcess) {
      EmailResult result = emailResults.get(key.Id);

      License_Key__c updateKey = new License_Key__c(Id = key.Id);

      // Always reset the Send_Email__c flag
      updateKey.Send_Email__c = false;

      if (result != null) {
        if (result.isSuccess) {
          // Clear any previous error messages on success
          updateKey.Email_Status__c = 'Success';
          updateKey.Email_Error_Message__c = null;
          updateKey.Email_Error_Details__c = null;
          updateKey.Last_Email_Sent_Date__c = DateTime.now();
          System.debug('Email sent successfully for: ' + key.Name);
        } else {
          // Store error information
          updateKey.Email_Status__c = 'Failed';
          updateKey.Email_Error_Message__c = result.userFriendlyMessage;
          updateKey.Email_Error_Details__c = result.getFullErrorInfo();
          System.debug('Email failed for: ' + key.Name + ' - ' + result.errorMessage);
        }
      } else {
        // No result returned - unexpected error
        updateKey.Email_Status__c = 'Failed';
        updateKey.Email_Error_Message__c = 'An unexpected error occurred while processing the email request.';
      }

      keysToUpdate.add(updateKey);
    }

    // Update the records with results
    if (!keysToUpdate.isEmpty()) {
      try {
        update keysToUpdate;
        System.debug('Successfully updated ' + keysToUpdate.size() + ' license key(s) with email results');

        // Publish Lightning Message Service events for notifications
        LicenseKeyNotificationPublisher.publishEmailNotifications(keysToUpdate);
      } catch (Exception e) {
        System.debug('ERROR updating license keys with email results: ' + e.getMessage());
      }
    }

    System.debug('=== ProcessLicenseKeyEmailFromIds Method Completed ===');
  }

  /**
   * Process License Key Email based on Brand and Key Type
   * Uses Factory pattern to delegate to brand-specific handlers
   * @param licenseKeys List of License Key records to process
   * @return Map of License Key Id to EmailResult
   */
  public static Map<Id, EmailResult> ProcessLicenseKeyEmail(List<License_Key__c> licenseKeys) {
    System.debug('=== ProcessLicenseKeyEmail Method Called ===');
    System.debug('Number of License Keys to process: ' + licenseKeys.size());

    Map<Id, EmailResult> results = new Map<Id, EmailResult>();

    for (License_Key__c lk : licenseKeys) {
      System.debug('--- Processing License Key ---');
      System.debug('License Key Name: ' + lk.Name);
      System.debug('Silo: ' + lk.Silo__c);
      System.debug('Key Type: ' + lk.Key_Type__c);
      System.debug('Send Email: ' + lk.Send_Email__c);
      System.debug('Record ID: ' + lk.Id);

      try {
        // Get the appropriate handler using Factory pattern based on Silo
        IBrandEmailHandler handler = BrandEmailHandlerFactory.getHandler(lk.Silo__c);
        System.debug('Handler obtained: ' + handler);

        // Validate and prepare the license key
        Boolean isValid = handler.validateAndPrepare(lk);

        if (isValid) {
          System.debug('License Key validated successfully, proceeding to send email');

          // Send the email using brand-specific logic
          EmailResult result = handler.sendEmail(lk);
          results.put(lk.Id, result);

          if (result.isSuccess) {
            System.debug('Email processing completed successfully for License Key: ' + lk.Name);
          } else {
            System.debug('Email processing failed for License Key: ' + lk.Name);
            System.debug('Error: ' + result.errorMessage);
          }
        } else {
          System.debug('WARNING: License Key validation failed for: ' + lk.Name);
          results.put(
            lk.Id,
            new EmailResult(false, 'License Key validation failed', 'The license key did not pass validation checks')
          );
        }
      } catch (Exception e) {
        System.debug('ERROR processing License Key ' + lk.Name + ': ' + e.getMessage());
        System.debug('Stack Trace: ' + e.getStackTraceString());
        results.put(lk.Id, new EmailResult(false, e.getMessage(), e.getStackTraceString()));
        // Continue processing other records even if one fails
      }

      System.debug('----------------------------');
    }

    System.debug('=== ProcessLicenseKeyEmail Method Completed ===');
    return results;
  }
}