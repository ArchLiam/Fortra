public class DunsResponseWrapper {
	// Internal
	public Account originating_Account;			// N/A
	public List<Account> account_Results;		// N/A
	public Boolean perform_Enrichment;			// N/A

	// Payload
	public ResponsePayload responsePayload;
	public class ResponsePayload {
        // Success
		public String status;
        public String message;
		public Integer count;
        public List<DunsResult> data;
		public String correlationId;

		// Failure
		public String reasonPhrase;
		public Integer statusCode; 
		public String errorMessage;
		public String errorDescription;
    }

	public class DunsResult {
		public CompanyDetail sitesDuns;
        public CompanyDetail domesticDuns;
        public CompanyDetail globalDuns;
    }

	public class CompanyDetail {
		public String duns;						// DB_DUNS__c
		public String description;				// DB_Industry__c
		public String globalUltimateDuns;		// DB_Global_Ultimate_DUNS__c
		public String domesticUltimateDuns;		// DB_Domestic_Ultimate_DUNS__c
		public String primaryName;				// DB_Global_Ultimate_Name__c
		public String blockID;					// DB_Block_Id__c
		public String blockStatus;				// DB_Block_Status__c
		public String blockStatusReason;		// DB_Block_Reason__c
		public String industryCodes;			// DB_Industry__c
		public String telephoneNumber;			// DB_Telephone_Number__c
		public String operatingStatus;			// DB_Operating_Status__c
		public String countryCode;				// DB_Address__CountryCode__s
		public String city;						// DB_Address__City__s
		public String stateCode;				// DB_Address__StateCode__s
		public String postalCode;				// DB_Address__PostalCode__s
		public String street;					// DB_Address__Street__s
		public String numberOfEmployeesScope;	// DB_Number_of_Employees_Scope__c
		public String yearlyRevenueCurrency;	// DB_Yearly_Revenue_Currency__c
		public String yearlyRevenue;			// DB_Yearly_Revenue__c
		public Date startDate;					// DB_Start_Date__c
		public Date incorporatedDate; 			// DB_Incorporated_Date__c
		public String fiscalYearEnd;
		public Integer dnbCode;					// DB_Code__c
		public Integer numberOfEmployees;		// DB_Number_of_Employees__c
		public WebsiteAddress websiteAddress;	// See subclass
		public Decimal latitude;
        public Decimal longitude;
	}
	
	public class WebsiteAddress {
		public String url;						// DB_Website__c
		public String domainName;
	}

	// Standard static method for easy deserialization
	public static DunsResponseWrapper parse(String jsonString) {
        return (DunsResponseWrapper) System.JSON.deserialize(jsonString, DunsResponseWrapper.class);
    }
}