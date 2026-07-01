/**
 * Template resolver for License Key email templates
 * Handles template resolution based on Product Code and Key Type
 * Uses Custom Metadata Type: LKG_Product__mdt
 */
public class LicenseKeyTemplateResolver {
  /**
   * Inner class to define email template configurations
   * Maps to LKG_Product__mdt Custom Metadata Type
   */
  public class TemplateConfig {
    public String productName { get; set; }
    public String genericTemplate { get; set; }
    public String specificTemporaryTemplate { get; set; }
    public String permanentTemplate { get; set; }
    public String subscriptionTemplate { get; set; }

    public TemplateConfig(
      String productName,
      String genericTemplate,
      String specificTemporaryTemplate,
      String permanentTemplate,
      String subscriptionTemplate
    ) {
      this.productName = productName;
      this.genericTemplate = genericTemplate;
      this.specificTemporaryTemplate = specificTemporaryTemplate;
      this.permanentTemplate = permanentTemplate;
      this.subscriptionTemplate = subscriptionTemplate;
    }

    /**
     * Get template name based on normalized key type
     */
    public String getTemplateForKeyType(String normalizedKeyType) {
      if (normalizedKeyType == 'generic') {
        return this.genericTemplate;
      } else if (normalizedKeyType == 'specific/temporary') {
        return this.specificTemporaryTemplate;
      } else if (normalizedKeyType == 'permanent') {
        return this.permanentTemplate;
      } else if (normalizedKeyType == 'subscription') {
        return String.isNotBlank(this.subscriptionTemplate) ? this.subscriptionTemplate : this.permanentTemplate; // Fallback to permanent if subscription not defined
      }
      return null;
    }
  }

  // Cache for template configurations to avoid repeated queries
  private static Map<String, TemplateConfig> templateCache = new Map<String, TemplateConfig>();

  /**
   * Query and build template configuration for a specific product identifier
   * @param productIdentifier The unique product identifier to query
   * @return TemplateConfig or null if not found
   */
  private static TemplateConfig queryTemplateConfig(String productIdentifier) {
    // Check cache first
    String normalizedIdentifier = productIdentifier.toLowerCase();

    if (templateCache.containsKey(normalizedIdentifier)) {
      System.debug('LicenseKeyTemplateResolver: Returning cached config for Product Identifier: ' + productIdentifier);
      return templateCache.get(normalizedIdentifier);
    }

    // Query specific product identifier from Custom Metadata Type
    List<LKG_Product__mdt> mappings = [
      SELECT
        License_Key_Product_Name__c,
        Generic_Email_Template_API_Name__c,
        SpecificTemp_Email_Template_API_Name__c,
        Permanent_Email_Template_API_Name__c,
        Subscription_Email_Template_API_Name__c
      FROM LKG_Product__mdt
      WHERE developername = :productIdentifier
      LIMIT 1
    ];

    if (mappings.isEmpty()) {
      System.debug(
        'LicenseKeyTemplateResolver: No template mapping found for Product Identifier: ' + productIdentifier
      );
      return null;
    }

    LKG_Product__mdt mapping = mappings[0];
    TemplateConfig config = new TemplateConfig(
      mapping.License_Key_Product_Name__c,
      mapping.Generic_Email_Template_API_Name__c,
      mapping.SpecificTemp_Email_Template_API_Name__c,
      mapping.Permanent_Email_Template_API_Name__c,
      mapping.Subscription_Email_Template_API_Name__c
    );

    // Cache the result
    templateCache.put(normalizedIdentifier, config);
    System.debug(
      'LicenseKeyTemplateResolver: Loaded and cached template config for Product Identifier: ' + productIdentifier
    );

    return config;
  }

  /**
   * Get email template name for a License Key
   * Main entry point for template resolution
   * @param licenseKey The License Key object with LKG_Product_Identifier_Name__c and Key_Type__c
   * @return The email template API name
   */
  public static String getTemplateName(License_Key__c licenseKey) {
    System.debug('LicenseKeyTemplateResolver.getTemplateName called');

    // Validate required fields
    if (String.isBlank(licenseKey.Key_Type__c)) {
      throw new IllegalArgumentException('Key Type is required to determine email template');
    }

    if (String.isBlank(licenseKey.LKG_Product_Identifier_Name__c)) {
      throw new IllegalArgumentException('LKG Product Identifier is required to determine email template');
    }

    String productIdentifier = licenseKey.LKG_Product_Identifier_Name__c.trim();

    System.debug('Product Identifier: ' + productIdentifier);
    System.debug('Key Type: ' + licenseKey.Key_Type__c);

    return resolveTemplateFromMap(productIdentifier, licenseKey.Key_Type__c);
  }

  /**
   * Helper method to retrieve template name by querying configuration
   * @param productIdentifier The unique product identifier
   * @param keyType The key type (e.g., 'Generic', 'Specific/Temporary')
   * @return The email template API name
   */
  private static String resolveTemplateFromMap(String productIdentifier, String keyType) {
    // Query configuration for this product identifier
    TemplateConfig config = queryTemplateConfig(productIdentifier);

    if (config == null) {
      throw new IllegalArgumentException(
        'No email templates defined for Product Identifier: ' +
          productIdentifier +
          '. Please configure LKG_Product__mdt for this product identifier.'
      );
    }

    String normalizedKeyType = normalizeKeyType(keyType);
    String templateName = config.getTemplateForKeyType(normalizedKeyType);

    if (String.isBlank(templateName)) {
      throw new IllegalArgumentException(
        'No email template defined for Product Identifier: ' +
          productIdentifier +
          ' (' +
          config.productName +
          '), Key Type: ' +
          keyType +
          '. Please configure the appropriate template in LKG_Product__mdt.'
      );
    }

    System.debug('Resolved template name: ' + templateName);
    System.debug('Product: ' + config.productName);
    return templateName;
  }

  /**
   * Helper method to normalize key type for map lookup
   * Converts various key type formats to standardized lowercase format
   */
  private static String normalizeKeyType(String keyType) {
    String normalized = keyType.trim().toLowerCase();

    // Map variations to standard keys
    if (normalized.contains('generic')) {
      return 'generic';
    } else if (normalized.contains('specific') || normalized.contains('temporary')) {
      return 'specific/temporary';
    } else if (normalized.contains('permanent')) {
      return 'permanent';
    } else if (normalized.contains('subscription')) {
      return 'subscription';
    }

    // Return as-is if no mapping found (will fail in map lookup)
    return normalized;
  }

  /**
   * Get the template configuration for a product identifier (for testing/debugging)
   * @param productIdentifier The unique product identifier
   * @return TemplateConfig or null if not found
   */
  @TestVisible
  private static TemplateConfig getTemplateConfig(String productIdentifier) {
    return queryTemplateConfig(productIdentifier);
  }

  /**
   * Check if a product identifier has template configuration
   * @param productIdentifier The unique product identifier
   * @return true if templates are configured for this product identifier
   */
  public static Boolean hasTemplateConfig(String productIdentifier) {
    TemplateConfig config = queryTemplateConfig(productIdentifier);
    return config != null;
  }

  /**
   * Clear the template cache (useful for testing)
   */
  @TestVisible
  private static void clearCache() {
    templateCache.clear();
  }
}