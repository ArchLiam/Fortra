@isTest
private class LkgRequestControllerTest {
  private static LkgRequestController requestController;

  static {
    requestController = new LkgRequestController();
  }

  @isTest
  static void generateLicenseKey_shouldReturnLkgKeyGenResult() {
    // Given a request body
    // When the request controller is called
    Test.setMock(HttpCalloutMock.class, new LkgHttpCalloutMock());
    Test.startTest();
    LkgKeyGenResult result = requestController.generateLicenseKey('');
    Test.stopTest();

    //Then a response should be returned
    System.Assert.areNotEqual(null, result, 'Response should not be null.');
  }

  @isTest
  static void generateLicenseKey_shouldParseLicenseKey() {
    // Given a request body for non-SGAVX
    String requestBody = 'silo=powertech';

    // When the request controller is called
    Test.setMock(HttpCalloutMock.class, new LkgHttpCalloutMock());
    Test.startTest();
    LkgKeyGenResult result = requestController.generateLicenseKey(requestBody);
    Test.stopTest();

    // Then the response should be parsed correctly
    System.Assert.areEqual(result.licenseKey, 'default_key_string', 'License key should be default_key_string.');
  }

  @isTest
  static void generateLicenseKey_shouldReturnNullSerialNumber() {
    // Given a request body for non-Clearswift silo
    String requestBody = 'silo=powertech';

    // When the request controller is called
    Test.setMock(HttpCalloutMock.class, new LkgHttpCalloutMock());
    Test.startTest();
    LkgKeyGenResult result = requestController.generateLicenseKey(requestBody);
    Test.stopTest();

    // Then the serial number should be null
    System.Assert.areEqual(null, result.serialNumber, 'Serial number should be null for non-Clearswift silos.');
  }

  @isTest
  static void generateLicenseKeySgavx_shouldParseLicenseKey() {
    // Given a request body for SGAVX
    String requestBody = 'silo=sgavx';

    // When the request controller is called
    Test.setMock(HttpCalloutMock.class, new LkgHttpCalloutMock());
    Test.startTest();
    LkgKeyGenResult result = requestController.generateLicenseKey(requestBody);
    Test.stopTest();

    // Then the response should be parsed correctly
    System.Assert.areEqual(result.licenseKey, 'sgavx_key_string', 'License key should be sgavx_key_string.');
  }

  @isTest
  static void generateLicenseKeyClearswift_shouldParseSerialNumber() {
    // Given a request body for Clearswift
    String requestBody = 'silo=clearswift';
    // When the request controller is called
    Test.setMock(HttpCalloutMock.class, new LkgHttpCalloutMock());
    Test.startTest();
    LkgKeyGenResult result = requestController.generateLicenseKey(requestBody);
    Test.stopTest();

    // Then the serial number should be parsed correctly
    System.Assert.areEqual(
      result.serialNumber,
      'clearswift_serial_number',
      'Serial number should be clearswift_serial_number for Clearswift silo.'
    );
  }

  @isTest
  static void generateLicenseKey_shouldSetRequestParameters() {
    // Given a request body
    String requestBody = 'silo=powertech&version=310&endLparNumber=99999&featureCode=12345';

    // When the request controller is called
    Test.setMock(HttpCalloutMock.class, new LkgHttpCalloutMock());
    Test.startTest();
    LkgKeyGenResult result = requestController.generateLicenseKey(requestBody);
    Test.stopTest();

    // Then the request parameters should be set correctly
    System.Assert.areEqual(result.requestParameters, requestBody, 'Request parameters should be set correctly.');
  }

  @isTest
  static void generateLicenseKey_shouldSetResponseMessage() {
    // Given a request body
    String requestBody = 'silo=powertech';

    // When the request controller is called
    Test.setMock(HttpCalloutMock.class, new LkgHttpCalloutMock());
    Test.startTest();
    LkgKeyGenResult result = requestController.generateLicenseKey(requestBody);
    Test.stopTest();

    // Then the response message should be set correctly
    System.Assert.areEqual(
      result.responseMessage,
      '{"status":"0","output":["default_key_string"]}',
      'Response message should be set correctly.'
    );
  }

  @isTest
  static void generateLicenseKey_shouldThrowExceptionOnHttpError() {
    // Given a request body and a mock that returns HTTP error
    String requestBody = 'silo=powertech';
    Test.setMock(HttpCalloutMock.class, new LkgHttpCalloutMockHttpError());

    // When the request controller is called
    Test.startTest();
    try {
      requestController.generateLicenseKey(requestBody);
      System.Assert.fail('Should have thrown KeyGenException');
    } catch (LkgKeyGenResponse.KeyGenException e) {
      // Then a KeyGenException should be thrown
      System.Assert.isTrue(e.getMessage().contains('keygen API HTTP error'), 'Should contain HTTP error message.');
    }
    Test.stopTest();
  }

  @isTest
  static void generateLicenseKey_shouldThrowExceptionOnApiError() {
    // Given a request body and a mock that returns API error
    String requestBody = 'silo=powertech';
    Test.setMock(HttpCalloutMock.class, new LkgHttpCalloutMockApiError());

    // When the request controller is called
    Test.startTest();
    try {
      requestController.generateLicenseKey(requestBody);
      System.Assert.fail('Should have thrown KeyGenException');
    } catch (LkgKeyGenResponse.KeyGenException e) {
      // Then a KeyGenException should be thrown
      System.Assert.isTrue(e.getMessage().contains('keygen API error'), 'Should contain API error message.');
    }
    Test.stopTest();
  }

  @isTest
  static void generateLicenseKey_shouldThrowExceptionOnApiErrorWithoutOutput() {
    // Given a request body and a mock that returns API error without output
    String requestBody = 'silo=powertech';
    Test.setMock(HttpCalloutMock.class, new LkgHttpCalloutMockApiErrorNoOutput());

    // When the request controller is called
    Test.startTest();
    try {
      requestController.generateLicenseKey(requestBody);
      System.Assert.fail('Should have thrown KeyGenException');
    } catch (LkgKeyGenResponse.KeyGenException e) {
      // Then a KeyGenException should be thrown with unknown error message
      System.Assert.isTrue(e.getMessage().contains('Unknown error'), 'Should contain Unknown error message.');
    }
    Test.stopTest();
  }

  // Mock classes for error scenarios
  public class LkgHttpCalloutMockHttpError implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(500);
      response.setBody('{"status":"0","output":["error"]}');
      return response;
    }
  }

  public class LkgHttpCalloutMockApiError implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      LkgRequestController.ApiResponse apiResponse = new LkgRequestController.ApiResponse();
      apiResponse.status = '1';
      apiResponse.output = new List<String>{ 'API Error Message' };
      response.setBody(JSON.serialize(apiResponse));
      return response;
    }
  }

  public class LkgHttpCalloutMockApiErrorNoOutput implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest request) {
      HttpResponse response = new HttpResponse();
      response.setStatusCode(200);
      LkgRequestController.ApiResponse apiResponse = new LkgRequestController.ApiResponse();
      apiResponse.status = '1';
      apiResponse.output = new List<String>();
      response.setBody(JSON.serialize(apiResponse));
      return response;
    }
  }
}