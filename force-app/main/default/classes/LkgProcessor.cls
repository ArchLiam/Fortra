public with sharing class LkgProcessor {
  public class LicenseKeyRequest {
    public String silo;
    public String subSilo;
    public String productCode;
    public String version;
    public String hardwareId;
    public String lkgProductIdentifierName;
    public String internalProductName;
    public String externalProductName;
    public Map<Integer, Object> dynamicParameters;
  }

  private LkgMapperClearswift mapper;
  private LkgMapperFactory mapperFactory;
  private LkgRequestBuilderFactory requestBuilderFactory;
  private LkgRequestController requestController;
  private LkgRecordCreatorFactory recordCreatorFactory;

  public LkgProcessor(
    LkgMapperFactory mapperFactory,
    LkgRequestBuilderFactory requestBuilderFactory,
    LkgRequestController requestController,
    LkgRecordCreatorFactory recordCreatorFactory
  ) {
    this.mapperFactory = mapperFactory;
    this.requestBuilderFactory = requestBuilderFactory;
    this.requestController = requestController;
    this.recordCreatorFactory = recordCreatorFactory;
  }

  public LkgKeyGenResponse Execute(String payload) {
    ILkgMapper mapper = mapperFactory.getMapper(payload);

    // Check if the mapper is valid
    if (mapper == null) {
      return LkgKeyGenResponse.error('Invalid Silo Mapper or Silo is not defined in LkgMapperFactory');
    }

    //log mapper name
    System.debug(LoggingLevel.DEBUG, 'Mapper: ' + mapper);

    LkgRequestBuilderBase.KeyData keyData = mapper.mapPayloadToKeyData(payload);

    ILkgRequestBuilder builder = requestBuilderFactory.getRequestBuilder(keyData.Silo, keyData.subSilo);

    if (builder == null) {
      return LkgKeyGenResponse.error(
        'Invalid Request Builder or Request Builder is not defined in LkgRequestBuilderFactory'
      );
    }

    //log request builder name
    System.debug(LoggingLevel.DEBUG, 'Request Builder: ' + builder);

    LkgProcessor.LicenseKeyRequest request = builder.buildRequest(keyData);

    System.debug(LoggingLevel.DEBUG, 'License Key Request: ' + JSON.serializePretty(request));

    String body = 'silo=' + EncodingUtil.urlEncode(request.silo, 'UTF-8');

    for (Integer i = 0; i < request.dynamicParameters.size(); i++) {
      String paramValue = String.valueOf(request.dynamicParameters.get(i));
      body += '&argv=' + EncodingUtil.urlEncode(paramValue, 'UTF-8');
    }

    // Generate license key from keygen service
    LkgKeyGenResult keyGenResult = requestController.generateLicenseKey(body);

    //log keygen result
    System.debug(LoggingLevel.DEBUG, 'KeyGen Result: ' + JSON.serializePretty(keyGenResult));

    keyGenResult.applyTo(keyData);

    ILkgRecordCreator recordCreator = recordCreatorFactory.getRecordCreator(keyData.Silo, keyData.subSilo);

    // Check if the record creator is valid
    if (recordCreator == null) {
      return LkgKeyGenResponse.error(
        'Invalid Record Creator or Record Creator is not defined in LkgRecordCreatorFactory'
      );
    }

    //log record creator name
    System.debug(LoggingLevel.DEBUG, 'Record Creator: ' + recordCreator);

    try {
      // generate License Key record
      License_Key__c licenseKey = recordCreator.createLicenseKeyRecord(keyData);

      // Temporarily set Send_Email__c to false to prevent trigger from firing until AFTER the attachment is created.
      // This avoids timing issues where the email is sent before the attachment exists.
      Boolean shouldSendEmail = licenseKey.Send_Email__c;
      licenseKey.Send_Email__c = false;

      recordCreator.insertLicenseKeyRecord(licenseKey);

      // log license key record
      System.debug(LoggingLevel.DEBUG, 'License Key Record: ' + JSON.serializePretty(licenseKey));

      if (keyData.createLicenseKeyFile != null && keyData.createLicenseKeyFile) {
        Attachment attachment = recordCreator.createAttachment(licenseKey);
        if (attachment != null) {
          recordCreator.insertLicenseKeyRecord(attachment);
          System.debug(LoggingLevel.DEBUG, 'Attachment created and inserted: ' + attachment.Name);
        }
      }

      // Attachment is created, trigger the email if it was requested
      if (shouldSendEmail) {
        licenseKey.Send_Email__c = true;
        update licenseKey;
      }

      return LkgKeyGenResponse.success(keyData.LicenseKey, licenseKey.Id);
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'Error: ' + e.getMessage());
      return LkgKeyGenResponse.error('An unexpected error occurred: ' + e.getMessage());
    }
  }
}