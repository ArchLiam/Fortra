/**
 * Orchestrates Robot and CCSS license key file generation.
 * Validates payload, fetches keys once, picks the right builder by silo,
 * attaches the .HSL file to the Account, and optionally emails it.
 *
 * Silo-specific differences handled here (3 variables only):
 *   - builder instance  → LkgRobotFileBuilder / LkgCcssFileBuilder
 *   - siloLabel         → 'Robot' / 'CCSS'
 *   - emailTemplateName → 'License Code File from Help/Systems' / 'License Code File from CCSS'
 */
public with sharing class LkgLicenseKeysFileService {
  // Dependency injection for testability — mirrors the pattern in EmailService
  @TestVisible
  private static IEmailSender emailSender = new DefaultEmailSender();

  public static LkgFileGenerateResult generateFile(
    List<Id> keyIds,
    Id accountId,
    Id contact1Id,
    Id contact2Id,
    Boolean sendEmail
  ) {
    try {
      // ── 1. Validate ────────────────────────────────────────────────────────
      if (keyIds == null || keyIds.isEmpty()) {
        return new LkgFileGenerateResult(false, 'No License Keys selected.');
      }
      if (accountId == null) {
        return new LkgFileGenerateResult(false, 'Account is required.');
      }
      if (sendEmail == true && contact1Id == null && contact2Id == null) {
        return new LkgFileGenerateResult(false, 'At least one contact is required to send an email.');
      }

      // ── 2. Fetch keys once (all fields for both silos) ─────────────────────
      List<License_Key__c> keys = [
        SELECT
          Id,
          Silo__c,
          Key_Type__c,
          End_Date__c,
          License_Key__c,
          License_Key_Product_Name__c,
          LKG_Product_Identifier_Name__c,
          Product_Code__c,
          LPAR_Number__c,
          LPAR_System_Name__c,
          LPAR_Serial_Number__c,
          LPAR_Model_Number__c,
          LPAR_Feature_Code__c,
          Account__c
        FROM License_Key__c
        WHERE Id IN :keyIds AND Account__c = :accountId
      ];

      if (keys.isEmpty()) {
        return new LkgFileGenerateResult(false, 'No matching License Key records found for this Account.');
      }

      // ── 3. All selected keys must belong to the same silo ──────────────────
      String silo = keys[0].Silo__c?.toLowerCase();
      for (License_Key__c k : keys) {
        if (k.Silo__c?.toLowerCase() != silo) {
          return new LkgFileGenerateResult(false, 'All selected keys must belong to the same Silo (Robot or CCSS).');
        }
      }

      // ── 4. Silo-specific config (the only 3 things that differ) ────────────
      LkgISeriesFileBuilder builder;
      String siloLabel;
      String emailTemplateName;

      if (silo == 'robot') {
        builder = new LkgRobotFileBuilder();
        siloLabel = 'Robot';
        emailTemplateName = 'Fortra | LK | Robot License Keys File';
      } else if (silo == 'ccss') {
        builder = new LkgCcssFileBuilder();
        siloLabel = 'CCSS';
        emailTemplateName = 'Fortra | LK | CCSS License Keys File';
      } else {
        return new LkgFileGenerateResult(false, 'Unsupported silo: ' + silo + '. Expected robot or ccss.');
      }

      // ── 5. Build file + attach to Account (Salesforce Files / ContentVersion) ──
      String fileContent = builder.buildFile(keys);
      String fileName = siloLabel + ' License Key File ' + Datetime.now().format('MMddyyyyHHmmss') + '.HSL';

      // Insert ContentVersion — Salesforce automatically creates the ContentDocument
      ContentVersion cv = new ContentVersion(
        Title = fileName,
        PathOnClient = fileName,
        VersionData = Blob.valueOf(fileContent),
        IsMajorVersion = true
      );
      insert cv;

      // Re-query to get the auto-generated ContentDocumentId
      cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

      // Link the ContentDocument to the Account so it appears in the Files related list
      insert new ContentDocumentLink(
        ContentDocumentId = cv.ContentDocumentId,
        LinkedEntityId = accountId,
        ShareType = 'V',
        Visibility = 'AllUsers'
      );

      // ── 6. Send email if requested ─────────────────────────────────────────
      if (sendEmail == true && (contact1Id != null || contact2Id != null)) {
        sendFileEmail(
          emailTemplateName,
          fileName,
          fileContent,
          accountId,
          contact1Id,
          contact2Id,
          cv.ContentDocumentId
        );
      }

      String successMsg = (sendEmail == true && (contact1Id != null || contact2Id != null))
        ? fileName +
          ' generated and emailed successfully. Check sent Email under \'Activities\' and the file under \'Files\'.'
        : fileName + ' generated successfully. Check the file under \'Files\'.';
      return new LkgFileGenerateResult(true, successMsg);
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'LkgLicenseKeysFileService error: ' + e.getMessage());
      System.debug(LoggingLevel.ERROR, e.getStackTraceString());
      return new LkgFileGenerateResult(false, 'An unexpected error occurred: ' + e.getMessage());
    }
  }

  // ─── Shared email logic ───────────────────────────────────────────────────

  private static void sendFileEmail(
    String emailTemplateName,
    String fileName,
    String fileContent,
    Id accountId,
    Id contact1Id,
    Id contact2Id,
    Id contentDocumentId
  ) {
    // Note: setTemplateId() and setFileAttachments() cannot be used together in Apex —
    // Salesforce throws a runtime "Script-thrown exception" if both are set on the same message.
    // We query the template for subject/body and set them manually so the file can be attached.
    List<EmailTemplate> templates = [
      SELECT Id, Subject, HtmlValue, Body
      FROM EmailTemplate
      WHERE Name = :emailTemplateName
      LIMIT 1
    ];
    if (templates.isEmpty()) {
      throw new AuraHandledException('Email template not found: ' + emailTemplateName);
    }
    EmailTemplate tpl = templates[0];
    // Resolve Contact merge fields — use contact1 as primary; fall back to contact2 when contact1 is absent.
    Id primaryContactId = contact1Id != null ? contact1Id : contact2Id;
    Id secondaryContactId = contact1Id != null ? contact2Id : null;
    List<Contact> contacts = [SELECT FirstName, LastName FROM Contact WHERE Id = :primaryContactId LIMIT 1];
    String contactFirstName = contacts.isEmpty() ? '' : (contacts[0].FirstName ?? '');
    String contactLastName = contacts.isEmpty() ? '' : (contacts[0].LastName ?? '');

    String htmlBody = String.isNotBlank(tpl.HtmlValue) ? tpl.HtmlValue : null;
    String textBody = tpl.Body;
    if (htmlBody != null) {
      htmlBody = htmlBody
        .replace('{!Contact.FirstName}', contactFirstName)
        .replace('{!Contact.LastName}', contactLastName);
    }
    if (textBody != null) {
      textBody = textBody
        .replace('{!Contact.FirstName}', contactFirstName)
        .replace('{!Contact.LastName}', contactLastName);
    }

    Messaging.EmailFileAttachment emailAttachment = new Messaging.EmailFileAttachment();
    emailAttachment.setFileName(fileName);
    emailAttachment.setBody(Blob.valueOf(fileContent));
    emailAttachment.setContentType('text/plain');

    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
    email.setSubject(tpl.Subject);
    if (htmlBody != null) {
      email.setHtmlBody(htmlBody);
    } else {
      email.setPlainTextBody(textBody);
    }
    email.setTargetObjectId(primaryContactId);
    email.setWhatId(accountId);
    email.setSaveAsActivity(true);
    email.setBccAddresses(new List<String>{ UserInfo.getUserEmail() });
    email.setFileAttachments(new List<Messaging.EmailFileAttachment>{ emailAttachment });

    if (secondaryContactId != null) {
      List<Contact> cc = [SELECT Email FROM Contact WHERE Id = :secondaryContactId AND Email != NULL LIMIT 1];
      if (!cc.isEmpty()) {
        email.setCcAddresses(new List<String>{ cc[0].Email });
      }
    }

    // allOrNone=false: matches DefaultEmailSender behaviour — avoids exception in sandboxes
    // where email deliverability is restricted (NO_SINGLE_MAIL_PERMISSION).
    // Activity timeline entry is still created via setSaveAsActivity(true).
    emailSender.sendEmail(new List<Messaging.SingleEmailMessage>{ email });

    // Link the ContentDocument to the EmailMessage so it appears under CombinedAttachments.
    // setSaveAsActivity(true) inserts the EmailMessage synchronously in the same transaction.
    if (contentDocumentId != null) {
      List<EmailMessage> emailMessages = [
        SELECT Id
        FROM EmailMessage
        WHERE RelatedToId = :accountId
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];
      if (!emailMessages.isEmpty()) {
        insert new ContentDocumentLink(
          ContentDocumentId = contentDocumentId,
          LinkedEntityId = emailMessages[0].Id,
          ShareType = 'V',
          Visibility = 'AllUsers'
        );
      }
    }
  }
}