public with sharing class LkgRequestBuilderFactory {
  public ILkgRequestBuilder getRequestBuilder(String siloName) {
    return getRequestBuilder(siloName, null);
  }

  public ILkgRequestBuilder getRequestBuilder(String siloName, String subSiloName) {
    switch on siloName {
      when 'clearswift' {
        return new LkgRequestBuilderClearswift();
      }
      when 'powertech', 'safestone', 'sgav', 'bytware', 'ccss' {
        return new LkgRequestBuilderPowertech();
      }
      when 'accessauth', 'securityscan' {
        return new LkgRequestBuilderAccessAuth();
      }
      when 'sgavx' {
        return new LkgRequestBuilderSgavx();
      }
      when 'legacyibm' {
        return new LkgRequestBuilderLegacyIbm();
      }
      when 'ptmulti' {
        return new LkgRequestBuilderPtMulti();
      }
      when 'tqjava' {
        return new LkgRequestBuilderTQSurveyor();
      }
      when 'rsf' {
        return new LkgRequestBuilderRSF();
      }
      when 'robot' {
        return new LkgRequestBuilderRobot();
      }
      when 'docm' {
        return new LkgRequestBuilderDocM();
      }
      when 'sequel' {
        return new LkgRequestBuilderSequel();
      }
      when 'querybuilder' {
        return new LkgRequestBuilderSequelQueryBuilder();
      }
      when 'sequelweb' {
        return new LkgRequestBuilderSequelWeb();
      }
      when 'halcyon' {
        if (subSiloName == 'ibm') {
          return new LkgRequestBuilderHalcyonIbm();
        }
        return null;
      }
      when 'intermapper' {
        return new LkgRequestBuilderIntermapper();
      }
      when 'vityl' {
        return new LkgRequestBuilderVityl();
      }
      when 'automate' {
        return new LkgRequestBuilderAutomate();
      }
      when 'fortra' {
        return new LkgRequestBuilderFortra();
      }
      when else {
        return null;
      }
    }
  }
}