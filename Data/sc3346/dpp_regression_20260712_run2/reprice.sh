#!/bin/bash
# Usage: reprice.sh <quoteId> <label> <passes>
# Snapshots oracle before, then Force-reprices <passes> times, snapshotting after each pass.
# Writes JSON snapshots to snap/<label>_p{0..N}.json
set -e
QID="$1"; LABEL="$2"; PASSES="${3:-2}"
DIR="/Users/liamjeong/Documents/Code/Fortra/Data/sc3346/dpp_regression_20260712_run2/snap"
ORACLE="SELECT Id, LineNumber, Product2.ProductCode, Product2.Fortra_Product_Type__c, Fortra_Product_Type__c, PricebookEntry.ProductSellingModel.SellingModelType, PricebookEntry.IsDerived, Quantity, CurrencyIsoCode, ListPrice, UnitPrice, NetUnitPrice, NetTotalPrice, Subtotal, TotalPrice, TotalLineAmount, Base_Price__c, Source_List_Price__c, Prior_Partner_Discount__c, Prior_Discretionary_Discount__c, PartnerDiscountPercent, Discount, COLA_Uplift_Percent__c, COLACalculatedPrice__c, QuoteAction.Type, QuoteAction.SourceAsset.Price, QuoteAction.SourceAsset.Product2.Fortra_Product_Type__c FROM QuoteLineItem WHERE QuoteId='$QID' ORDER BY LineNumber"

snap() { sf data query -o FortraUAT --json --query "$ORACLE" > "$DIR/${LABEL}_p${1}.json" 2>/dev/null; }
reprice() {
  printf '{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},"graph":{"graphId":"g1","records":[{"referenceId":"ref1","record":{"attributes":{"type":"Quote","method":"PATCH","id":"%s"}}}]}}' "$QID" > /tmp/rp_${LABEL}.json
  sf api request rest "/services/data/v64.0/connect/rev/sales-transaction/actions/place" --method POST -o FortraUAT --body "@/tmp/rp_${LABEL}.json" 2>/dev/null
}

echo "[$LABEL] snapshot p0 (before)"; snap 0
for p in $(seq 1 "$PASSES"); do
  echo "[$LABEL] reprice pass $p"
  RESP=$(reprice)
  OK=$(echo "$RESP" | python3 -c "import sys,json;
try:
  d=json.load(sys.stdin); print(d.get('isSuccess'))
except: print('PARSE_ERR')" 2>/dev/null)
  echo "$RESP" > "$DIR/${LABEL}_repriceresp_p${p}.json"
  echo "  isSuccess=$OK"
  snap "$p"
done
echo "[$LABEL] done"
