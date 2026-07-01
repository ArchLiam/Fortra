@isTest
public with sharing class LkgRecordCreatorFactoryMock implements System.StubProvider {
  public static Integer getRecordCreatorCallCount = 0;

  public Object handleMethodCall(
    Object stubbedObject,
    String stubbedMethodName,
    Type returnType,
    List<Type> argTypes,
    List<String> listOfParamNames,
    List<Object> args
  ) {
    switch on stubbedMethodName {
      when 'getRecordCreator' {
        getRecordCreatorCallCount++;

        String siloName = (String) args.get(0);

        switch on siloName {
          when 'clearswift' {
            return (LkgRecordCreatorClearswift) Test.createStub(
              LkgRecordCreatorClearswift.class,
              new LkgRecordCreatorMock()
            );
          }
          when 'powertech', 'safestone', 'policyminder' {
            return (LkgRecordCreatorPowerTech) Test.createStub(
              LkgRecordCreatorPowerTech.class,
              new LkgRecordCreatorMock()
            );
          }
          when 'accessauth', 'securityscan' {
            return (LkgRecordCreatorAccessAuth) Test.createStub(
              LkgRecordCreatorAccessAuth.class,
              new LkgRecordCreatorMock()
            );
          }
          when 'sgavx' {
            return (LkgRecordCreatorSgavx) Test.createStub(LkgRecordCreatorSgavx.class, new LkgRecordCreatorMock());
          }
          when 'legacyibm' {
            return (LkgRecordCreatorLegacyIbm) Test.createStub(
              LkgRecordCreatorLegacyIbm.class,
              new LkgRecordCreatorMock()
            );
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