/**
 * @description Base class for intentional, catchable domain exceptions thrown by Fortra Apex,
 * distinct from system exceptions swallowed elsewhere, so deliberate domain errors can be caught
 * and classified (for example, a logger auto-deriving a category when an exception is instanceof AppException).
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public virtual class AppException extends Exception {}