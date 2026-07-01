ApexClass c = [SELECT Body FROM ApexClass WHERE Name='COLAUpliftPrehook'];
String body = c.Body;
// dump the buildNetUnitPriceUpdate method region and its guard
Integer ni = body.indexOf('buildNetUnitPriceUpdate');
while (ni >= 0) {
    System.debug(LoggingLevel.ERROR, '=== OCC @' + ni + ' ===\n' + body.substring(Math.max(0,ni-100), Math.min(ni+600, body.length())));
    ni = body.indexOf('buildNetUnitPriceUpdate', ni+1);
}
// guard text around Fortra_Product_Type / storedNet
Integer gi = body.indexOf('storedNet');
if (gi>=0) System.debug(LoggingLevel.ERROR, 'STOREDNET=' + body.substring(Math.max(0,gi-300), Math.min(gi+500, body.length())));
