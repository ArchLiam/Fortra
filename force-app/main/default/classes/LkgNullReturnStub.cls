/**
 * Minimal stub provider that returns null for every method call.
 * Used in LkgProcessorHardwareKeysTest to simulate factory methods that return no result.
 */
@isTest
public class LkgNullReturnStub implements System.StubProvider {
  public Object handleMethodCall(
    Object stubbedObject,
    String stubbedMethodName,
    Type returnType,
    List<Type> argTypes,
    List<String> listOfParamNames,
    List<Object> args
  ) {
    return null;
  }
}