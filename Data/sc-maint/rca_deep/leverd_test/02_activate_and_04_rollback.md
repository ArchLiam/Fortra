# Lever-d test — activation (step 2) & rollback (step 4)

Procedure version activation for `Rev_Mgmt_Default_Pricing_Procedure` is **UI-only** (per
`reference_pricing_procedure_deploy_mechanics`); there is no supported API activate/deactivate.
ExpressionSetVersion hard-delete is **platform-blocked** — rollback = re-activate the prior version,
never delete.

## Step 2 — ACTIVATE the deployed version
1. Setup → **Pricing Procedures** (or Object Manager → ExpressionSet) → `Rev_Mgmt_Default_Pricing_Procedure`.
2. Find the version created by the `01_build_and_deploy` deploy (newest, Draft/Inactive).
3. **Record the CURRENT active version Id+number first** (this is your rollback target — today it is
   ExpressionSetVersion `9QMWC00000023eX4AQ`, **V14**).
4. Activate the new version. Confirm it became the sole Active.
5. Proceed to `03_verify.sh`.

## Step 4 — ROLLBACK (run unless you are shipping lever-d)
1. Setup → same procedure.
2. **Re-activate the prior version** you recorded in Step 2.3 (V14 `9QMWC00000023eX4AQ`).
3. Leave the lever-d version Inactive (do **not** attempt to delete it — platform-blocked).
4. (Optional) Re-run `00_preflight.sh` → gate-check should report the active definition is back to the
   pre-test state for the **runtime** version. Note: the lever-d element may remain in the *definition
   metadata* of the inactive version — that is expected and harmless (it is the inactive version).
5. Reprice the canary once more (`Force/Skip` on `0Q0WC0000038aXd0AI`) to confirm it returns to the
   pre-test committed value, closing the window cleanly.

## If lever-d PASSED and you are shipping it
- Keep the lever-d version active.
- **Downstream remediation (separate owner-gated workstream):** the existing fossils that are not in the
  5 Draft test quotes (and any that flowed to Orders/Assets) need a one-time reprice. Re-send affected
  Orders to Workday via `Order_Completed_WD__e` (see `project_workday_resubmit_mechanism`) once nets are
  correct. **Do not touch Accepted quote `00781068` / line `0QLWC000003dAaT4AU`.**
- Before any **prod** promotion, fix the `COLAUpliftTest.buildOverrideMap` 41-error drift (0% compile →
  0% coverage = hard prod-cutover blocker). It does **not** block this UAT `NoTestRun` deploy.
