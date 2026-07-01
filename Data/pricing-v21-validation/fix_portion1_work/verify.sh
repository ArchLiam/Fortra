#!/bin/bash
# Force-reprice a record through live V21, then dump QLI/OrderItem pricing fields.
# usage: ./verify.sh <Quote|Order> <RECORD_ID>
set -e
TYPE="$1"; ID="$2"
W="Data/pricing-v21-validation/fix_portion1_work"
cat > "$W/body.json" <<JSON
{"pricingPref":"Force","configurationPref":{"configurationMethod":"Skip"},
 "graph":{"graphId":"1","records":[{"referenceId":"ref1",
   "record":{"attributes":{"type":"$TYPE","method":"PATCH","id":"$ID"}}}]}}
JSON
echo "=== reprice $TYPE $ID ==="
sf api request rest "/services/data/v67.0/connect/rev/sales-transaction/actions/place" \
   --method POST -o FortraUAT --body "$(cat "$W/body.json")" 2>&1 | python3 -c "import json,sys;d=json.load(sys.stdin);print('isSuccess=',d.get('isSuccess'));print('errors=',d.get('errorResponse'))" 2>&1 | head
if [ "$TYPE" = "Quote" ]; then
  sf data query -o FortraUAT -q "SELECT Id,Quantity,UnitPrice,NetUnitPrice,ListPrice,NetTotalPrice,TotalLineAmount,TotalPrice,PricingTermCount,CalculationStatus,Source_List_Price__c,Base_Price__c,Pre_Partner_Price__c,CancelNetUnitPrice__c FROM QuoteLineItem WHERE QuoteId='$ID' ORDER BY Id" -r human
else
  sf data query -o FortraUAT -q "SELECT Id,Quantity,UnitPrice,NetUnitPrice,ListPrice,NetTotalPrice,TotalLineAmount,TotalPrice,PricingTermCount,Source_List_Price__c,Base_Price__c FROM OrderItem WHERE OrderId='$ID' ORDER BY Id" -r human
fi
