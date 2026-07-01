/**
 * Interface for brand-specific email handlers
 * Each brand implementation must implement this interface
 */
public interface IBrandEmailHandler {
  /**
   * Get the recipient email address for the license key
   * @param licenseKey The License Key record to process
   * @return Email address to send to
   */
  String getRecipient1Email(License_Key__c licenseKey);

  String getRecipient2Email(License_Key__c licenseKey);

  /**
   * Get the email template name for a license key based on product identifier and key type
   * @param licenseKey The License Key record with LKG_Product_Identifier_Name__c and Key_Type__c
   * @return Email template API name
   */
  String getEmailTemplateForLicenseKey(License_Key__c licenseKey);

  /**
   * Get any additional merge fields for the email template
   * @param licenseKey The License Key record to process
   * @return Map of merge field names and values
   */
  Map<String, String> getAdditionalMergeFields(License_Key__c licenseKey);

  /**
   * Process and send email for the license key
   * @param licenseKey The License Key record to process
   * @return EmailResult containing success status and error details
   */
  EmailResult sendEmail(License_Key__c licenseKey);

  /**
   * Perform any brand-specific data preparation or validation
   * @param licenseKey The License Key record to process
   * @return Boolean indicating if the record is valid for email processing
   */
  Boolean validateAndPrepare(License_Key__c licenseKey);
}