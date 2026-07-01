public with sharing class LkgRecordCreatorFactory {
  public ILkgRecordCreator getRecordCreator(string silo) {
    return getRecordCreator(silo, null);
  }
  public ILkgRecordCreator getRecordCreator(String silo, String subSilo) {
    switch on silo {
      when 'clearswift' {
        return new LkgRecordCreatorClearswift();
      }
      when 'powertech', 'safestone', 'sgav', 'bytware', 'ccss' {
        return new LkgRecordCreatorPowertech();
      }
      when 'accessauth', 'securityscan' {
        return new LkgRecordCreatorAccessAuth();
      }
      when 'sgavx' {
        return new LkgRecordCreatorSgavx();
      }
      when 'legacyibm' {
        return new LkgRecordCreatorLegacyIbm();
      }
      when 'robot' {
        return new LkgRecordCreatorRobot();
      }
      when 'rsf' {
        return new LkgRecordCreatorRSF();
      }
      when 'docm' {
        return new LkgRecordCreatorDocM();
      }
      when 'sequel' {
        return new LkgRecordCreatorSequel();
      }
      when 'sequelweb' {
        return new LkgRecordCreatorSequelWeb();
      }
      when 'querybuilder' {
        return new LkgRecordCreatorSequelQueryBuilder();
      }
      when 'tqjava' {
        return new LkgRecordCreatorTQSurveyor();
      }
      when 'intermapper' {
        return new LkgRecordCreatorIntermapper();
      }
      when 'vityl' {
        return new LkgRecordCreatorVityl();
      }
      when 'halcyon' {
        if (subSilo == 'ibm') {
          return new LkgRecordCreatorHalcyonIbm();
        }
        return null;
      }
      when 'ptmulti' {
        return new LkgRecordCreatorPtMulti();
      }
      when 'automate' {
        return new LkgRecordCreatorAutomate();
      }
      when 'fortra' {
        return new LkgRecordCreatorFortra();
      }
      when else {
        return null;
      }
    }
  }
}