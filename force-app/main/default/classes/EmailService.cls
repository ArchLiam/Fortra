/**
 * Service class for handling all email operations
 * Centralizes email sending logic for license keys
 */
public class EmailService {
  // Dependency injection for testability
  // Allows tests to inject MockEmailSender while production uses DefaultEmailSender
  @TestVisible
  private static IEmailSender emailSender = new DefaultEmailSender();

  /**
   * Send email for a license key using specified template
   * @param licenseKey The License Key record
   * @param templateApiName API name of the email template to use
   * @param recipientEmail Email address to send to (optional, can be derived from related Contact)
   * @param additionalMergeFields Optional map of additional merge field values
   * @return EmailResult containing success status and error details
   */
  public static EmailResult sendLicenseKeyEmail(
    License_Key__c licenseKey,
    String templateApiName,
    String[] recipientEmail,
    String[] bccRecipient,
    Map<String, String> additionalMergeFields
  ) {
    System.debug('=== EmailService.sendLicenseKeyEmail START ===');
    System.debug('License Key ID: ' + licenseKey.Id);
    System.debug('License Key Name: ' + licenseKey.Name);
    System.debug('Template API Name: ' + templateApiName);
    System.debug('Recipient Email: ' + recipientEmail);
    System.debug('BCC Recipient Email: ' + bccRecipient);

    try {
      // Validate inputs
      if (String.isBlank(templateApiName)) {
        System.debug('ERROR: Template API Name is required');
        return new EmailResult(false, 'Email template name is required', 'Template API Name was blank or null');
      }

      if (recipientEmail == null || recipientEmail.isEmpty()) {
        System.debug('ERROR: At least one recipient email is required');
        String errorMsg = 'At least one contact with valid email address is required to send license key email';
        return new EmailResult(false, errorMsg, 'No recipient email addresses were provided');
      }

      if (additionalMergeFields != null && !additionalMergeFields.isEmpty()) {
        System.debug('Additional Merge Fields:');
        for (String key : additionalMergeFields.keySet()) {
          System.debug('  ' + key + ' = ' + additionalMergeFields.get(key));
        }
      }

      // Get email template ID
      Id templateId = getEmailTemplateId(templateApiName);
      if (templateId == null) {
        System.debug('ERROR: Email template not found: ' + templateApiName);
        return new EmailResult(
          false,
          'Email template not found: ' + templateApiName,
          'The specified email template does not exist in the system'
        );
      }

      // Get template content
      String htmlBody = getTemplateHtmlBody(templateId);
      String plainBody = getTemplatePlainTextBody(templateId);
      String subject = getTemplateSubject(templateId);

      if (licenseKey.LKG_Product_Identifier_Name__c == null) {
        System.debug('ERROR: License Key Product Identifier is null');
        return new EmailResult(
          false,
          'License Key Product Identifier is required',
          'The LKG_Product_Identifier_Name__c field on License Key is null'
        );
      }

      // STEP 1: Replace placeholders (||PlaceholderName||) with Text_Injection__c
      // This happens FIRST to inject configured text blocks into template
      // Also injects product-specific instructions from LKG_Product__mdt based on LKG_Product_Identifier_Name__c
      String productIdentifier = licenseKey.LKG_Product_Identifier_Name__c;
      System.debug('Product Identifier for placeholder injection: ' + productIdentifier);

      if (htmlBody != null) {
        htmlBody = EmailTemplatePlaceholderProcessor.replacePlaceholdersWithInjectedText(htmlBody, productIdentifier);
        System.debug('Placeholders replaced with configured text in HTML body');
      }
      if (plainBody != null) {
        plainBody = EmailTemplatePlaceholderProcessor.replacePlaceholdersWithInjectedText(plainBody, productIdentifier);
        System.debug('Placeholders replaced with configured text in plain text body');
      }
      if (subject != null) {
        subject = EmailTemplatePlaceholderProcessor.replacePlaceholdersWithInjectedText(subject, productIdentifier);
        System.debug('Placeholders replaced with configured text in subject');
      }

      // STEP 2: Replace merge fields ({License_Key__c.Field__c}) with actual values
      // Lightning Email Templates with RelatedTo can only access direct fields on License_Key__c
      // They CANNOT access relationship fields like Account__r.Name or Contact_1__r.Name
      // So we must manually replace merge fields for relationship data

      if (additionalMergeFields != null && !additionalMergeFields.isEmpty()) {
        System.debug('Replacing merge fields in template...');
        for (String fieldPath : additionalMergeFields.keySet()) {
          String value = additionalMergeFields.get(fieldPath);
          String placeholder = '{' + fieldPath + '}'; // Classic syntax: {License_Key__c.Field}

          if (htmlBody != null && htmlBody.contains(placeholder)) {
            htmlBody = htmlBody.replace(placeholder, value);
            System.debug('Replaced ' + placeholder + ' with ' + value);
          }
          if (plainBody != null && plainBody.contains(placeholder)) {
            plainBody = plainBody.replace(placeholder, value);
          }
          if (subject != null && subject.contains(placeholder)) {
            subject = subject.replace(placeholder, value);
          }
        }
      }

      // STEP 3: Clean up any remaining unreplaced merge fields and placeholders
      if (htmlBody != null) {
        htmlBody = EmailTemplatePlaceholderProcessor.removeUnreplacedMergeFields(htmlBody);
        System.debug('Cleaned up unreplaced merge fields in HTML body');
      }
      if (plainBody != null) {
        plainBody = EmailTemplatePlaceholderProcessor.removeUnreplacedMergeFields(plainBody);
        System.debug('Cleaned up unreplaced merge fields in plain text body');
      }
      if (subject != null) {
        subject = EmailTemplatePlaceholderProcessor.removeUnreplacedMergeFields(subject);
        System.debug('Cleaned up unreplaced merge fields in subject');
      }

      // Prepare email message
      Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();

      email.setToAddresses(recipientEmail);

      if (bccRecipient != null && !bccRecipient.isEmpty()) {
        email.setBccAddresses(bccRecipient);
      }

      // Set subject and body directly (don't use template ID after we've customized the content)
      if (subject != null) {
        email.setSubject(subject);
      }
      if (htmlBody != null) {
        email.setHtmlBody(htmlBody);
      }
      if (plainBody != null && htmlBody == null) {
        email.setPlainTextBody(plainBody);
      }

      // Get Contact ID and set relationship for activity logging
      Id contactId = getContactId(licenseKey);
      if (contactId != null) {
        email.setTargetObjectId(contactId);
        email.setWhatId(licenseKey.Id);

        // In production, save as activity; in test context, skip to avoid DML issues
        // File attachments ARE supported with setSaveAsActivity(true) when TargetObjectId is a Contact
        email.setSaveAsActivity(!Test.isRunningTest());
        System.debug('setSaveAsActivity: ' + !Test.isRunningTest());
      }

      // If License key's Create License Key File field is true,
      // Attach the first attachment found related to the license key
      if (licenseKey.Create_License_Key_File__c) {
        // setEntityAttachments to both send the attachment in the email and make it visible in the activity record in Salesforce UI
        List<String> attachmentIds = EmailAttachmentService.getAttachmentIdsForLicenseKey(licenseKey.Id);

        if (!attachmentIds.isEmpty()) {
          email.setEntityAttachments(attachmentIds);
          System.debug('Entity attachments set - will appear in both email and Salesforce UI');
        } else {
          System.debug('WARNING: No attachment found for License Key: ' + licenseKey.Id);
        }
      }

      // Send email using injected email sender (allows mocking in tests)
      System.debug('Sending email...');
      IEmailSenderResult result = emailSender.sendEmail(new List<Messaging.SingleEmailMessage>{ email });

      if (result.isSuccess()) {
        System.debug('Email sent successfully');
        System.debug('=== EmailService.sendLicenseKeyEmail END ===');
        return new EmailResult(true);
      } else {
        String errorMsg = result.getErrorMessage();
        System.debug('Email failed: ' + errorMsg);
        System.debug('=== EmailService.sendLicenseKeyEmail END ===');
        return new EmailResult(false, errorMsg, 'Salesforce messaging service returned an error');
      }
    } catch (Exception e) {
      System.debug('ERROR in sendLicenseKeyEmail: ' + e.getMessage());
      System.debug('Stack Trace: ' + e.getStackTraceString());
      return new EmailResult(false, e.getMessage(), e.getStackTraceString());
    }
  }

  /**
   * Overloaded method - simplified version without additional merge fields
   */
  public static EmailResult sendLicenseKeyEmail(
    License_Key__c licenseKey,
    String templateApiName,
    String[] recipientEmail
  ) {
    return sendLicenseKeyEmail(licenseKey, templateApiName, recipientEmail, null, null);
  }

  /**
   * Helper method to get email template ID from API name
   * @param templateApiName API name of the email template
   * @return Email template ID
   */
  @TestVisible
  private static Id getEmailTemplateId(String templateApiName) {
    try {
      EmailTemplate template = [
        SELECT Id
        FROM EmailTemplate
        WHERE DeveloperName = :templateApiName
        LIMIT 1
      ];
      return template.Id;
    } catch (QueryException e) {
      System.debug('Email template not found: ' + templateApiName);
      return null;
    }
  }

  /**
   * Helper method to get Contact ID from License Key
   * Returns Contact_1__c if available
   */
  @TestVisible
  private static Id getContactId(License_Key__c licenseKey) {
    // Return Contact_1__c if present; fall back to Contact_2__c so that activity logging
    // works correctly when only Contact 2 is selected.
    if (licenseKey.Contact_1__c != null) {
      return licenseKey.Contact_1__c;
    }
    if (licenseKey.Contact_2__c != null) {
      return licenseKey.Contact_2__c;
    }
    return null;
  }

  /**
   * Get email template HTML body
   */
  @TestVisible
  private static String getTemplateHtmlBody(Id templateId) {
    try {
      EmailTemplate template = [
        SELECT HtmlValue
        FROM EmailTemplate
        WHERE Id = :templateId
        LIMIT 1
      ];
      return template.HtmlValue;
    } catch (QueryException e) {
      System.debug('Could not retrieve HTML body for template: ' + templateId);
    }
    return null;
  }

  /**
   * Get email template plain text body
   */
  @TestVisible
  private static String getTemplatePlainTextBody(Id templateId) {
    try {
      EmailTemplate template = [
        SELECT Body
        FROM EmailTemplate
        WHERE Id = :templateId
        LIMIT 1
      ];
      return template.Body;
    } catch (QueryException e) {
      System.debug('Could not retrieve plain text body for template: ' + templateId);
      return null;
    }
  }

  /**
   * Get email template subject
   */
  @TestVisible
  private static String getTemplateSubject(Id templateId) {
    try {
      EmailTemplate template = [
        SELECT Subject
        FROM EmailTemplate
        WHERE Id = :templateId
        LIMIT 1
      ];
      return template.Subject;
    } catch (QueryException e) {
      System.debug('Could not retrieve subject for template: ' + templateId);
    }
    return null;
  }

  /**
   * Custom exception for email service errors
   */
  public class EmailServiceException extends Exception {
  }
}