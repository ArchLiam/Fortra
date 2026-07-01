public class AccessTokenGenerator {
    
	public static String generateDunsToken() {
        String token = null;
		Http httpRootObj = new Http();
        HttpRequest request = new HttpRequest();
        HttpResponse response = new HttpResponse();
        
		String requestBody = 
			'grant_type=client_credentials' + '&' + 
			'scope={!$Credential.Microsoft_JWT_for_DUNS.scope}' + '&' +
			'client_id={!$Credential.Microsoft_JWT_for_DUNS.client_id}' + '&' +
			'client_secret={!$Credential.Microsoft_JWT_for_DUNS.client_secret}'
		;

		request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
		request.setEndpoint('callout:' + 'Microsoft_JWT_for_DUNS');
		request.setBody(requestBody);
		request.setTimeout(120000);
        request.setMethod('GET');
        
        try {
            response = httpRootObj.send(request);
			Map<String, Object> deserializedMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
			token = (String) deserializedMap.get('access_token');
        } 
        catch(Exception expObj) {
			throw expObj;
        }
        return token;
    }
}