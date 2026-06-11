# LKG — License Key Generation Framework (Apex)

## Overview

**LKG = License Key Generation.** This `Lkg*` family (~141 classes) is a self-contained, custom-built
subsystem that generates software **license keys** for Fortra's many acquired product brands ("silos") and
persists them as `License_Key__c` records. It is independent of the Revenue Cloud / RCA pricing stack — it is
the engineering side of the business (provisioning license keys for products customers bought), driven from an
LWC/Aura UI and, for some products, from hardware-asset requests.

The framework is a **strategy + factory + pipeline** design. A single orchestrator (`LkgProcessor`) runs four
stages, each dispatched per-silo by a factory:

```
payload (JSON)
  → Mapper          parse UI/hardware payload → KeyData          (LkgMapper*, LkgMapperFactory)
  → RequestBuilder  build urlencoded keygen-API request body     (LkgRequestBuilder*, LkgRequestBuilderFactory)
  → RequestController  HTTP callout to `callout:keygen_api`       (LkgRequestController) → LkgKeyGenResult
  → RecordCreator   create + insert License_Key__c (+ Attachment) (LkgRecordCreator*, LkgRecordCreatorFactory)
  → LkgKeyGenResponse (success/error, returned to the LWC)
```

Each of the three per-silo families (**Mapper**, **RequestBuilder**, **RecordCreator**) has the same shape:
a `*Base` virtual class (shared logic + `KeyData`/`License_Key__c` field mapping), a `*Factory` that routes by
silo/sub-silo string, per-product subclasses that override only the silo-specific bits, and an interface
(`ILkgMapper`, `ILkgRequestBuilder`, `ILkgRecordCreator` — those interfaces live outside this list). The whole
thing is heavily unit-tested via `System.StubProvider` mocks so each stage can be tested in isolation.

> Silo routing strings (used by all three factories): `clearswift`, `powertech`/`safestone`/`sgav`/`bytware`/`ccss`
> (all → Powertech), `accessauth`/`securityscan` (→ AccessAuth), `sgavx`, `legacyibm`, `robot`, `rsf`, `docm`,
> `sequel`, `querybuilder`, `sequelweb`, `tqjava` (→ TQSurveyor), `intermapper`, `vityl`, `ptmulti`,
> `halcyon`+subSilo `ibm` (→ HalcyonIbm), `automate`/`bpa` (→ Automate), `fortra`. **Note the silo string is not
> always the class name** — several strings collapse onto one product class.

---

## Core Orchestration & Domain Types

| Class | Role | Purpose / key methods |
|---|---|---|
| `LkgProcessor` | **Orchestrator** (service) | Heart of the pipeline. Ctor takes the 4 factories/controller (DI-friendly). `Execute(payload)` runs Mapper→RequestBuilder→Controller→RecordCreator, builds the `silo=…&argv=…` urlencoded body, returns `LkgKeyGenResponse`. Inner `LicenseKeyRequest` is the request DTO. **Load-bearing gotcha:** it sets `Send_Email__c=false` before insert, creates the attachment, *then* flips email back on with an `update` — so the notification email fires only after the key file Attachment exists. |
| `LkgRequestController` | **Integration / HTTP callout** | `generateLicenseKey(body)` POSTs to named credential `callout:keygen_api` (form-urlencoded), validates HTTP 200 + API `status=='0'`, parses license key / serial out of the response. Returns `LkgKeyGenResult`. Inner `ApiResponse {status, output}` is the keygen API contract. Throws `LkgKeyGenResponse.KeyGenException` on any error. |
| `LkgKeyGenResult` | **DTO (callout result)** | Immutable holder of `licenseKey`, `serialNumber`, `requestParameters`, `responseMessage`. `applyTo(keyData)` copies these back onto the `KeyData` before record creation. |
| `LkgKeyGenResponse` | **DTO (UI response)** | `@AuraEnabled` result returned to the LWC: `isSuccess`, `message`, `generatedKey`, `licenseKeyId`. Static factories `success(...)` / `error(...)`. Declares the framework-wide `KeyGenException`. |
| `LkgTermPermRangeChecker` | **Utility** | Parses a `permTermVersionRange` JSON blob into a `PermTermVersionRange` struct (min/max version + modification) used to decide Permanent vs Term key types by product release. Returns `null` on blank/parse failure (fail-soft). |
| `LkgUiController` | **Aura/LWC controller** | All `@AuraEnabled(cacheable=true)` getters that drive the key-gen UI off `LKG_*__mdt` custom metadata: `getSolutionGroups`, `getSolutionCategoriesByGroup`, `getSolutionsByCategory`, `getProductsBySolution`, `getLkgProductByName`, `getKeyTypesBySilo` (Global + Silo-scoped), `getUIFieldsByProduct` (Global/Silo/Product scope filtering + custom sort), `getUIFieldOptions`, `getContactsByAccountId`. This is the metadata-driven config layer of LKG. |

---

## Mapper Family — payload → KeyData

Parses the inbound JSON payload (UI or hardware) into a `LkgRequestBuilderBase.KeyData`. Subclasses override
`createKeyDataInstance()` (to return a silo-specific KeyData subclass) and `mapSiloFields()` (silo-specific
attributes). `LkgMapperFactory` chooses UI vs hardware path by the payload's `source` field, then routes by silo.

| Class | Role | Purpose / key methods |
|---|---|---|
| `LkgMapperBase` | **Base (virtual)** | Implements `ILkgMapper`. `mapPayloadToKeyData(payload)` deserializes the `UiPayload`, runs `mapBaseFields` + `mapSiloFields`. Defines the shared `UiPayload` and `ProductData` inner DTOs (account/contacts/expiration/keyType/attributes + silo/brand/product metadata). |
| `LkgMapperFactory` | **Factory (router)** | `getMapper(payload)` — splits hardware-based vs account/UI-based requests (inner `PayloadRouting`/`HardwarePayloadRouting`), then `switch on silo` to instantiate the right mapper. |
| `LkgMapperAccessAuth` | Per-silo mapper | AccessAuth / Security Scanner. |
| `LkgMapperAutomate` | Per-silo mapper | Automate / BPA. Returns `AutomateKeyData`; computes **Points** via `AutomatePointsBuilderContext` + `LkgAutomatePointsBuilderFactory`, parses an actions string. Tier/version-aware. |
| `LkgMapperClearswift` | Per-silo mapper | Clearswift (email/web security). The default example silo in tests. |
| `LkgMapperDocM` | Per-silo mapper | Document Management. |
| `LkgMapperFortra` | Per-silo mapper | Fortra-branded product. Computes tiers/IPs/webApps/containers/capabilities/RNA-count and a license-format version, with `@TestVisible` default constants (`B0`/`C0`/`D1`…). |
| `LkgMapperHalcyonIbm` | Per-silo mapper | Halcyon (IBM sub-silo). |
| `LkgMapperIntermapper` | Per-silo mapper | Intermapper (network monitoring). |
| `LkgMapperLegacyIbm` | Per-silo mapper | Legacy IBM-i products. |
| `LkgMapperPowertech` | Per-silo mapper | Powertech (also serves safestone/sgav/bytware/ccss silos). |
| `LkgMapperPtMulti` | Per-silo mapper | Powertech multi-product / bundle requests. |
| `LkgMapperRSF` | Per-silo mapper | RSF product line. |
| `LkgMapperRobot` | Per-silo mapper | Robot (IBM-i automation). |
| `LkgMapperSequel` | Per-silo mapper | Sequel (data access/reporting). |
| `LkgMapperSequelQueryBuilder` | Per-silo mapper | Sequel "querybuilder" silo variant. |
| `LkgMapperSequelWeb` | Per-silo mapper | Sequel Web variant. |
| `LkgMapperSgavx` | Per-silo mapper | SGAVX (the one product that generates an XML license **Attachment** — see RecordCreatorSgavx). |
| `LkgMapperTQSurveyor` | Per-silo mapper | TQ/Surveyor (`tqjava` silo). |
| `LkgMapperVityl` | Per-silo mapper | Vityl (capacity/performance). |

---

## RequestBuilder Family — KeyData → keygen-API request

Turns a `KeyData` into a `LkgProcessor.LicenseKeyRequest` with an ordered `dynamicParameters` map that becomes the
positional `&argv=` arguments sent to the keygen service. Each silo defines its own parameter **enum** (positional
contract with the external keygen API — order matters) and overrides `GetDynamicParameters()` / sometimes
`GetSiloName()`. Subclasses also declare silo-specific `KeyData` subclasses (e.g. `AutomateKeyData`, `SequelKeyData`).

| Class | Role | Purpose / key methods |
|---|---|---|
| `LkgRequestBuilderBase` | **Base (virtual)** | Implements `ILkgRequestBuilder`. Defines the canonical `KeyData` struct (~30 fields) and key-type constants (`Permanent`/`Generic`/`Specific_Temporary`). `buildRequest()` assembles the request; `GetDynamicParameters()`/`GetSiloName()` are the override points. |
| `LkgRequestBuilderFactory` | **Factory (router)** | `getRequestBuilder(silo[, subSilo])` — `switch on silo`; halcyon dispatches on `subSilo=='ibm'`. |
| `LkgRequestBuilderAccessAuth` | Per-silo builder | AccessAuth/SecurityScan parameter mapping. |
| `LkgRequestBuilderAutomate` | Per-silo builder | Automate/BPA. `AutomateParameters` enum; `AutomateKeyData`; helpers `getVersion(release, mod)`, `getLicenseKeyType()`; emits Points. |
| `LkgRequestBuilderClearswift` | Per-silo builder | `ClearswiftParameters` enum; company name + expiration type/date + elements; `expirationDefault` = year 3000 sentinel for permanent keys. |
| `LkgRequestBuilderDocM` | Per-silo builder | Document Management. |
| `LkgRequestBuilderFortra` | Per-silo builder | Fortra product parameter mapping. |
| `LkgRequestBuilderHalcyonIbm` | Per-silo builder | Halcyon IBM. |
| `LkgRequestBuilderIntermapper` | Per-silo builder | Intermapper. |
| `LkgRequestBuilderLegacyIbm` | Per-silo builder | Legacy IBM-i. |
| `LkgRequestBuilderPowerTech` | Per-silo builder | Powertech (note camelCase **`PowerTech`** in this family — differs from Mapper/RecordCreator `Powertech`). |
| `LkgRequestBuilderPtMulti` | Per-silo builder | Powertech multi-product. |
| `LkgRequestBuilderRSF` | Per-silo builder | RSF. |
| `LkgRequestBuilderRobot` | Per-silo builder | Robot. |
| `LkgRequestBuilderSequel` | Per-silo builder | `SequelParameters` enum; `SequelKeyData`; version-index + license-key-type logic; `MIN_RELEASE_OF_QUERY_AND_REPORT_WRITER='25'`. |
| `LkgRequestBuilderSequelQueryBuilder` | Per-silo builder | `SequelQueryBuilderParameters` enum; `SequelQueryBuilderKeyData`; tier-points computation. |
| `LkgRequestBuilderSequelWeb` | Per-silo builder | `SequelWebKeyData` (carries Release/Modification). |
| `LkgRequestBuilderSgavx` | Per-silo builder | SGAVX. |
| `LkgRequestBuilderTQSurveyor` | Per-silo builder | TQ/Surveyor (`tqjava`). |
| `LkgRequestBuilderVityl` | Per-silo builder | Vityl. |

---

## RecordCreator Family — KeyData → License_Key__c

Maps the finalized `KeyData` (now carrying the generated key) onto a `License_Key__c` SObject, inserts it, and
optionally builds an `Attachment` (the license file). Subclasses override only `mapSiloFields()` for
silo-specific columns (e.g. `Points__c`, `Modification__c`, `Release__c`) and, rarely, `createAttachment()`.

| Class | Role | Purpose / key methods |
|---|---|---|
| `LkgRecordCreatorBase` | **Base (virtual)** | Implements `ILkgRecordCreator`. `createLicenseKeyRecord()` maps ~25 base `License_Key__c` fields (account, contacts, dates, product names, key, serial, silo, notes). `insertLicenseKeyRecord(SObject)` does DML. `createAttachment()` returns `null` by default (override to emit a file). Inner `LicenseKeyResponseMessage` DTO. |
| `LkgRecordCreatorFactory` | **Factory (router)** | `getRecordCreator(silo[, subSilo])` — `switch on silo`; halcyon dispatches on `subSilo=='ibm'`. |
| `LkgRecordCreatorAccessAuth` | Per-silo creator | AccessAuth/SecurityScan fields. |
| `LkgRecordCreatorAutomate` | Per-silo creator | Stamps `Modification__c` and `Points__c` from `AutomateKeyData`. |
| `LkgRecordCreatorClearswift` | Per-silo creator | Clearswift fields. |
| `LkgRecordCreatorDocM` | Per-silo creator | Document Management. |
| `LkgRecordCreatorFortra` | Per-silo creator | Fortra product fields. |
| `LkgRecordCreatorHalcyonIbm` | Per-silo creator | Halcyon IBM. |
| `LkgRecordCreatorIntermapper` | Per-silo creator | Intermapper. |
| `LkgRecordCreatorLegacyIbm` | Per-silo creator | Legacy IBM-i. |
| `LkgRecordCreatorPowertech` | Per-silo creator | Powertech (+ safestone/sgav/bytware/ccss). |
| `LkgRecordCreatorPtMulti` | Per-silo creator | Powertech multi-product. |
| `LkgRecordCreatorRSF` | Per-silo creator | RSF. |
| `LkgRecordCreatorRobot` | Per-silo creator | Robot. |
| `LkgRecordCreatorSequel` | Per-silo creator | Sequel. |
| `LkgRecordCreatorSequelQueryBuilder` | Per-silo creator | Sequel QueryBuilder. |
| `LkgRecordCreatorSequelWeb` | Per-silo creator | Stamps `Release__c`/`Modification__c` from `SequelWebKeyData`. |
| `LkgRecordCreatorSgavx` | Per-silo creator | **Only creator that overrides `createAttachment()`** — emits the SGAVX XML license file as an `Attachment` on the `License_Key__c`. |
| `LkgRecordCreatorTQSurveyor` | Per-silo creator | TQ/Surveyor. |
| `LkgRecordCreatorVityl` | Per-silo creator | Vityl. |

---

## Automate Points Sub-system

The Automate/BPA products price their keys in "points" derived from product code + tier + version. This is a
nested strategy factory used by `LkgMapperAutomate`.

| Class | Role | Purpose / key methods |
|---|---|---|
| `LkgAutomatePointsBuilderFactory` | **Factory (router)** | `getBuilder(AutomatePointsBuilderContext)` selects an `ILkgAutomatePointsBuilder` by composite key `productCode_tier_(GTE11|LT11)` from a static map (AUT/BPA tiers A–D, modern vs legacy <v11). Falls back to a default builder; throws `IllegalArgumentException` on unmapped keys. *(The `ILkgAutomatePointsBuilder` interface, `AutomatePointsBuilderContext`, and the concrete `AutomateTier*PointsBuilder` classes are referenced here but live outside the `Lkg*` list.)* |

---

## Mocks & Test Doubles (`@isTest`, used by the test suite)

These implement `System.StubProvider` (or `HttpCalloutMock`) so each pipeline stage can be tested independently
with `Test.createStub`. They track call counts and let tests inject canned outputs.

| Class | Role | Purpose |
|---|---|---|
| `LkgHttpCalloutMock` | `HttpCalloutMock` | Canned keygen-API responses for `callout:keygen_api`; branches on request body (`silo=sgavx` → XML license, `silo=clearswift` → key+serial, else default key). |
| `LkgMapperMock` | StubProvider | Stubs `mapPayloadToKeyData`; counts `mapPayloadCallCount`. |
| `LkgMapperFactoryMock` | StubProvider | Stubs `getMapper`. |
| `LkgRequestBuilderMock` | StubProvider | Stubs `buildRequest`. |
| `LkgRequestBuilderFactoryMock` | StubProvider | Stubs `getRequestBuilder`. |
| `LkgRecordCreatorMock` | StubProvider | Stubs create/insert/attachment; captures `createdLicenseKey`, `sendEmailValueOnCreate` (used to assert the deferred-email behavior). |
| `LkgRecordCreatorFactoryMock` | StubProvider | Stubs `getRecordCreator`. |
| `LkgRequestControllerMock` | StubProvider | Stubs `generateLicenseKey` (avoids the real HTTP callout). |

---

## Test Classes (one per non-mock class)

Each production class has a matching `*Test`. They follow the same pattern: build a `UiPayload`, stub the
collaborators with the mocks above, exercise the unit, assert field mapping / call counts / parameter ordering.

`LkgAutomatePointsBuilderFactoryTest`, `LkgKeyGenResponseTest`, `LkgMapperAccessAuthTest`, `LkgMapperAutomateTest`,
`LkgMapperBaseTest`, `LkgMapperClearswiftTest`, `LkgMapperDocMTest`, `LkgMapperFactoryTest`, `LkgMapperFortraTest`,
`LkgMapperHalcyonIbmTest`, `LkgMapperIntermapperTest`, `LkgMapperLegacyIbmTest`, `LkgMapperPowertechTest`,
`LkgMapperPtMultiTest`, `LkgMapperRSFTest`, `LkgMapperRobotTest`, `LkgMapperSequelTest`,
`LkgMapperSequelQueryBuilderTest`, `LkgMapperSequelWebTest`, `LkgMapperSgavxTest`, `LkgMapperTQSurveyorTest`,
`LkgMapperVitylTest`, `LkgProcessorTest`, `LkgRecordCreatorAccessAuthTest`, `LkgRecordCreatorAutomateTest`,
`LkgRecordCreatorBaseTest`, `LkgRecordCreatorClearswiftTest`, `LkgRecordCreatorDocMTest`,
`LkgRecordCreatorFactoryTest`, `LkgRecordCreatorFortraTest`, `LkgRecordCreatorHalcyonIbmTest`,
`LkgRecordCreatorIntermapperTest`, `LkgRecordCreatorLegacyIbmTest`, `LkgRecordCreatorPowertechTest`,
`LkgRecordCreatorPtMultiTest`, `LkgRecordCreatorRSFTest`, `LkgRecordCreatorRobotTest`,
`LkgRecordCreatorSequelTest`, `LkgRecordCreatorSequelQueryBuilderTest`, `LkgRecordCreatorSequelWebTest`,
`LkgRecordCreatorSgavxTest`, `LkgRecordCreatorTQSurveyorTest`, `LkgRecordCreatorVitylTest`,
`LkgRequestBuilderAccessAuthTest`, `LkgRequestBuilderAutomateTest`, `LkgRequestBuilderBaseTest`,
`LkgRequestBuilderClearswiftTest`, `LkgRequestBuilderDocMTest`, `LkgRequestBuilderFactoryTest`,
`LkgRequestBuilderFortraTest`, `LkgRequestBuilderHalcyonIbmTest`, `LkgRequestBuilderIntermapperTest`,
`LkgRequestBuilderLegacyIbmTest`, `LkgRequestBuilderPowerTechTest`, `LkgRequestBuilderPtMultiTest`,
`LkgRequestBuilderRSFTest`, `LkgRequestBuilderRobotTest`, `LkgRequestBuilderSequelTest`,
`LkgRequestBuilderSequelQueryBuilderTest`, `LkgRequestBuilderSequelWebTest`, `LkgRequestBuilderSgavxTest`,
`LkgRequestBuilderTQSurveyorTest`, `LkgRequestBuilderVitylTest`, `LkgRequestControllerTest`, `LkgUiControllerTest`,
`LkgTermPermRangeCheckerTest`.

---

## Patterns & Gotchas

- **Strategy + Factory per stage.** To add a product you typically add a Mapper, RequestBuilder, and RecordCreator
  subclass plus a `when` branch in each of the three factories — and wire the silo into the `LKG_*__mdt` config.
  Forgetting any one factory branch yields a clear `LkgKeyGenResponse.error('… not defined in …Factory')`.
- **Silo string ≠ class name.** Multiple silo strings collapse to one class (e.g. `safestone`/`sgav`/`bytware`/`ccss`
  → Powertech; `accessauth`/`securityscan` → AccessAuth; `tqjava` → TQSurveyor). Don't assume a 1:1 mapping.
- **Casing inconsistency:** the RequestBuilder family uses `LkgRequestBuilderPowerTech`/`LkgRequestBuilderHalcyonIbm`
  with camelCase **`PowerTech`**, while Mapper/RecordCreator use `Powertech`. Easy to mistype.
- **Positional keygen-API contract.** `dynamicParameters` is a `Map<Integer,Object>` flattened into ordered
  `&argv=` params. The per-silo `*Parameters` enums encode that order — reordering an enum breaks the external
  keygen call silently. This is the most fragile coupling in the framework.
- **Deferred email (load-bearing).** `LkgProcessor.Execute` deliberately inserts the `License_Key__c` with
  `Send_Email__c=false`, creates the Attachment, then flips it back to `true` via `update`. This sequencing exists
  so the email-on-create automation does not fire before the license-key file Attachment exists. Do not "simplify."
- **SGAVX is the attachment special case** — only `LkgRecordCreatorSgavx` overrides `createAttachment()`; everything
  else returns the base `null`. `LkgHttpCalloutMock` mirrors this (returns XML for `silo=sgavx`).
- **Named credential dependency.** All callouts go through `callout:keygen_api`. The whole subsystem is dead if that
  external named credential / keygen service is misconfigured.
- **Metadata-driven UI.** `LkgUiController` reads `LKG_Solution_Group__mdt`, `LKG_Solution_Category__mdt`,
  `LKG_Solution__mdt`, `LKG_Product__mdt`, `LKG_Key_Type__mdt`, `LKG_UI_Field__mdt`, `LKG_UI_Field_Option__mdt`,
  `LKG_Silo__mdt`/`LKG_Brand__mdt`. New products/fields are largely config, not code — but the silo routing in the
  Apex factories still has to be updated in lockstep.
- **Fully mock-isolated tests.** Every stage is stubbed via `System.StubProvider`; the HTTP callout via
  `LkgHttpCalloutMock`. Mocks track call counts and capture inserted records — when adding a stage, extend the
  matching mock or stage tests will silently skip coverage.
- **Independent of pricing/RCA.** Despite living in the same org as the Revenue Cloud work, LKG shares no code with
  the pricing procedures, Workday/MuleSoft order sync, or Quote/Order automation documented elsewhere.
