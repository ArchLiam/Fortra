@isTest
public class LkgRequestBuilderFactoryMock implements System.StubProvider {
  public static Integer buildRequestBuilderFactoryCallCount = 0;

  public Object handleMethodCall(
    Object stubbedObject,
    String stubbedMethodName,
    Type returnType,
    List<Type> argTypes,
    List<String> listOfParamNames,
    List<Object> args
  ) {
    switch on stubbedMethodName {
      when 'getRequestBuilder' {
        buildRequestBuilderFactoryCallCount++;

        String siloName = (String) args.get(0);

        switch on siloName {
          when 'clearswift' {
            return (LkgRequestBuilderClearswift) Test.createStub(
              LkgRequestBuilderClearswift.class,
              new LkgRequestBuilderMock()
            );
          }
          when 'powertech', 'safestone', 'policyminder' {
            return (LkgRequestBuilderPowerTech) Test.createStub(
              LkgRequestBuilderPowerTech.class,
              new LkgRequestBuilderMock()
            );
          }
          when 'sgavx' {
            return (LkgRequestBuilderSgavx) Test.createStub(LkgRequestBuilderSgavx.class, new LkgRequestBuilderMock());
          }
          when else {
            return null;
          }
        }
      }
      when else {
        return null;
      }
    }
  }
}