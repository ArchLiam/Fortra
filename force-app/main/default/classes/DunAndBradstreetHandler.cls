public with sharing class DunAndBradstreetHandler {
	
	@InvocableMethod(label='Duns Enrichment' description='Callout D&B via Mulesoft and perform enrichment')
	public static List<List<Account>> dunsEnrichment(List<DunsRequestWrapper> requests) {
		System.debug('dunsEnrichment');
		List<List<Account>> accountsToReturn = new List<List<Account>>();
		List<DunsResponseWrapper> responses = new List<DunsResponseWrapper>();

		for (DunsRequestWrapper request : requests) {
			Account account = request.account;
			System.debug('Request Duns: ' + request.duns);
			System.debug('Request Account: ' + request.account.Id + ' --- ' + request.account.DB_DUNS__c);
			// if(account.DB_DUNS__c == request.duns) {
				DunsResponseWrapper wrapper = dunsCallout(account);
				responses.add(wrapper);
			// }
		}

		for (DunsResponseWrapper wrapper : responses) {
			if(wrapper.responsePayload.errorMessage != null) {
				System.debug('DUNS Callout Error - Code: ' + wrapper.responsePayload.statusCode + ', Message: ' + wrapper.responsePayload.errorMessage);
				// throw new CalloutException('DUNS Callout Error - Code: ' + wrapper.errorCode + ', Message: ' + wrapper.errorMessage);
			} else {
				DunsResponseWrapper result = DunAndBradstreetHelper.handleDunsResponse(wrapper);
				if(result.account_Results.size() > 0) {
					accountsToReturn.add(result.account_Results);
				}
			}
		}

		return accountsToReturn;
	}
	
    public static DunsResponseWrapper dunsCallout(Account account) {
		if(String.isBlank(account.Name) && String.isBlank(account.DB_DUNS__c)) {
			System.debug('Insufficient data for DUNS callout');
			return new DunsResponseWrapper();
		}

		String accessToken = AccessTokenGenerator.generateDunsToken();	// Get Access Token

		String dunsNumber = account.DB_DUNS__c;							
		String searchTermString = account.Name;							// Required
		String countryISOAlpha2CodeString = account.BillingCountryCode;	// Required
		String addressRegionString = account.BillingStateCode;
		String addressLocalityString = account.BillingCity;
		String postalCodeString = account.BillingPostalCode;
		String streetAddressLine1String = account.BillingStreet;

		Http httpRootObj = new Http();
        HttpRequest request = new HttpRequest();
        HttpResponse response = new HttpResponse();

		String requestString = '';
		if(String.isNotBlank(dunsNumber)) {
			requestString += 'dunsNumber=' + EncodingUtil.urlEncode(dunsNumber, 'UTF-8');
		} else {
			requestString += String.isNotBlank(countryISOAlpha2CodeString) ? 'countryISOAlpha2Code=' + EncodingUtil.urlEncode(countryISOAlpha2CodeString, 'UTF-8') : 'countryISOAlpha2Code=US';
			requestString += String.isNotBlank(searchTermString) ? '&searchTerm=' + EncodingUtil.urlEncode(searchTermString, 'UTF-8') : '';
			requestString += String.isNotBlank(addressRegionString) ? '&addressRegion=' + EncodingUtil.urlEncode(addressRegionString, 'UTF-8') : '';
			requestString += String.isNotBlank(addressLocalityString) ? '&addressLocality=' + EncodingUtil.urlEncode(addressLocalityString, 'UTF-8') : '';	
			requestString += String.isNotBlank(postalCodeString) ? '&postalCode=' + EncodingUtil.urlEncode(postalCodeString, 'UTF-8') : '';
			requestString += String.isNotBlank(streetAddressLine1String) ? '&streetAddressLine1=' + EncodingUtil.urlEncode(streetAddressLine1String, 'UTF-8') : '';
		}
		System.debug('Mulesoft Callout Request String: ?' + requestString);

		request.setEndpoint('callout:Mulesoft_DUNS' + '?' + requestString);
		request.setHeader('Authorization', 'Bearer ' + accessToken);
		request.setHeader('client_id', '{!$Credential.Mulesoft_DUNS.client_id}');
		request.setHeader('client_secret', '{!$Credential.Mulesoft_DUNS.client_secret}');
        request.setMethod('GET');
		request.setTimeout(120000);
        
        try {
            response = httpRootObj.send(request);
			System.debug('Response Body: ' + response.getBody());
			DunsResponseWrapper wrapper = DunsResponseWrapper.parse(response.getBody());
			// System.debug('Response Wrapper: ' + response.getBody());
			if(wrapper == null){ // Blank response
				wrapper = new DunsResponseWrapper();
			}
			// if(String.isNotBlank(account.DB_DUNS__c) && String.isBlank(wrapper.duns)) {
			// 	wrapper.duns = account.DB_DUNS__c;
			// }
			wrapper.originating_Account = account;
			return wrapper;
        } 
        catch(Exception expObj) {
			throw expObj;
        }
    }

	public class DunsRequestWrapper {
		@InvocableVariable(label='Account' description='Account to process' required=true)
		public Account account;

		@InvocableVariable(label='Duns' description='Duns from Account')
		public String duns;
	}
}