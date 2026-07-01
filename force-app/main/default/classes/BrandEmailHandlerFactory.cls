/**
 * Factory class to create silo-specific email handlers
 * Uses Factory pattern to instantiate the appropriate handler based on Silo
 */
public class BrandEmailHandlerFactory {
  // Map to cache handlers (improves performance)
  private static Map<String, IBrandEmailHandler> handlerCache = new Map<String, IBrandEmailHandler>();

  /**
   * Get the appropriate handler based on silo name
   * @param siloName The name of the silo (e.g., 'Clearswift', 'PowerTech', 'Automate')
   * @return IBrandEmailHandler implementation for the silo
   */
  public static IBrandEmailHandler getHandler(String siloName) {
    if (String.isBlank(siloName)) {
      System.debug('ERROR: Silo name is null or empty, using default handler');
      return BaseBrandEmailHandler.getDefaultHandler();
    }

    // Normalize silo name (remove spaces, convert to lowercase for consistency)
    String normalizedSilo = siloName.trim().replace(' ', '').toLowerCase();

    // Check cache first
    if (handlerCache.containsKey(normalizedSilo)) {
      System.debug('Returning cached handler for silo: ' + siloName);
      return handlerCache.get(normalizedSilo);
    }

    // Instantiate the appropriate handler based on silo
    IBrandEmailHandler handler;

    try {
      // Use Type system to dynamically instantiate the class
      // Class naming convention: [SiloName]EmailHandler
      String className = capitalizeFirstLetter(normalizedSilo) + 'EmailHandler';
      Type handlerType = Type.forName(className);

      if (handlerType != null) {
        handler = (IBrandEmailHandler) handlerType.newInstance();
        System.debug('Successfully instantiated handler: ' + className);
      } else {
        System.debug('No specific handler defined for silo: ' + siloName + ', using default handler');
        handler = BaseBrandEmailHandler.getDefaultHandler();
      }
    } catch (Exception e) {
      // If any error occurs during instantiation, use default handler
      System.debug(
        'Error instantiating handler for silo ' + siloName + ': ' + e.getMessage() + ', using default handler'
      );
      handler = BaseBrandEmailHandler.getDefaultHandler();
    }

    // Cache the handler
    handlerCache.put(normalizedSilo, handler);

    return handler;
  }

  /**
   * Helper method to capitalize first letter of a string
   */
  private static String capitalizeFirstLetter(String input) {
    if (String.isBlank(input)) {
      return input;
    }
    return input.substring(0, 1).toUpperCase() + input.substring(1);
  }

  /**
   * Clear the handler cache (useful for testing)
   */
  @TestVisible
  private static void clearCache() {
    handlerCache.clear();
  }

  /**
   * Custom exception for brand handler errors
   */
  public class BrandHandlerException extends Exception {
  }
}