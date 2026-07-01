public with sharing class LkgMapperFactory {
  private class PayloadRouting {
    public String source; // 'hardware' or null for account-based
  }

  //Minimal hardware payload to determine silo for hardware-based requests
  private class HardwarePayloadRouting {
    public String source;
    public Id assetId;
  }

  //Main entry point - determines whether this is Account-based or hardware-based request
  public ILkgMapper getMapper(String payload) {
    // First, check if this is a hardware-based request
    PayloadRouting routing = (PayloadRouting) JSON.deserialize(payload, PayloadRouting.class);
    if (routing.source == 'hardware') {
      return getHardwareMapper(payload);
    } else {
      return getUiMapper(payload);
    }
  }

  // Get mapper for Account based key generation
  private ILkgMapper getUiMapper(String payload) {
    LkgMapperBase.UiPayload uiPayload = (LkgMapperBase.UiPayload) JSON.deserialize(
      payload,
      LkgMapperBase.UiPayload.class
    );

    switch on uiPayload.productData.silo {
      when 'clearswift' {
        return new LkgMapperClearswift();
      }
      when 'powertech', 'safestone', 'sgav', 'bytware', 'ccss' {
        return new LkgMapperPowertech();
      }
      when 'accessauth', 'securityscan' {
        return new LkgMapperAccessAuth();
      }
      when 'sgavx' {
        return new LkgMapperSgavx();
      }
      when 'legacyibm' {
        return new LkgMapperLegacyIbm();
      }
      when 'robot' {
        return new LkgMapperRobot();
      }
      when 'rsf' {
        return new LkgMapperRSF();
      }
      when 'docm' {
        return new LkgMapperDocM();
      }
      when 'sequel' {
        return new LkgMapperSequel();
      }
      when 'sequelweb' {
        return new LkgMapperSequelWeb();
      }
      when 'querybuilder' {
        return new LkgMapperSequelQueryBuilder();
      }
      when 'tqjava' {
        return new LkgMapperTQSurveyor();
      }
      when 'intermapper' {
        return new LkgMapperIntermapper();
      }
      when 'vityl' {
        return new LkgMapperVityl();
      }
      when 'halcyon' {
        if (uiPayload.productData.subSilo == 'ibm') {
          return new LkgMapperHalcyonIbm();
        }
        return null;
      }
      when 'ptmulti' {
        return new LkgMapperPtMulti();
      }
      when 'automate' {
        return new LkgMapperAutomate();
      }
      when 'fortra' {
        return new LkgMapperFortra();
      }
      when else {
        return null;
      }
    }
  }

  // Get mapper for hardware-based key generation
  private ILkgMapper getHardwareMapper(String payload) {
    HardwarePayloadRouting hwRouting = (HardwarePayloadRouting) JSON.deserialize(payload, HardwarePayloadRouting.class);

    if (hwRouting.assetId == null) {
      System.debug('Hardware mapper requested but assetId is null');
      return null;
    }
    return new LkgMapperHardwareBase();

    // Query the Asset to determine the silo
    // TODO: silos are determined from Asset -> Product2 -> LKG_Intersect -> LKG_Product__mdt -> LKG_Silo__r.DeveloperName
    //String silo = determineSiloFromAsset(hwRouting.assetId);

    //System.debug('Hardware mapper - determined silo: ' + silo);

    // TODO: Route to silo-specific hardware mappers as they are created
    // Example:
    // switch on silo {
    //   when 'clearswift' { return new LkgMapperClearswiftHardware(); }
    // }
    //System.debug('No hardware mapper found for silo: ' + silo);
    //return null;
  }

  /**
   * Determine silo from Asset
   * TODO: Implement actual logic based on Product2 or custom metadata
   * This might involve:
   * - Querying Product2 custom fields
   * - Querying LKG_Product__mdt based on Product2 relationship
   * - Other business logic
   */
  private String determineSiloFromAsset(Id assetId) {
    // Placeholder implementation
    // This will need to be replaced with actual business logic
    List<Asset> assets = [
      SELECT Product2.Name, ProductCode, Product2.Family
      FROM Asset
      WHERE Id = :assetId
      LIMIT 1
    ];

    if (assets.isEmpty()) {
      return null;
    }

    // TODO: Replace with actual silo determination logic
    // For example, this might involve:
    // 1. Query LKG_Product__mdt WHERE Internal_Product_Name__c = :assets[0].Product2.Name
    // 2. Get the LKG_Silo__r.DeveloperName from that metadata
    // 3. Return the silo name

    return null; // Placeholder - needs implementation
  }
}