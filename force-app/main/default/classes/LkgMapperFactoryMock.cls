@isTest
public class LkgMapperFactoryMock implements System.StubProvider {
  public static Integer mapperFactoryCallCount = 0;

  public Object handleMethodCall(
    Object stubbedObject,
    String stubbedMethodName,
    Type returnType,
    List<Type> argTypes,
    List<String> listOfParamNames,
    List<Object> args
  ) {
    switch on stubbedMethodName {
      when 'getMapper' {
        mapperFactoryCallCount++;

        String payloadJson = (String) args.get(0);
        LkgMapperBase.UiPayload uiPayload = (LkgMapperBase.UiPayload) JSON.deserialize(
          payloadJson,
          LkgMapperBase.UiPayload.class
        );

        switch on uiPayload.productData.silo {
          when else {
            return (LkgMapperClearswift) Test.createStub(LkgMapperClearswift.class, new LkgMapperMock());
          }
        }
      }
      when else {
        return null;
      }
    }
  }
}