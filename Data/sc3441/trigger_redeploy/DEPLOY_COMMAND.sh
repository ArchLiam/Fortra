#!/usr/bin/env bash
# SC-3441 — before-save trigger re-deploy to FortraUAT (CancelNetUnitPrice__c populator).
#
# DO NOT RUN until the Context Definition SalesTransactionContextExt_v2 has been
# Synced/regenerated so the compiled runtime hydration includes CancelNetUnitPrice__c.
# This trigger is the POPULATOR for real cancellations; without the context Sync the
# quote-side seed still will not fire live (the order-side direct NetUnitPrice stamp
# does not depend on the context Sync).
#
# Package contents (source format, this directory):
#   classes/CancelLineNetSeedHandler.cls        (api 62.0) — asset-net resolver + stamper
#   classes/CancelLineNetSeedHandlerTest.cls    (api 62.0) — 15 tests
#   triggers/OrderItemTrigger.trigger           (api 62.0) — NEW (OrderItem has no live trigger)
#   triggers/QuoteLineItemTrigger.trigger       (api 61.0) — REDEPLOY, preserves live api 61.0,
#                                                            adds the SC-3441 handleQuoteLines call
#
# Target org alias: FortraUAT  (NOT the "uat" alias — different org)

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- DRY RUN (validate only, no changes committed) ----
sf project deploy start \
  --target-org FortraUAT \
  --source-dir "$HERE/classes" \
  --source-dir "$HERE/triggers" \
  --test-level RunSpecifiedTests \
  --tests CancelLineNetSeedHandlerTest \
  --dry-run \
  --wait 30

# ---- REAL DEPLOY (uncomment to run after the dry-run passes) ----
# sf project deploy start \
#   --target-org FortraUAT \
#   --source-dir "$HERE/classes" \
#   --source-dir "$HERE/triggers" \
#   --test-level RunSpecifiedTests \
#   --tests CancelLineNetSeedHandlerTest \
#   --wait 30
