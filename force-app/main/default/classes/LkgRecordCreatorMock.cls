@isTest
public class LkgRecordCreatorMock implements System.StubProvider {
  public static Integer insertRecordCallCount = 0;
  public static Integer createRecordCallCount = 0;
  public static Integer createAttachmentCallCount = 0;
  public static SObject recordToInsert;
  public static License_Key__c createdLicenseKey;
  public static Boolean sendEmailValueOnCreate = true; // Default to true

  public Object handleMethodCall(
    Object stubbedObject,
    String stubbedMethodName,
    Type returnType,
    List<Type> argTypes,
    List<String> listOfParamNames,
    List<Object> args
  ) {
    switch on stubbedMethodName {
      when 'createLicenseKeyRecord' {
        createRecordCallCount++;

        // Create a License Key with Send_Email__c set based on the test configuration
        License_Key__c key = new License_Key__c(Send_Email__c = sendEmailValueOnCreate);
        createdLicenseKey = key;
        return key;
      }
      when 'insertLicenseKeyRecord' {
        insertRecordCallCount++;
        recordToInsert = (SObject) args.get(0);
        return recordToInsert;
      }
      when 'createAttachment' {
        createAttachmentCallCount++;
        Attachment att = new Attachment();
        att.Name = 'License Key';
        att.Body = Blob.valueOf('test');
        att.ContentType = 'text/plain';
        return att;
      }
      when else {
        return null;
      }
    }
  }

  // Reset method for test isolation
  public static void reset() {
    insertRecordCallCount = 0;
    createRecordCallCount = 0;
    createAttachmentCallCount = 0;
    recordToInsert = null;
    createdLicenseKey = null;
    sendEmailValueOnCreate = true;
  }
}