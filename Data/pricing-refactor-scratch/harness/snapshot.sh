#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Fortra pricing golden-snapshot capture  ·  READ-ONLY (one SOQL query, no DML)
# Captures the pricing "oracle" fields per line into a normalized, diffable TSV.
#
#   Usage:  ORG=FortraUAT ./snapshot.sh <Quote|Order> <recordId> <outfile.tsv>
#   e.g. :  ./snapshot.sh Quote 0Q0WC000001abcXYZ baselines/S05_quote.tsv
#           ./snapshot.sh Order 801WC000001defXYZ baselines/S05_order.tsv
#
# Field sets differ per object (dual-object asymmetry, INV-17):
#   Quote path uses PrehookRSNetUnitPrice__c ; Order path uses RegionalNetUnitPrice__c
#   Workday line-type oracle = OrderItem.Workday_Contract_Line_Type__c (Order only)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
OBJ="${1:?object: Quote or Order}"; RID="${2:?record Id}"; OUT="${3:?output .tsv}"
ORG="${ORG:-FortraUAT}"

if [ "$OBJ" = "Quote" ]; then
  SOQL="SELECT LineNumber, Product2.Name, Product2Id, Fortra_Product_Type__c, Quantity, \
UnitPrice, ListPrice, Base_Price__c, NetUnitPrice, NetTotalPrice, TotalPrice, Subtotal, TotalLineAmount, \
PricingTerm, PricingTermCount, PricingTermUnit, StartDate, EndDate, \
Pre_Partner_Price__c, PrehookRSNetUnitPrice__c, PartnerDiscountPercent, Partner_Discount_Percent__c, \
COLACalculatedPrice__c, COLA_Uplift_Percent__c, CancelNetUnitPrice__c \
FROM QuoteLineItem WHERE QuoteId='$RID' ORDER BY LineNumber"
elif [ "$OBJ" = "Order" ]; then
  SOQL="SELECT OrderItemNumber, Product2.Name, Product2Id, Fortra_Product_Type__c, Quantity, \
UnitPrice, ListPrice, Base_Price__c, NetUnitPrice, NetTotalPrice, TotalPrice, TotalLineAmount, \
PricingTermCount, ServiceDate, EndDate, \
Pre_Partner_Price__c, RegionalNetUnitPrice__c, PartnerDiscountPercent, \
COLACalculatedPrice__c, COLA_Uplift_Percent__c, CancelNetUnitPrice__c, \
Workday_Contract_Line_Type__c, Workday_Revenue_Category__c \
FROM OrderItem WHERE OrderId='$RID' ORDER BY OrderItemNumber"
else echo "OBJ must be Quote or Order" >&2; exit 2; fi

mkdir -p "$(dirname "$OUT")"
HERE="$(cd "$(dirname "$0")" && pwd)"
sf data query --target-org "$ORG" -q "$SOQL" --result-format csv 2>/dev/null | \
  python3 "$HERE/normalize.py" "$OUT" "$OBJ" "$RID"
