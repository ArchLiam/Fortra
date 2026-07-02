# 02 — Impact & Blast Radius

Scope is **narrow and asymmetric**: only `Hardware_Platform__c = iSeries` records are affected (the 46
existing rows + all future iSeries hardware created via this modal). Cross Platform and platform-NULL
records have no iSeries-model concept and are untouched.

## Downstream consumers of `Model_Number__c`

| Consumer | Where | Role | Breaks for iSeries? | Notes |
|---|---|---|---|---|
| **hardwareGroupManager LWC** | `js:121/130/822`, `html:312/611` | display | **Yes** | The user-visible face of the bug — grid + cards show blank model |
| **hardwareManagementModal** | `html:239-240` | display | **Yes (cosmetic)** | `if:true={hw.Model_Number__c}` suppresses the "Model:" line for iSeries |
| **HardwareGroupController** | `cls:58/103/116/395` | search/display | **Yes** | `cls:103` `WHERE Model_Number__c LIKE :modelFilter` — model search won't find iSeries rows |
| **HardwareManagementController** | `cls:209-211`, `324-325` | search/display | **Yes** | Free-text search keys off `Model_Number__c`; iSeries codes not found |
| **BSSOrderInfoRestService** | `cls:104` (SELECT), `cls:198` (→ outbound `model`) | integration | **No live impact** | Reads `Hardware_ID__r.Model_Number__c`. Only **2 OrderItems** reach the 46 HW via `Hardware_ID__c`, both on **Draft** orders → nothing transmitted today |
| **PowerOrderSplittingService** | `cls:410` (SELECT), `cls:424` (clone copy) | data fidelity | **Latent** | Clones copy `Model_Number__c` only, not `iSeries_Model__c` — splitting an iSeries HW loses the model on clones. Rare; **separate ticket** |
| **HardwareAttributePricingPrehook** | `cls:530/629/674` | pricing | **No — SAFE** | Price derives from `P_Group_List__c` + `Server_Type__c` + `Users_Per_Partition__c`. Model is **audit-JSON only** |
| **HardwareProductEligibilityService** | `cls:46` | eligibility | **No — SAFE** | Eligibility uses `Number_of_Processors__c` + `Feature_Code__c` + `Product2.Type`. Model is never read in any rule |
| **HardwareProductSelectorController** | `cls:42/132` | display | **No (cosmetic)** | Surfaces model as header context only; not used in `addProductsToQuote` |
| **Hardware_Selection_Screen flow** | `:115` | placeholder | **No** | `[PLACEHOLDER]` developer note, not a live read |

### Confirmed NON-consumers (false positives — exclude from scope)

- **LkgRecordCreator{LegacyIbm,HalcyonIbm,Sequel,Robot,Powertech}**, **LicenseKeyEmailHandler**,
  **LkgRequestBuilder\*** — these reference **`LPAR_Model_Number__c` on `License_Key__c`** (a different
  object/field sourced from the inbound LKG JSON payload), **not** `Hardware__c.Model_Number__c`. No FK to
  the hardware model field. Zero impact.
- **QuoteLineItemTriggerHandler / OpportunityTriggerHandler** — production code has **no**
  `Model_Number__c` reference; the grep hits are test fixtures (`...Test.cls`).

## Consumers of `iSeries_Model__c`

| Consumer | Where | Role | Breaks if blank? |
|---|---|---|---|
| hardwareGroupManager (write) | `js:737` | the only model write from the create form | Client validation requires it for iSeries (`js:702-704`) — fails with a toast, not an exception |
| HardwareGroupController | `cls:170-171` (write), `437-438` (options), `486` (controller) | persist + dependent picklist controller | Null-safe; `getFeatureCodeOptions` returns `[]` early |
| iSeries_Feature_Code__c | `field-meta.xml:12` | **dependent picklist controlled by it** | Re-pointing the model write away from `iSeries_Model__c` orphans this |
| Fortra_Hardware_Hardware_Creation_Subflow | `:158` | optional assignment | No |
| Fortra_Hardware_Hardware_Management_Orchestrator | `:221` (`ISeriesModelChoices`), screen label "iSeries Model" `:388` | choice set | No |
| All_Hardware list view | `listView:13` | filter `iSeries_Model__c != null` | Row simply excluded if blank |
| FortraDemoDataFactory | `cls:411/424` | seed/demo data | Test-only literals |

**Key architectural point:** `Model_Number__c` (free-text full name, e.g. "IBM Power E1080") and
`iSeries_Model__c` (constrained short-code picklist, e.g. "M9S"/"500"/"22A") are **semantically distinct**,
not drop-in substitutes — `FortraDemoDataFactory` even populates both with different values on one record.

## Child relationships seen in the Inspector screenshot (clarification)

`ModelOrderItems__r`, `PriorModelOrderItems__r`, `Quote_Line_Items_Model__r` are **Lookup(Hardware__c)**
relationships pointing at the whole Hardware record — **not** references to the `iSeries_Model__c` picklist
or the `Model_Number__c` text field:

- `ModelOrderItems__r` = `OrderItem.Model__c` → Lookup(Hardware__c)
- `PriorModelOrderItems__r` = `OrderItem.Prior_Model__c` → Lookup(Hardware__c)
- `Quote_Line_Items_Model__r` = `QuoteLineItem.Model__c` → Lookup(Hardware__c) (*"driving price for Power products"*)

Downstream code traverses `Model__r.*` / `Hardware__r.*` to the Hardware and then reads the model field
from it — so a consumer reading `Hardware__r.Model_Number__c` on a diverted row gets `null`.

## Live downstream reference counts (the 46 diverted HW)

- `OrderItem.Hardware__c` = 24 · `OrderItem.Model__c` = 2
- `QuoteLineItem.Hardware__c` = 18 · `QuoteLineItem.Hardware_Reference__c` = 7
- `Asset.Hardware__c` = 25
- Of these, **24/24 OrderItems, 24/25 Assets, 15/18 QLIs** point at HW with `Model_Number__c = null`.
- **BSS-reachable set = 2 OrderItems**, both on **Draft** orders → no live integration data loss.

## Net blast-radius verdict

- **User-visible (the ticket itself):** display surfaces show blank model for iSeries → fixed by the read/label change.
- **Latent / out of immediate scope:** model-search parity (`cls:103`, `324-325`), BSS-on-activation, Power-split clone copy.
- **Safe (no change):** pricing, product eligibility.
- **Not consumers:** License-Key/LKG stack, QLI/Opp trigger handlers.
- The recommended UI fix has **near-zero regression surface** (LWC-only, trivially reversible).
