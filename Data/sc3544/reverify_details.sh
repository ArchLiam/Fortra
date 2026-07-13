cd /Users/liamjeong/Documents/Code/Fortra
QIDS="0Q0WC000002VENJ 0Q0WC0000037rFZ 0Q0WC0000039i05 0Q0WC0000039i3J 0Q0WC0000039i4v 0Q0WC000003FapR 0Q0WC000003FbFF 0Q0WC000003FbLh 0Q0WC000003FoMA 0Q0WC000003GNi5 0Q0WC000003GOO1 0Q0WC000003GPaD 0Q0WC000003IIT0 0Q0WC000003IbiX"
echo "=== reprice the 14 detail-bearing quotes (fix should skip detail lines, no batch failure) ==="
for q in $QIDS; do
  sf api request rest "/services/data/v64.0/actions/custom/flow/Fortra_Quote_Reprice" --method POST --body "{\"inputs\":[{\"QuoteId\":\"$q\"}]}" -o FortraUAT 2>/dev/null >/dev/null
  echo -n "."
done
echo " done"
echo "=== wait 90s for async ==="
sleep 90
echo "=== NEW QuotePriceStampQueueable jobs in last 5 min: any Failed? ==="
sf data query -o FortraUAT -q "SELECT Status, COUNT(Id) n FROM AsyncApexJob WHERE JobType='Queueable' AND ApexClass.Name='QuotePriceStampQueueable' AND CreatedDate=LAST_N_MINUTES:5 GROUP BY Status" --result-format csv 2>/dev/null | grep -vE "^Warning|Querying"
echo ""
echo "=== the 15 detail lines: should stay NULL (correctly skipped, no error) ==="
sf data query -o FortraUAT -q "SELECT COUNT(Id) still_null FROM QuoteLineItem WHERE Id IN ('0QLWC000002q2Sn4AI','0QLWC000003d2QR4AY','0QLWC000003euBR4AY','0QLWC000003euEf4AI','0QLWC000003euGI4AY','0QLWC000003kkKf4AI','0QLWC000003kkfd4AA','0QLWC000003kkm54AA','0QLWC000003kySU4AY','0QLWC000003lZi94AE','0QLWC000003laPh4AI','0QLWC000003lbX34AI','0QLWC000003nWpr4AE','0QLWC000003npkP4AQ','0QLWC000003npkQ4AQ') AND UnitPrice = null" 2>/dev/null | grep -vE "Warning|Querying"
