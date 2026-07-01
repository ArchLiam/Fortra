/**
 * Service class for handling email attachment operations
 * Retrieves file attachments from License Key records for email sending
 */
public class EmailAttachmentService {
  /**
   * Get file attachment for a License Key record
   * Checks both old-style Attachments and modern ContentDocuments
   * @param licenseKeyId The License Key record ID
   * @return EmailFileAttachment object ready to attach to email, or null if no file found
   */
  public static Messaging.EmailFileAttachment getAttachmentForLicenseKey(Id licenseKeyId) {
    System.debug('=== EmailAttachmentService.getAttachmentForLicenseKey START ===');
    System.debug('License Key ID: ' + licenseKeyId);

    // First try old-style Attachments (most common for programmatically created files)
    List<Attachment> attachments = [
      SELECT Id, Name, Body, ContentType
      FROM Attachment
      WHERE ParentId = :licenseKeyId
      ORDER BY CreatedDate
      LIMIT 1
    ];

    System.debug('Found ' + attachments.size() + ' Attachments for License Key: ' + licenseKeyId);

    if (!attachments.isEmpty()) {
      System.debug(
        'Attachment Name: ' +
          attachments[0].Name +
          ', ContentType: ' +
          attachments[0].ContentType +
          ', Body Size: ' +
          attachments[0].Body?.size() +
          ' bytes'
      );

      Messaging.EmailFileAttachment emailAttachment = new Messaging.EmailFileAttachment();
      emailAttachment.setFileName(attachments[0].Name);
      emailAttachment.setBody(attachments[0].Body);
      if (String.isNotBlank(attachments[0].ContentType)) {
        emailAttachment.setContentType(attachments[0].ContentType);
      }
      System.debug('Email file attachment created successfully from Attachment');
      return emailAttachment;
    } else {
      System.debug('No Attachments found for License Key: ' + licenseKeyId);
    }

    System.debug('=== EmailAttachmentService.getAttachmentForLicenseKey END ===');
    return null;
  }

  /**
   * Get attachment IDs for a License Key record
   * Used for setEntityAttachments() to make attachments visible in Salesforce UI
   * @param licenseKeyId The License Key record ID
   * @return List of Attachment IDs
   */
  public static List<String> getAttachmentIdsForLicenseKey(Id licenseKeyId) {
    List<String> attachmentIds = new List<String>();

    // Query for Attachment IDs
    List<Attachment> attachments = [
      SELECT Id
      FROM Attachment
      WHERE ParentId = :licenseKeyId
      ORDER BY CreatedDate
    ];

    System.debug('Found ' + attachments.size() + ' Attachment(s)');

    for (Attachment att : attachments) {
      attachmentIds.add(att.Id);
    }
    return attachmentIds;
  }
}