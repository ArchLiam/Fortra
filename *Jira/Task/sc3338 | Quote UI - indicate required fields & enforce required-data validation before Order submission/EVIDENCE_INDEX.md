# SC-3338 — Evidence Index

All checks read-only against FortraUAT / FortraProd and the local repo, 2026-06-12. No deploys, no DML.

## A. Required-field metadata (mdt)
| Evidence | Proves |
|---|---|
| `sf data query "SELECT COUNT() FROM Order_Submit_Validation__mdt" --target-org FortraUAT` → **48** | mdt total = 48 records |
| `… WHERE Active__c=true` → **25** | 25 Active / 23 Inactive split |
| `Data/sc3338/retrieve/Order_Submit_Validation_LIVE.csv` (49 data rows incl. header) | Per-rule object/field/relationship/active/error-message; byte-matches org; rows X00001–X00049 cited throughout README §3 |

## B. Enforcement classes & validator behavior
| Evidence | Proves |
|---|---|
| `force-app/main/default/classes/OrderSubmissionValidator.cls:69` (`validate(List<ValidationRequest>)`) | Apex entry point invoked by live v13 flow |
| `OrderSubmissionValidator.cls:254-265` (`isValuePopulated`) | Populated-logic the modal mirrors |
| `OrderSubmissionValidator.cls:258-259` (Boolean → always populated) | `Workday_MobilePhone_Primary__c` and Places Boolean rules can never block |
| `OrderSubmissionValidator.cls:230` (`'Required field is missing.'` default) | Blank `EffectiveDate` Error_Message → generic, not silent |
| `OrderSubmissionValidator.cls:297-303` (`fieldExists`) | Inactive `Workday_Customer_Id__c`/`ProductCode` rules inert (not in describe) |
| `ls force-app/main/default/classes` → `OrderSubmissionValidator`, `FieldPopulatedCheck`, `QuoteToOrderFieldMapper` (+Tests) present | Local class set; FieldPopulatedCheck deprecated but still in org |

## C. Flows (live versions + trigger types)
| Evidence | Proves |
|---|---|
| `FlowDefinitionView` query (FortraUAT) | `Fortra_Order_Submission_Check` (ProcessType=Flow), `Fortra_Quote_to_Order_Conversion` (Flow), `Fortra_OrderItem_Set_Workday_Contract_Line_Type` (RecordAfterSave), `Fortra_Order_Workday_Contract_ID` (RecordAfterSave), `Quote_After_Update_Create_Order_From_Quote` (RecordAfterSave), `Order_Before_Insert_Update_Sync_Status` (RecordBeforeSave), `Fortra_Quote_Validate_Partner_Pricing_Model` (RecordBeforeSave) |
| `Flow … Status='Active'` tooling query | Active versions: Submission_Check **v13**, Workday_Contract_ID **v3**, Set_Workday_Contract_Line_Type **v11**, Quote_to_Order_Conversion **v27**, Validate_Partner_Pricing_Model **v2** |
| `grep -c FieldPopulatedCheck force-app/.../Fortra_Order_Submission_Check.flow-meta.xml` → **4**; `OrderSubmissionValidator` → 0 | Local flow STALE (calls deprecated validator); do not deploy |

## D. Quote schema / UI
| Evidence | Proves |
|---|---|
| `Data/sc3338/retrieve/Quote_describe.json` — `Name` `"nillable": false` | Only Name hard-required |
| `Quote_describe.json` — 36 of 237 fields with `inlineHelpText` | Sparse help-text coverage |
| describe scan: `BillToContactId`/`StartDate`/`Status`/`CurrencyIsoCode`/`LegalEntityId` → **NONE**; `Bill_To_Place__c`/`Ship_To_Place__c`/`ContactId`/`Billing_Partner__c` → **HELP** | The 5 fields needing new help text vs the 4 already covered |
| `11_QUOTE_UI_HELPTEXT_AUDIT.md` (layout parse) | Quote-Quote Layout 128 items / 1 Required; Amendment Layout 127 / 2 Required; `Quote_Record_Page` dynamic FlexiPage (no force:recordDetail) so classic Required dots don't render |

## E. Validation rules (drift)
| Evidence | Proves |
|---|---|
| `ValidationRule WHERE EntityDefinition.QualifiedApiName='Quote'` (tooling) → 4 | Live Quote VRs: Enforce_Amendment_Sales_Restriction, Sales_Cannot_Create_Downsell, Quote_BillToContactAcct_Equal_QuoteAcct, Quote_BillToPlacceAcct_Equal_QuoteAcct (D2; corrects GT's 5) |
| `ValidationRule WHERE … ='Order'` (tooling) → 7 | Live Order VRs: Lock_Currency_At_Order_Activation + 6 Bill/Ship account-equality (D1; none enforces required-field presence) |

## F. Conversion field map & trigger
| Evidence | Proves |
|---|---|
| `QuoteToOrderFieldMapper.cls:19-27` (header map) + `:130-141` (Bill_To_Account ← Quote.AccountId) | Quote→Order required-field provenance; SC-3339 Bill_To_Account caveat |
| `QuoteToOrderFieldMapper.cls:22-23` (Ship_To_Account ← Ship_To_Place.Account, null when no Place) | Silent Ship_To_Account hole |
| `./conv_retrieve2/unpackaged/triggers/OrderValidationTrigger.trigger` = `trigger … on Order (before insert)` (also `./Org Data/_src/triggers/`) | Only Order trigger is before-insert; no update-time required-field backstop (corrects Claim-18 path) |

## G. Auto-population (formula) evidence
| Evidence | Proves |
|---|---|
| `FieldDefinition` IsCalculated: Order `WorkdayReferenceID__c`=**true**, `Workday_Contract_ID__c`=false; OrderItem `Billing_Frequency__c`=**true** | WorkdayReferenceID & OrderItem Billing_Frequency are formula (auto); Workday_Contract_ID set by flow v3 — all non-rep |

## H. Prod-vs-UAT parity
| Evidence | Proves |
|---|---|
| FortraProd `EntityDefinition WHERE QualifiedApiName='Order_Submit_Validation__mdt'` → **0** | mdt absent in prod |
| FortraProd `ApexClass WHERE Name IN ('OrderSubmissionValidator','FieldPopulatedCheck')` → **0** | validator classes absent in prod |
| FortraProd `Flow WHERE Definition.DeveloperName='Fortra_Order_Submission_Check'` → **0** | submission flow absent in prod |
| `Data/sc3338/PROD_PARITY_EVIDENCE.md` | Independent parity table + non-deploy directive |

## I. Reusable build template
| Evidence | Proves |
|---|---|
| `Fortra_Quote_Validate_Partner_Pricing_Model` v2 Active (RecordBeforeSave) | Live customError pattern to copy for the AC4 Quote-time blocker |
