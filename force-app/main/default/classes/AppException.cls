/**
 * Base class for INTENTIONAL, catchable domain exceptions thrown by Fortra Apex
 * (D-18 seed). System exceptions caught in swallow blocks are NOT of this type;
 * this exists so deliberate domain errors can be caught and classified. A logger
 * may auto-derive a category when an exception `instanceof AppException`.
 */
public virtual class AppException extends Exception {}
