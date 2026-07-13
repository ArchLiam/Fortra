#!/usr/bin/env bash
# RCA full-functionality RE-RUN 2026-07-09 — reprice-twice + BEFORE/MID/AFTER snapshots.
# Covers S1-S14 golden scenarios + the 6 reprice-based §T ticket quotes.
# WRITES = reprice flow only (idempotent, authorized). Snapshots read-only.
set -uo pipefail
ORG=FortraUAT
HARNESS="/Users/liamjeong/Documents/Code/Fortra/Data/pricing-refactor-scratch/harness"
OUT="/Users/liamjeong/Documents/Code/Fortra/Data/pricing-refactor-scratch/rca_fulltest_20260708/run0710"
PREV="/Users/liamjeong/Documents/Code/Fortra/Data/pricing-refactor-scratch/rca_fulltest_20260708/snap"
mkdir -p "$OUT"
LOG="$OUT/reprice_log.tsv"; echo -e "scenario\tquote\tr1\tr2" > "$LOG"

declare -a SCN=(
  "S1:0Q0WC000003IIT0" "S2_S11:0Q0WC000003GMu5" "S3:0Q0WC000003IKkv" "S4:0Q0WC0000028bsk"
  "S5:0Q0WC000003IKeT" "S6:0Q0WC0000035dGj" "S7:0Q0WC0000039bwH" "S9:0Q0WC000003Fr77"
  "S10:0Q0WC000003ICoz" "S11b:0Q0WC000003FcrF" "S12:0Q0WC000002RK6g" "S13:0Q0WC000003FapR" "S14:0Q0WC0000028HhT"
  "T3544_Ifvp:0Q0WC000003Ifvp" "T3544_F55h:0Q0WC000003F55h" "T3544_Ih3B:0Q0WC000003Ih3B"
  "T3350_Ibx3:0Q0WC000003Ibx3" "T3346_Xkn:0Q0WC0000035Xkn" "T3384_xy9:0Q0WC0000036xy9"
)
reprice(){ sf api request rest "/services/data/v64.0/actions/custom/flow/Fortra_Quote_Reprice" \
    --method POST --body "{\"inputs\":[{\"QuoteId\":\"$1\"}]}" -o "$ORG" 2>&1 \
    | sed -n 's/.*\("isSuccess": *[a-z]*\).*/\1/p' | head -1; }

for pair in "${SCN[@]}"; do
  scn="${pair%%:*}"; q="${pair#*:}"
  ORG=$ORG "$HARNESS/snapshot.sh" Quote "$q" "$OUT/${scn}.before.tsv" >/dev/null 2>&1
  r1=$(reprice "$q"); ORG=$ORG "$HARNESS/snapshot.sh" Quote "$q" "$OUT/${scn}.mid.tsv" >/dev/null 2>&1
  r2=$(reprice "$q"); ORG=$ORG "$HARNESS/snapshot.sh" Quote "$q" "$OUT/${scn}.after.tsv" >/dev/null 2>&1
  echo -e "${scn}\t${q}\t${r1}\t${r2}" >> "$LOG"
  echo ">>> ${scn} (${q})  r1=[${r1}] r2=[${r2}]"
done
echo "=== DONE ==="
