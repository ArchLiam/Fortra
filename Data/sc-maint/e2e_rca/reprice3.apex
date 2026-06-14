// Discover the real RLM reprice entry point used by the managed UI.
// The Revenue Cloud "Reprice" uses ConnectApi.QuoteManagement.placeQuote or
// the platform PlaceQuote pipeline. Probe class existence safely.
String[] candidates = new String[]{};
try { Type t = Type.forName('ConnectApi.QuoteManagement'); System.debug('QuoteManagement=' + t); } catch(Exception e){ System.debug('QuoteManagement NONE'); }
try { Type t = Type.forName('ConnectApi.PlaceQuote'); System.debug('PlaceQuote=' + t); } catch(Exception e){ System.debug('PlaceQuote NONE'); }
try { Type t = Type.forName('ConnectApi.Pricing'); System.debug('Pricing=' + t); } catch(Exception e){ System.debug('Pricing NONE'); }
try { Type t = Type.forName('ConnectApi.SalesTransaction'); System.debug('SalesTransaction=' + t); } catch(Exception e){ System.debug('SalesTransaction NONE'); }
try { Type t = Type.forName('SBQQ.QuoteAPI'); System.debug('SBQQ.QuoteAPI=' + t); } catch(Exception e){ System.debug('SBQQ NONE'); }
