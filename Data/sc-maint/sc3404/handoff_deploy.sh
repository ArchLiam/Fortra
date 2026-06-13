#!/usr/bin/env bash
# Renewal-$0 fix — deploy / verify / revert helper for Rev_Mgmt_Default_Pricing_Procedure V14
# See: "*Jira/Task/sc3403 .../11_RENEWAL_ZERO_PRICE_HANDOFF.md"
#
# Usage:
#   ./handoff_deploy.sh backup            # retrieve current live -> _live_backup/
#   ./handoff_deploy.sh deploy <dir>      # deploy edited metadata dir (V14 must be DEACTIVATED first, via UI)
#   ./handoff_deploy.sh verify            # re-retrieve live -> rchk/ and print the renewal-chain state
#   ./handoff_deploy.sh revert            # redeploy pristine V14 (V14 must be DEACTIVATED first, via UI)
#
# NOTES:
#   - API version MUST be 67.0 (v66 -> "Property 'dataType' not valid").
#   - "metadata.transfer:Finalizing" CLI error is COSMETIC; always confirm with `verify`.
#   - Activation/deactivation is done in the UI (single V14 row). NEVER "Reactivate All Dependencies".

set -uo pipefail
ORG="FortraUAT"
API="67.0"
ROOT="Data/sc-maint/sc3404"
MEMBER="ExpressionSetDefinition:Rev_Mgmt_Default_Pricing_Procedure"
PRISTINE="$ROOT/revert"   # pristine V14 package

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

print_state () {
  local f
  f="$(find "$1" -name 'Rev_Mgmt_Default_Pricing_Procedure.expressionSetDefinition' 2>/dev/null | head -1)"
  [ -z "$f" ] && { echo "  (metadata file not found under $1)"; return; }
  python3 - "$f" <<'PY'
import sys
lines=open(sys.argv[1]).read().split("\n")
# active V140 block
s=None;ab=ae=None
for i,l in enumerate(lines):
    if l.strip()=='<versions>': s=i
    elif l.strip()=='</versions>' and s is not None:
        if any('_V140</fullName>' in x for x in lines[s:i+1]): ab,ae=s,i
        s=None
if ab is None: print("  V140 block NOT found"); raise SystemExit
seg="\n".join(lines[ab:ae+1])
def field_near(name):
    # find the <steps> block whose <name> == name, then its resultIncluded
    blk=lines[ab:ae+1]
    for i,l in enumerate(blk):
        if l.strip()==f"<name>{name}</name>":
            # search outward in this steps block
            j=i
            while j>0 and blk[j].strip()!="<steps>": j-=1
            k=i
            while k<len(blk) and blk[k].strip()!="</steps>": k+=1
            sub=blk[j:k]
            ri=[x.strip() for x in sub if "<resultIncluded>" in x]
            sq=[x.strip() for x in sub if x.strip().startswith("<sequenceNumber>")]
            return (ri[0] if ri else "?", sq[0] if sq else "?")
    return ("(name not found)","")
for nm in ["DerivedPricingRenewals","DerivedProductsRenewals","DerivedProductsNonRenewal"]:
    ri,sq=field_near(nm)
    print(f"  {nm:28} {ri:28} {sq}")
import re
cl=re.search(r"DerivedProductsNonRenewal.*?<conditionLogic>(.*?)</conditionLogic>", seg, re.S)
# better: find conditionLogic inside the NonRenewal block specifically
print("  DerivedProductsNonRenewal.conditionLogic ->", end=" ")
blk=lines[ab:ae+1]
for i,l in enumerate(blk):
    if l.strip()=="<name>DerivedProductsNonRenewal</name>":
        j=i
        while j>0 and blk[j].strip()!="<steps>": j-=1
        k=i
        while k<len(blk) and blk[k].strip()!="</steps>": k+=1
        m=[x.strip() for x in blk[j:k] if "<conditionLogic>" in x]
        print(m[0] if m else "?"); break
else: print("?")
print("\n  PRISTINE expected: DerivedPricingRenewals=false, conditionLogic=1")
PY
}

case "${1:-}" in
  backup)
    sf project retrieve start -m "$MEMBER" -o "$ORG" -r "$ROOT/_live_backup" --api-version "$API"
    echo "== live state =="; print_state "$ROOT/_live_backup"
    ;;
  deploy)
    [ -z "${2:-}" ] && { echo "usage: $0 deploy <dir>"; exit 1; }
    echo "!! Confirm V14 is DEACTIVATED in the UI before deploying. Ctrl-C to abort."; read -r _
    sf project deploy start -d "$2" -o "$ORG" --api-version "$API"
    echo "(ignore a cosmetic 'metadata.transfer:Finalizing' — run: $0 verify)"
    ;;
  verify)
    rm -rf "$ROOT/rchk"
    sf project retrieve start -m "$MEMBER" -o "$ORG" -r "$ROOT/rchk" --api-version "$API"
    echo "== LIVE renewal-chain state =="; print_state "$ROOT/rchk"
    ;;
  revert)
    echo "!! Confirm V14 is DEACTIVATED in the UI before reverting. Ctrl-C to abort."; read -r _
    sf project deploy start -d "$PRISTINE" -o "$ORG" --api-version "$API"
    echo "(then reactivate V14 in UI, and run: $0 verify)"
    ;;
  *)
    echo "usage: $0 {backup|deploy <dir>|verify|revert}"; exit 1;;
esac
