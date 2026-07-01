@isTest
public class LkgRequestControllerMock implements System.StubProvider {
  public static Integer generateLicenseKeyCallCount = 0;

  public Object handleMethodCall(
    Object stubbedObject,
    String stubbedMethodName,
    Type returnType,
    List<Type> argTypes,
    List<String> listOfParamNames,
    List<Object> args
  ) {
    for (integer i = 0; i < listOfParamNames.size(); i++) {
      System.debug('parameter name: ' + listOfParamNames.get(i));
      System.debug('  parameter type: ' + argTypes.get(i).getName());
    }

    switch on stubbedMethodName {
      when 'generateLicenseKey' {
        generateLicenseKeyCallCount++;

        LkgKeyGenResult keyGenResult = new LkgKeyGenResult(
          'mock_license_key',
          'mock_serial_number',
          'mock_request_parameters',
          'mock_response_message'
        );
        return keyGenResult;
      }
      when else {
        return null;
      }
    }
  }
}