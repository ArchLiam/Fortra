@isTest
global class LkgHttpCalloutMock implements HttpCalloutMock {
  global HTTPResponse respond(HTTPRequest request) {
    HttpResponse response = new HttpResponse();
    response.setStatusCode(200);
    String requestBody = request.getBody();

    switch on request.getEndpoint() {
      when 'callout:keygen_api' {
        LkgRequestController.ApiResponse apiResponse = new LkgRequestController.ApiResponse();
        apiResponse.status = '0';
        if (requestBody.startsWith('silo=sgavx')) {
          apiResponse.output = new List<String>{ '<license><signature>sgavx_key_string</signature></license>' };
        } else if (requestBody.startsWith('silo=clearswift')) {
          apiResponse.output = new List<String>{ 'clearswift_key_string', 'clearswift_serial_number' };
        } else {
          apiResponse.output = new List<String>{ 'default_key_string' };
        }
        response.setBody(JSON.serialize(apiResponse));
        return response;
      }
      when else {
        response.setBody('{"status": "value", "output": ["default_key_string"]}');
        return response;
      }
    }
  }
}