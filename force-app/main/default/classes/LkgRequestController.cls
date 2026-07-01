public with sharing class LkgRequestController {
  public class ApiResponse {
    public String status;
    public List<String> output;
  }

  public LkgKeyGenResult generateLicenseKey(String body) {
    try {
      Http http = new Http();
      HttpRequest httpRequest = new HttpRequest();
      httpRequest.setEndpoint('callout:keygen_api');
      httpRequest.setMethod('POST');
      httpRequest.setHeader('Content-Type', 'application/x-www-form-urlencoded');
      httpRequest.setBody(body);

      HttpResponse httpResponse = http.send(httpRequest);
      String responseBody = httpResponse.getBody();
      System.debug(LoggingLevel.DEBUG, 'Response Body: ' + responseBody);
      ApiResponse apiResponse = (ApiResponse) JSON.deserialize(responseBody, ApiResponse.class);

      // Check for HTTP errors
      if (httpResponse.getStatusCode() != 200) {
        throw new LkgKeyGenResponse.KeyGenException('keygen API HTTP error: ' + httpResponse.getStatusCode());
      }

      // Check for API-level errors
      if (apiResponse.status != '0') {
        String errorMessage = (apiResponse.output != null && !apiResponse.output.isEmpty())
          ? apiResponse.output[0]
          : 'Unknown error';
        throw new LkgKeyGenResponse.KeyGenException('keygen API error: ' + errorMessage);
      }

      return parseResponse(body, apiResponse);
    } catch (LkgKeyGenResponse.KeyGenException e) {
      throw e;
    } catch (Exception e) {
      throw new LkgKeyGenResponse.KeyGenException('Unexpected keygen API error: ' + e.getMessage());
    }
  }

  private LkgKeyGenResult parseResponse(String body, ApiResponse response) {
    String licenseKey = getLicenseKey(body, response);
    String serialNumber = getSerialNumber(body, response);
    return new LkgKeyGenResult(licenseKey, serialNumber, body, JSON.serialize(response));
  }

  private String getLicenseKey(String body, ApiResponse response) {
    if (body.startsWith('silo=sgavx')) {
      return getSgavxLicenseKey(response);
    } else {
      return response.output[0];
    }
  }

  private String getSgavxLicenseKey(ApiResponse response) {
    String result = '';
    String responseXml = String.join(response.output, '');
    Dom.Document doc = new Dom.Document();
    doc.load(responseXml);

    Dom.XmlNode root = doc.getRootElement();
    Dom.XmlNode signatureNode = root.getChildElement('signature', null);
    if (signatureNode != null) {
      result = signatureNode.getText();
    }

    return result;
  }

  private String getSerialNumber(String body, ApiResponse response) {
    if (!body.startsWith('silo=clearswift')) {
      return null;
    }

    return response.output.size() > 1 ? response.output[1] : null;
  }
}