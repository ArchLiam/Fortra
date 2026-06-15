#!/bin/bash
# ============================================================================
# LEVER-D (H5) TEST — STEP 1: BUILD (drift-safe) + DEPLOY   ⚠️ MUTATING
# Run ONLY inside an authorized offline republish window, AFTER 00_preflight
# reported gate-check = ABSENT. Requires owner go (co-owned V14, ~100k lines).
# ============================================================================
set -euo pipefail
ORG="FortraUAT"
D="Data/sc-maint/rca_deep/leverd_test"
LIVE=$(find "$D/run/live" -name "Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition" | head -1)
[ -n "$LIVE" ] || { echo "No fresh retrieve found — run 00_preflight.sh first."; exit 1; }

echo "### 1. Build the deploy package = FRESH live V14 + RenMaintCOLA group (drift-safe) ###"
rm -rf "$D/run/deploy"
python3 "$D/build_deploy.py" "$LIVE" "$D/element_group.xml" "$D/run/deploy"

echo
echo "### 2. (Per reference_pricing_procedure_deploy_mechanics) DEACTIVATE active V14 first ###"
echo "   >>> Do this in Setup UI (Pricing Procedure > Rev_Mgmt_Default_Pricing_Procedure > deactivate),"
echo "   >>> OR via the team's standard deactivation step. Procedure activation is UI-only."
read -p "   Press ENTER once the active version is DEACTIVATED (offline window open)... " _

echo
echo "### 3. Deploy the rebuilt definition (api 67, --metadata-dir, NoTestRun) ###"
echo "   NOTE: the CLI may throw 'Missing message metadata.transfer:Finalizing' — this is COSMETIC."
echo "   The deploy still processes. Verify via the printed Deploy ID / Setup > Deployment Status,"
echo "   NOT the CLI exit code."
sf project deploy start -o "$ORG" --api-version 67 \
  --metadata-dir "$D/run/deploy" \
  --test-level NoTestRun \
  2>&1 | grep -vE "Warning: @salesforce" | tee "$D/run/deploy_result.txt" || true
echo
echo "   Confirm component success:"
echo "     sf project deploy report -o $ORG    # or Setup > Deployment Status"
echo
echo "### 4. ACTIVATE the new version (UI-only) ###"
echo "   >>> In Setup, activate the newly-deployed version of Rev_Mgmt_Default_Pricing_Procedure."
echo "   >>> Record the new ExpressionSetVersion Id + number for rollback."
echo
echo "BUILD+DEPLOY STEP DONE. Activate in UI, then run 03_verify.sh."
