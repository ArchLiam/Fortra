@isTest
public class LkgRequestBuilderMock implements System.StubProvider {
  public static Integer buildRequestCallCount = 0;

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
      when 'buildRequest' {
        buildRequestCallCount++;

        string silo = '';

        LkgProcessor.LicenseKeyRequest licenseKeyRequest = new LkgProcessor.LicenseKeyRequest();
        Map<Integer, Object> dynamicParameters = new Map<Integer, Object>();

        for (integer i = 0; i < listOfParamNames.size(); i++) {
          if (listOfParamNames.get(i) == 'keydata') {
            LkgRequestBuilderBase.KeyData keyData = (LkgRequestBuilderBase.KeyData) args.get(i);
            silo = keyData.Silo;
          }
        }

        switch on silo {
          when 'clearswift' {
            dynamicParameters.put(LkgRequestBuilderClearswift.ClearswiftParameters.CompanyName.ordinal(), 'Test Co.');
            dynamicParameters.put(LkgRequestBuilderClearswift.ClearswiftParameters.ExpirationType.ordinal(), '1');
            dynamicParameters.put(
              LkgRequestBuilderClearswift.ClearswiftParameters.ExpirationDate.ordinal(),
              '3000-01-01'
            );
            dynamicParameters.put(LkgRequestBuilderClearswift.ClearswiftParameters.ProductCode.ordinal(), '24');
            dynamicParameters.put(LkgRequestBuilderClearswift.ClearswiftParameters.LanguageIndex.ordinal(), '0');
            dynamicParameters.put(LkgRequestBuilderClearswift.ClearswiftParameters.VersionIndex.ordinal(), '0');
            dynamicParameters.put(LkgRequestBuilderClearswift.ClearswiftParameters.ServerCount.ordinal(), '0');
            dynamicParameters.put(LkgRequestBuilderClearswift.ClearswiftParameters.UserCount.ordinal(), '380');
            dynamicParameters.put(LkgRequestBuilderClearswift.ClearswiftParameters.Elements.ordinal(), '1');

            licenseKeyRequest.dynamicParameters = dynamicParameters;
          }
          when else {
          }
        }

        licenseKeyRequest.silo = silo;
        licenseKeyRequest.subSilo = null;
        licenseKeyRequest.dynamicParameters = dynamicParameters;

        return licenseKeyRequest;
      }
      when else {
        return null;
      }
    }
  }
}