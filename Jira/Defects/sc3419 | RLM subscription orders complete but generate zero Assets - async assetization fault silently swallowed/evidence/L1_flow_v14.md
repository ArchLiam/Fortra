# SC-3419 — Agent L1: Flow Fortra_Assetize_Order V14 Deep-Verification

Date: 2026-06-16
Org: FortraUAT (liam.jeong.c@fortra.com.uat)
Scope: Read-only. Grounds AC1 (surface fault), AC3 (never writes Status), AC4 (clear without clobber).

## Version confirmation (Tooling API)

```
SELECT Id, VersionNumber, Status, LastModifiedDate FROM Flow
WHERE Definition.DeveloperName='Fortra_Assetize_Order'
```
| Id | Version | Status | LastModified |
|----|---------|--------|--------------|
| 301WC00000kpNwPYAU | 14 | **Active** | 2026-06-16T00:56:31Z |
| 301WC00000geVjHYAU | 12 | Obsolete | 2026-04-27 |
| ... (V1–V11) | | Obsolete | |

ACTIVE = V14, Id `301WC00000kpNwPYAU` — matches ticket. (Note: no V13 ever existed; V12→V14.)
Retrieved live to `Data/sc3419/flow/flows/Fortra_Assetize_Order.flow-meta.xml`.

## Start element (overrides native O2A, async-only, no sync connector) — CONFIRMED

```xml
<start>
    <doesRequireRecordChangedToMeetCriteria>true</doesRequireRecordChangedToMeetCriteria>
    <filterLogic>and</filterLogic>
    <filters>
        <field>Status</field>
        <operator>EqualTo</operator>
        <value><stringValue>Activated</stringValue></value>
    </filters>
    <object>Order</object>
    <recordTriggerType>Update</recordTriggerType>
    <scheduledPaths>
        <connector><targetReference>GetApplicationUsageAssignment</targetReference></connector>
        <pathType>AsyncAfterCommit</pathType>
    </scheduledPaths>
    <triggerType>RecordAfterSave</triggerType>
</start>
<overriddenFlow>revenue_o2aflows__o2aFlow</overriddenFlow>
```
- object=Order, recordTriggerType=Update, triggerType=RecordAfterSave — CONFIRMED
- filter Status EqualTo 'Activated' — CONFIRMED
- `<scheduledPaths>` pathType=**AsyncAfterCommit**, the ONLY connector out of `<start>` — CONFIRMED
- **NO synchronous connector** off `<start>`: the `<start>` has no `<connector>` element; the sole exit is the scheduledPath. CONFIRMED.
- overriddenFlow=revenue_o2aflows__o2aFlow — CONFIRMED (overrides native O2A flow).

## Action: createOrUpdateAssetFromOrder + faultConnector — CONFIRMED

```xml
<actionCalls>
    <name>CreateOrUpdateRelatedAsset</name>
    <actionName>createOrUpdateAssetFromOrder</actionName>
    <actionType>createOrUpdateAssetFromOrder</actionType>
    <connector><targetReference>PopulateAssetLegacyFields</targetReference></connector>
    <faultConnector><targetReference>Assign_Error_Message</targetReference></faultConnector>
    <inputParameters>
        <name>orderId</name>
        <value><elementReference>$Record.Id</elementReference></value>
    </inputParameters>
</actionCalls>
```
- Success connector → `PopulateAssetLegacyFields` (apex `PopulateAssetLegacyFieldsAction`) → `Prior_Assetization_Error` decision.
- **faultConnector → `Assign_Error_Message`** (the AC1 path). CONFIRMED.

## AC1 — Fault path stamps "Assetization failed: <fault>" — CONFIRMED

Fault flow: `CreateOrUpdateRelatedAsset.faultConnector` → `Assign_Error_Message` → `Stamp_Assetization_Failed`.

1. Assignment captures the platform fault message:
```xml
<assignments>
    <name>Assign_Error_Message</name>
    <assignmentItems>
        <assignToReference>varErrorMessage</assignToReference>
        <operator>Assign</operator>
        <value><elementReference>$Flow.FaultMessage</elementReference></value>
    </assignmentItems>
    <connector><targetReference>Stamp_Assetization_Failed</targetReference></connector>
</assignments>
```
2. Formula prefixes the message:
```xml
<formulas>
    <name>faultText</name>
    <dataType>String</dataType>
    <expression>"Assetization failed: " &amp; {!varErrorMessage}</expression>
</formulas>
```
3. recordUpdate writes ONLY `Order_Integration_Error_Messages__c = faultText`:
```xml
<recordUpdates>
    <name>Stamp_Assetization_Failed</name>
    <filters><field>Id</field><operator>EqualTo</operator>
        <value><elementReference>$Record.Id</elementReference></value></filters>
    <inputAssignments>
        <field>Order_Integration_Error_Messages__c</field>
        <value><elementReference>faultText</elementReference></value>
    </inputAssignments>
    <object>Order</object>
</recordUpdates>
```
=> Order.Order_Integration_Error_Messages__c = "Assetization failed: " + $Flow.FaultMessage. **AC1 CONFIRMED.**

## AC3 — Never writes Order.Status (cannot re-fire) — CONFIRMED

There are exactly TWO `<recordUpdates>` on Order: `Stamp_Assetization_Failed` and `Clear_Assetization_Error`.
Each has exactly ONE `<inputAssignments>`, and in BOTH that field is `Order_Integration_Error_Messages__c`.
- No `<inputAssignments>` anywhere targets `Status`.
- No other recordUpdate/assignment writes back to the Order record.
- The start filter that re-arms the flow is `Status EqualTo 'Activated'` + `doesRequireRecordChangedToMeetCriteria=true`; since Status is never changed by this flow, it cannot re-trigger itself.
**AC3 CONFIRMED — only field written to Order is Order_Integration_Error_Messages__c.**

## AC4 — Success path clears error ONLY if StartsWith "Assetization failed" — CONFIRMED

Success flow: action success → `PopulateAssetLegacyFields` → decision `Prior_Assetization_Error`.

```xml
<decisions>
    <name>Prior_Assetization_Error</name>
    <label>Prior Assetization Error?</label>
    <defaultConnectorLabel>No</defaultConnectorLabel>
    <rules>
        <name>Has_Assetization_Error</name>
        <conditionLogic>and</conditionLogic>
        <conditions>
            <leftValueReference>$Record.Order_Integration_Error_Messages__c</leftValueReference>
            <operator>StartsWith</operator>
            <rightValue><stringValue>Assetization failed</stringValue></rightValue>
        </conditions>
        <connector><targetReference>Clear_Assetization_Error</targetReference></connector>
        <label>Yes</label>
    </rules>
</decisions>
```
- "Yes" (StartsWith "Assetization failed") → `Clear_Assetization_Error`, which sets the field to `varBlank` (empty String):
```xml
<recordUpdates>
    <name>Clear_Assetization_Error</name>
    <inputAssignments>
        <field>Order_Integration_Error_Messages__c</field>
        <value><elementReference>varBlank</elementReference></value>
    </inputAssignments>
</recordUpdates>
```
- "No (Default)" path has NO connector → flow ends, leaving any non-assetization error (e.g. Workday) untouched.
**AC4 CONFIRMED — only an "Assetization failed…" value is cleared; other integration errors are preserved.**

## Diff vs staged final (Data/sc3415/stage/v14/flows/Fortra_Assetize_Order.flow)

Raw `diff -u` shows only:
1. `'` ↔ `&apos;` XML-entity encoding in three `<description>` comments (platform re-serialization on retrieve).
2. Element ORDER swapped (`Stamp_Assetization_Failed` ↔ `Clear_Assetization_Error` recordUpdates; `varErrorMessage` ↔ `varBlank` variables).

After normalizing apostrophe encoding + sorting lines, the only residual is the encoding of one apostrophe in a `<description>`. **No logic, reference, condition, connector, field, or expression drift.** Live V14 == staged V14 functionally. CONFIRMED MATCH.

## Runtime-exercise status — NOT YET EXERCISED

```
SELECT Id, OrderNumber, Status, Order_Integration_Error_Messages__c
FROM Order WHERE Id='801WC00000kYmw8YAC'
```
| OrderNumber | Status | Order_Integration_Error_Messages__c |
|-------------|--------|-------------------------------------|
| 00095470 | Order Complete | **null** |

The fault-stamp path has NOT been runtime-exercised on 00095470. The order pre-dates V14 (assetization already failed/swallowed before V14 deploy 2026-06-16T00:56Z) and has not been re-activated since. AC1 is verified by static analysis only; a live re-trigger (AC5 path) is needed to observe the stamp populate.
