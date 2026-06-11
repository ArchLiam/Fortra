# Custom Apex Triggers

## Overview

The Fortra org has 10 no-namespace Apex triggers covering quoting (CPQ/Revenue Cloud), the
Quote→Order→Asset lifecycle, currency handling, and integration-adjacent automation (PSA billing,
license-key emails). Most triggers are thin and delegate to a `*Handler` / `*TriggerHandler` class,
following the standard logic-less-trigger pattern; two are exceptions that hold inline logic
(`LicenseKeyTrigger`, `QuoteLineItemExchangeRateTrigger`). The **one-trigger-per-object pattern is
mostly followed but NOT enforced**: the `Quote` object has **two** separate triggers
(`QuoteTrigger` + `QuoteSyncingTrigger`), and `QuoteLineItem` also has **two**
(`QuoteLineItemTrigger` + `QuoteLineItemExchangeRateTrigger`) — execution order between sibling
triggers on the same object is undefined, which is a fragility worth noting.

## Triggers

| Trigger | Object | Events | Handler / Purpose |
|---|---|---|---|
| `AssetMigrationQueueClearTrigger` | `Asset` | after insert | `AssetMigrationQueueClearHandler.handleAfterInsert`. When an Asset is created from a migration Contract, clears `In_Rerun_Queue__c` on the `Migration_Run_Detail__c` rows for the originating Quote. Implements the strict "Full Pipeline succeeded" milestone (Order + AUA + Asset all present) for auto-removal from the rerun queue. |
| `FortraBillingEventItemTrigger` | `pse__Billing_Event_Item__c` (PSA) | after insert, after update | `FortraBillingEventItemTriggerHandler.handleAfterInsertOrUpdate`. Reacts to PSA (PS Cloud) billing-event-item changes. Trigger fires on a managed-package object but the trigger + handler are custom (no namespace). |
| `LicenseKeyTrigger` | `License_Key__c` | after insert, after update | **Inline logic (no handler delegation for filtering).** Collects `License_Key__c` Ids where `Send_Email__c == true` (on insert) or just flipped false→true (on update), then calls `LicenseKeyEmailHandler.ProcessLicenseKeyEmailFromIds`. Drives license-key email sends. |
| `OpportunityTrigger` | `Opportunity` | before insert, before update, after update | `OpportunityTriggerHandler` (`handleBeforeInsert` / `handleBeforeUpdate` / `handleAfterUpdate`). Manages `Hardware__c` record lifecycle on stage change: 'Closed Lost' deletes `Status='Quoting'` Hardware (if not referenced by other Opps); 'Order Processing' flips Hardware `Quoting`→`Active`. |
| `OrderValidationTrigger` | `Order` | before insert | `OrderValidationTriggerHandler.handleBeforeInsert`. Validates Orders at creation time (e.g. required-field / data-integrity gating before the Quote→Order conversion completes). |
| `QuoteLineGroupTrigger` | `QuoteLineGroup` | after update | `QuoteLineGroupTriggerHandler.handleHardwareChange`. Propagates a group-level Hardware change down to the child quote lines (keeps QLI hardware references in sync when the group's hardware is reassigned). |
| `QuoteLineItemExchangeRateTrigger` | `QuoteLineItem` | before insert, before update, after insert, after update | **Inline logic (no dedicated handler).** *Before:* sets `Exchange_Rate_To_USD__c` on each QLI via `DatedConversionRateLookup.getExchangeRates` (ACM/CurrencyType fallback). *After:* propagates the rate up to the parent `Opportunity.Exchange_Rate_To_USD__c`, but **only when the QLI's Quote is the Opportunity's `SyncedQuoteId`**. Uses `Database.update(..., false)` (allOrNone=false) so Opportunity VR failures don't block the QLI save — QLI rate is source of truth, Opp copy is best-effort. |
| `QuoteLineItemTrigger` | `QuoteLineItem` | before insert, before update, after insert | Delegates to three handlers: `QuoteLineItemTriggerHandler.handleHardwareLinking` (before insert/update — hardware assignment when lines join/leave groups); `COLAUpliftHandler.handleBeforeInsert` / `handleBeforeUpdate` (COLA Cost-of-Living-Adjustment uplift for renewal lines — **SC-3350 territory**); `RenewalQuoteLineHandler.enqueueCarryoverCleanup` (after insert — async cleanup of carried-over renewal data). |
| `QuoteSyncingTrigger` | `Quote` | after update | `QuoteSyncingTriggerHandler.handleAfterUpdate`. Initializes the quote checklist when `IsSyncing` is set to true. **Second trigger on `Quote`** (see one-trigger-per-object note). |
| `QuoteTrigger` | `Quote` | before insert, before update | `QuoteRenewalTypeHandler.applyRenewalQuoteType`. Normalizes the renewal quote-type field so Product Configuration Rule evaluation works for renewals. **First trigger on `Quote`.** |

## Patterns & Notes

- **Handler delegation (logic-less trigger):** 8 of 10 triggers immediately delegate to a `*Handler` /
  `*TriggerHandler` class. Exceptions: `LicenseKeyTrigger` (inline filtering before calling the email
  handler) and `QuoteLineItemExchangeRateTrigger` (substantial inline logic, no dedicated handler).
- **Two triggers per object on `Quote` and `QuoteLineItem`** — the one-trigger-per-object pattern is NOT
  enforced. Sibling-trigger ordering is undefined; treat as fragile when changing save-time behavior.
- **COLA / renewal hot zone:** `QuoteLineItemTrigger` wires in `COLAUpliftHandler` and
  `RenewalQuoteLineHandler` — the active SC-3350 COLA renewal-pricing work touches this path. Changes
  here are load-bearing for renewal pricing.
- **Currency dependency:** `QuoteLineItemExchangeRateTrigger` depends on `DatedConversionRateLookup`
  (Advanced Currency Management). Its Opportunity rate-propagation is intentionally non-atomic
  (`allOrNone=false`) to survive Opportunity validation-rule failures.
- **Managed-package object, custom trigger:** `FortraBillingEventItemTrigger` runs on the PS Cloud
  `pse__Billing_Event_Item__c` object but is fully custom (no namespace), so it is in scope here while
  the object itself is managed.
- **Authorship signals:** several triggers are headered `@author Claude Code` (Opportunity,
  QuoteLineGroup, QuoteLineItem); `FortraBillingEventItemTrigger` by german.wren (2026-02-27).
