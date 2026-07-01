/**
 * Abstract base class for brand email handlers
 * Provides common functionality shared across all brands
 * Extends this class instead of implementing IBrandEmailHandler directly
 */
public abstract class BaseBrandEmailHandler implements IBrandEmailHandler {
  // Protected instance variable for template name - accessible to child classes
  protected String templateName;

  // In BaseBrandEmailHandler.cls
  public static IBrandEmailHandler getDefaultHandler() {
    // Return a concrete implementation, perhaps DefaultBrandEmailHandler
    return new DefaultBrandEmailHandler();
  }

  public class DefaultBrandEmailHandler extends BaseBrandEmailHandler {
    // Inherits all base functionality without overrides
  }

  /**
   * Get recipient email address - shared logic for all brands
   * Override this method in brand-specific class if custom logic needed
   */
  public virtual String getRecipient1Email(License_Key__c licenseKey) {
    // Check if Contact_1__c is available and has email
    if (licenseKey.Contact_1__r != null && String.isNotBlank(licenseKey.Contact_1__r.Email)) {
      System.debug('Using Contact 1 Email: ' + licenseKey.Contact_1__r.Email);
      return licenseKey.Contact_1__r.Email;
    }

    return null;
  }

  public virtual String getRecipient2Email(License_Key__c licenseKey) {
    // Check if Contact_2__c is available and has email
    if (licenseKey.Contact_2__r != null && String.isNotBlank(licenseKey.Contact_2__r.Email)) {
      System.debug('Using Contact 2 Email: ' + licenseKey.Contact_2__r.Email);
      return licenseKey.Contact_2__r.Email;
    }

    return null;
  }

  /**
   * Get email template name for a license key based on product code and key type
   * Delegates to LicenseKeyTemplateResolver for template resolution
   * Override this method if brand needs custom template resolution logic
   */
  public virtual String getEmailTemplateForLicenseKey(License_Key__c licenseKey) {
    return LicenseKeyTemplateResolver.getTemplateName(licenseKey);
  }

  public virtual String getRecipient3EmailOwner(License_Key__c licenseKey) {
    User CreatedBy = [
      SELECT Email
      FROM User
      WHERE Id = :licenseKey.CreatedById
      LIMIT 1
    ];
    System.debug('Created By Email: ' + CreatedBy.Email);
    return CreatedBy.Email;
  }

  public virtual List<String> buildBCCRecipientList(License_Key__c licenseKey) {
    List<String> bccRecipient = new List<String>();
    bccRecipient.add(getRecipient3EmailOwner(licenseKey));
    System.debug('BCC List: ' + bccRecipient);
    return bccRecipient;
  }

  /**
   * Build recipient list from license key contacts
   * Returns list of valid email addresses from Contact_1 and Contact_2
   * Override this method if custom recipient logic is needed
   */
  public virtual List<String> buildRecipientList(License_Key__c licenseKey) {
    System.debug('BaseBrandEmailHandler.buildRecipientList called');

    List<String> recipients = new List<String>();
    String recipient1Email = getRecipient1Email(licenseKey);
    String recipient2Email = getRecipient2Email(licenseKey);

    if (String.isNotBlank(recipient1Email)) {
      recipients.add(recipient1Email);
      System.debug('Added recipient 1: ' + recipient1Email);
    }
    if (String.isNotBlank(recipient2Email)) {
      recipients.add(recipient2Email);
      System.debug('Added recipient 2: ' + recipient2Email);
    }

    // Validate at least one recipient exists
    if (recipients.isEmpty()) {
      System.debug('ERROR: No valid recipients found');
      throw new EmailService.EmailServiceException(
        'No valid contact email addresses found. License Key must have at least one contact with a valid email address.'
      );
    }

    System.debug('Total recipients: ' + recipients.size());
    return recipients;
  }

  /**
   * Helper method to handle null values - available to all child classes
   */
  public String nvl(String value) {
    return value != null ? value : '';
  }

  /**
   * Helper method to format Date fields in '10/Jan/2026' format
   * @param dateValue The date value to format
   * @return Formatted date string or empty string if null
   */
  public String formatDateField(Date dateValue) {
    if (dateValue == null) {
      return '';
    }

    // Format as 'dd/MMM/yyyy' => '10/Jan/2026'
    Datetime dt = Datetime.newInstance(dateValue.year(), dateValue.month(), dateValue.day());
    return dt.format('dd/MMM/yyyy');
  }

  /**
   * Base common fields merge - provides common merge fields for all brands
   * This includes all populated License Key fields and standard relationships
   * Brand-specific handlers can call this and add additional fields
   */
  protected Map<String, String> BaseCommonFieldsMerge(License_Key__c licenseKey) {
    System.debug('BaseBrandEmailHandler.BaseCommonFieldsMerge called');

    Map<String, String> mergeFields = new Map<String, String>();

    // Basic License Key fields - using getPopulatedFieldsAsMap for direct fields
    Map<String, Object> licenseKeyMap = licenseKey.getPopulatedFieldsAsMap();
    for (String field : licenseKeyMap.keySet()) {
      Object fieldValue = licenseKeyMap.get(field);
      // Skip relationship fields (they end with __c or __r or standard Id fields)
      // We'll handle relationships separately below
      if (fieldValue != null && !(fieldValue instanceof SObject)) {
        String mergeFieldKey = 'License_Key__c.' + field;
        String mergeFieldValue;

        // Format Date fields specially
        if (fieldValue instanceof Date) {
          mergeFieldValue = formatDateField((Date) fieldValue);
        } else {
          mergeFieldValue = nvl(String.valueOf(fieldValue));
        }

        mergeFields.put(mergeFieldKey, mergeFieldValue);
      }
    }

    // Account relationship fields - must be added explicitly
    if (licenseKey.Account__r != null) {
      mergeFields.put('License_Key__c.Account__r.Name', nvl(licenseKey.Account__r.Name));
      mergeFields.put('License_Key__c.Account__r.AccountNumber', nvl(licenseKey.Account__r.AccountNumber));
      System.debug('Added Account relationship fields');
    }

    // Contact 1 relationship fields
    if (licenseKey.Contact_1__r != null) {
      mergeFields.put('License_Key__c.Contact_1__r.Name', nvl(licenseKey.Contact_1__r.Name));
      mergeFields.put('License_Key__c.Contact_1__r.FirstName', nvl(licenseKey.Contact_1__r.FirstName));
      mergeFields.put('License_Key__c.Contact_1__r.LastName', nvl(licenseKey.Contact_1__r.LastName));
      mergeFields.put('License_Key__c.Contact_1__r.Email', nvl(licenseKey.Contact_1__r.Email));
      System.debug('Added Contact_1 relationship fields');
    }

    // Contact 2 relationship fields
    if (licenseKey.Contact_2__r != null) {
      mergeFields.put('License_Key__c.Contact_2__r.Name', nvl(licenseKey.Contact_2__r.Name));
      mergeFields.put('License_Key__c.Contact_2__r.FirstName', nvl(licenseKey.Contact_2__r.FirstName));
      mergeFields.put('License_Key__c.Contact_2__r.LastName', nvl(licenseKey.Contact_2__r.LastName));
      mergeFields.put('License_Key__c.Contact_2__r.Email', nvl(licenseKey.Contact_2__r.Email));
      System.debug('Added Contact_2 relationship fields');
    }

    System.debug('Total base merge fields prepared: ' + mergeFields.size());
    return mergeFields;
  }

  /**
   * Validate and prepare license key for email processing
   * Validates ID, resolves email template, and stores it for later use
   * Override this method if brand needs custom validation logic
   */
  public virtual Boolean validateAndPrepare(License_Key__c licenseKey) {
    System.debug('BaseBrandEmailHandler.validateAndPrepare called');

    // Basic validation
    if (licenseKey.Id == null) {
      System.debug('ERROR: License Key ID is null');
      return false;
    }

    // Resolve email template using product code and key type
    this.templateName = getEmailTemplateForLicenseKey(licenseKey);

    if (String.isBlank(this.templateName)) {
      System.debug('ERROR: Template name is blank after determination');
      return false;
    }

    System.debug('Validation passed');
    return true;
  }

  /**
   * Get additional merge fields for email template
   * Default implementation returns common merge fields from BaseCommonFieldsMerge
   * Override this method if brand needs custom merge fields
   */
  public virtual Map<String, String> getAdditionalMergeFields(License_Key__c licenseKey) {
    System.debug('BaseBrandEmailHandler.getAdditionalMergeFields called');

    // Get common merge fields from base class
    Map<String, String> mergeFields = BaseCommonFieldsMerge(licenseKey);

    System.debug('Total merge fields prepared: ' + mergeFields.size());
    return mergeFields;
  }

  /**
   * Send email for license key using EmailService
   * Default implementation handles standard email sending flow
   * Override this method if brand needs custom email sending logic
   * @return EmailResult containing success status and error details
   */
  public virtual EmailResult sendEmail(License_Key__c licenseKey) {
    System.debug('=== BaseBrandEmailHandler.sendEmail START ===');

    try {
      // Build recipient list using base class method
      List<String> recipients = buildRecipientList(licenseKey);
      List<String> bccRecipients = buildBCCRecipientList(licenseKey);

      Map<String, String> mergeFields = getAdditionalMergeFields(licenseKey);

      System.debug('Delegating to EmailService with ' + recipients.size() + ' recipient(s)...');

      EmailResult result = EmailService.sendLicenseKeyEmail(
        licenseKey,
        templateName,
        recipients,
        bccRecipients,
        mergeFields
      );

      if (result.isSuccess) {
        System.debug('Email sent successfully via EmailService');
      } else {
        System.debug('Email sending failed: ' + result.errorMessage);
      }

      System.debug('=== BaseBrandEmailHandler.sendEmail END ===');
      return result;
    } catch (Exception e) {
      System.debug('ERROR in BaseBrandEmailHandler.sendEmail: ' + e.getMessage());
      System.debug('Stack Trace: ' + e.getStackTraceString());
      System.debug('=== BaseBrandEmailHandler.sendEmail END ===');
      return new EmailResult(false, e.getMessage(), e.getStackTraceString());
    }
  }
}