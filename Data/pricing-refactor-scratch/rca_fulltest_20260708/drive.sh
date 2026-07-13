#!/usr/bin/env bash
# RCA full-functionality capture driver — reprice-twice + snapshot BEFORE/MID/AFTER per scenario.
# WRITES = reprice flow calls only (authorized). Snapshots are read-only SOQL.
set -uo pipefail
ORG=FortraUAT
HARNESS="/Users/liamjeong/Documents/Code/Fortra/Data/pricing-refactor-scratch/harness"
OUT="/Users/liamjeong/Documents/Code/Fortra/Data/pricing-refactor-scratch/rca_fulltest_20260708"
mkdir -p "$OUT/snap"
LOG="$OUT/reprice_log.tsv"
echo -e "scenario\tquote\tphase\tisSuccess\terrors" > "$LOG"

# scenario -> quote  (S2 and S11 share GMu5; capture once as GMu5)
declare -a SCN=(
  "S1:0Q0WC000003IIT0"
  "S2_S11:0Q0WC000003GMu5"
  "S3:0Q0WC000003IKkv"
  "S4:0Q0WC0000028bsk"
  "S5:0Q0WC000003IKeT"
  "S6:0Q0WC0000035dGj"
  "S7:0Q0WC0000039bwH"
  "S9:0Q0WC000003Fr77"
  "S10:0Q0WC000003ICoz"
  "S11b:0Q0WC000003FcrF"
  "S12:0Q0WC000002RK6g"
  "S13:0Q0WC000003FapR"
  "S14:0Q0WC0000028HhT"
)

reprice() {  # $1=quoteId -> prints "isSuccess<TAB>errors"
  local qid="$1" resp iss errs
  resp="$(sf api request rest "/services/data/v64.0/actions/custom/flow/Fortra_Quote_Reprice" \
      --method POST --body "{\"inputs\":[{\"QuoteId\":\"$qid\"}]}" -o "$ORG" 2>&1)"
  # parse from first '[' (CLI prepends warning lines)
  local json="${resp#*[}"; json="[${json}"
  iss="$(printf '%s' "$json" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); r=d[0] if isinstance(d,list) else d
    print(str(r.get("isSuccess")))
except Exception as e:
    print("PARSE_ERR")' 2>/dev/null)"
  errs="$(printf '%s' "$json" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); r=d[0] if isinstance(d,list) else d
    es=r.get("errors") or []
    print("; ".join((e.get("message") or e.get("statusCode","")) for e in es) if es else "")
except Exception:
    print("")' 2>/dev/null)"
  [ -z "$iss" ] && iss="EMPTY_RESP"
  printf '%s\t%s' "$iss" "$errs"
}

for pair in "${SCN[@]}"; do
  scn="${pair%%:*}"; qid="${pair#*:}"
  echo ">>> $scn ($qid)"
  ORG=$ORG "$HARNESS/snapshot.sh" Quote "$qid" "$OUT/snap/${scn}.before.tsv" >/dev/null 2>&1
  r1="$(reprice "$qid")"; echo -e "${scn}\t${qid}\treprice1\t${r1}" >> "$LOG"
  ORG=$ORG "$HARNESS/snapshot.sh" Quote "$qid" "$OUT/snap/${scn}.mid.tsv" >/dev/null 2>&1
  r2="$(reprice "$qid")"; echo -e "${scn}\t${qid}\treprice2\t${r2}" >> "$LOG"
  ORG=$ORG "$HARNESS/snapshot.sh" Quote "$qid" "$OUT/snap/${scn}.after.tsv" >/dev/null 2>&1
  echo "    r1=[$r1]  r2=[$r2]"
done
echo "=== DONE ==="
