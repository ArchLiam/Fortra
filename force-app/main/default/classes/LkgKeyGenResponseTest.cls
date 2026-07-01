@isTest
public with sharing class LkgKeyGenResponseTest {
    
    @isTest
    static void testDefaultConstructor() {
        // When
        LkgKeyGenResponse response = new LkgKeyGenResponse();

        // Then
        System.assert(!response.isSuccess, 'Default isSuccess should be false');
        System.assertEquals('', response.message, 'Default message should be empty');
        System.assertEquals('', response.generatedKey, 'Default generatedKey should be empty');
        System.assertEquals(null, response.licenseKeyId, 'Default licenseKeyId should be null');
    }

    @isTest
    static void testSuccessResponse() {
        // Given
        String generatedKey = 'ABC123';
        Id licenseKeyId = Id.valueOf('001000000000000AAA');

        // When
        LkgKeyGenResponse response = LkgKeyGenResponse.success(generatedKey, licenseKeyId);

        // Then
        System.assert(response.isSuccess, 'Response should indicate success');
        System.assertEquals('License key generated successfully. Click {0} to view the key.', response.message, 'Success message should match expected format');
        System.assertEquals(generatedKey, response.generatedKey, 'Generated key should match input');
        System.assertEquals(licenseKeyId, response.licenseKeyId, 'License Key ID should match input');
    }

    @isTest
    static void testErrorResponse() {
        // Given
        String errorMessage = 'An error occurred during key generation.';

        // When
        LkgKeyGenResponse response = LkgKeyGenResponse.error(errorMessage);

        // Then
        System.assert(!response.isSuccess, 'Response should indicate failure');
        System.assertEquals(errorMessage, response.message, 'Error message should match input');
        System.assertEquals('', response.generatedKey, 'Generated key should be empty on error');
        System.assertEquals(null, response.licenseKeyId, 'License Key ID should be null on error');
    }
}