@isTest
public class LkgMapperMock implements System.StubProvider {
  public static Integer mapPayloadCallCount = 0;

  public Object handleMethodCall(
    Object stubbedObject,
    String stubbedMethodName,
    Type returnType,
    List<Type> argTypes,
    List<String> listOfParamNames,
    List<Object> args
  ) {
    switch on stubbedMethodName {
      when 'mapPayloadToKeyData' {
        mapPayloadCallCount++;

        string silo = '';

        for (integer i = 0; i < listOfParamNames.size(); i++) {
          if (listOfParamNames.get(i) == 'payload') {
            System.debug(LoggingLevel.DEBUG, 'uiPayload: ' + args.get(i).toString());

            LkgMapperBase.UiPayload uiPayload = (LkgMapperBase.UiPayload) JSON.deserialize(
              args.get(i).toString(),
              LkgMapperBase.UiPayload.class
            );
            silo = uiPayload.productData.silo;
          }
        }

        switch on silo {
          when 'sgavx' {
            LkgRequestBuilderSgavx.SgavxKeyData sgavxKeyData = new LkgRequestBuilderSgavx.SgavxKeyData();
            sgavxKeyData.Silo = 'sgavx';
            sgavxKeyData.subSilo = null;
            sgavxKeyData.createLicenseKeyFile = true;

            return sgavxKeyData;
          }
          when else {
            LkgRequestBuilderClearswift.ClearswiftKeyData keyData = new LkgRequestBuilderClearswift.ClearswiftKeyData();
            keyData.Silo = 'clearswift';
            keyData.subSilo = null;

            return keyData;
          }
        }
      }
      when else {
        return null;
      }
    }
  }
}