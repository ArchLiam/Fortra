# SC-3350 / COLA — Canonical User Story (as provided 2026-06-10)

> Preserved verbatim for conformance auditing. This is the authoritative business spec for the COLA Uplift
> feature. **Note it is single-year only** (Req #5) — it contains no out-year / MyCAP / multi-year
> compounding, which resolves the scope fork in [../README.md](../README.md) §7 toward **Option A**.

## User Story
As a Revenue Operations Manager, I need automated COLA Uplift percentages applied to renewal quote lines in
Revenue Cloud so that pricing reflects predefined uplift percentages based on the solution associated with
each product, with the ability for users to override the uplift while maintaining auditability.

## Requirements
- **#1 Custom Object for COLA Uplift Rules** — custom object `COLA_Uplift_Rules__c` storing all COLA uplift
  data. Fields: Unit, Solution Group, Solution Category, Solution Name, Default COLA Percentage, Active flag.
  **Field history tracking** enabled for auditability.
- **#2 Populate COLA Uplift Rules** — load initial percentages for all solutions (mapping table below);
  Cyber + Tech units, all categories and names.
- **#3 Configure Quote Line Automation** — on renewal quote creation, auto-populate
  `COLA_Uplift_Percent__c` and `Default_COLA_Uplift_Percent__c` by matching the **product's solution name**
  to `COLA_Uplift_Rules__c`. If no match, set uplift to **0%**.
- **#4 Enable User Override** — users can override `COLA_Uplift_Percent__c`; once overridden, automation will
  not overwrite on future recalculations. `Default_COLA_Uplift_Percent__c` remains read-only.
- **#5 Pricing Procedure Integration** — RCA Pricing Procedure applies
  `Final Price = Base Renewal Price × (1 + COLA_Uplift_Percent__c / 100)`. Apply **only to renewal** quote lines.
- **#6 Security & Permissions** — authorized Revenue Operations users can update `COLA_Uplift_Rules__c`;
  standard users cannot.

## Mapping table (Unit · Solution Group · Solution Category · Solution · Default COLA %)
| Unit | Solution Group | Solution Category | Solution | Default COLA % |
|---|---|---|---|---|
| Cyber | Defensive Security | Vulnerability Management | Beyond Security Legacy | 6.20 |
| Cyber | Defensive Security | File Integrity Management | File Integrity Monitoring | 5.00 |
| Cyber | Defensive Security | Email Security | Cloud Email Protection | 5.00 |
| Cyber | Defensive Security | Brand Protection | External Threat Monitoring | 5.00 |
| Cyber | Defensive Security | Human Risk Management | Human Risk Management | 5.00 |
| Cyber | Defensive Security | Data Protection | Data Classification | 4.70 |
| Cyber | Defensive Security | Cloud Data Protection | CASB | 5.00 |
| Cyber | Defensive Security | Fortra Platform | Event Fusion Center (EFC) | 0 |
| Cyber | Defensive Security | Offensive Security | Core Impact | 6.20 |
| Tech | RPA+ | Robotic Process Automation | Automate | 9.85 |
| Tech | RPA+ | Core IGA | Access Assurance Suite | 4.70 |
| Tech | RPA+ | Network Monitoring | Automated Analytics | 7.85 |
| Tech | RPA+ | Powertech Identity & Access Manager | Powertech Identity & Access Manager (BoKS) | 7.85 |
| Tech | RPA+ | Capacity Management | TeamQuest OEM | 4.70 |
| Tech | Managed File Transfer | GoAnywhere | GoAnywhere MFT | 7.85 |
| Tech | Managed File Transfer | Globalscape | Globalscape EFT | 7.85 |
| Tech | Power | Business Intelligence | Abstract | 7.85 |
| Tech | Power | Doc Management | DeliverNow | 7.85 |
| Tech | Power | Systems Management | MessengerConsole | **12.00** |
| Tech | Power | Cybersecurity | SecureCare | **4.70** |
| Tech | IPP | IPP | IPP | 0 |
