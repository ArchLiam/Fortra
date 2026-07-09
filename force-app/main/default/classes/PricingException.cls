/**
 * Intentional pricing-domain exception (D-18 seed). Extend for finer domain
 * errors (e.g. validation). Not used by the swallow-logging path — caught hook
 * exceptions are system types — but available for deliberate throws that should
 * be catchable and self-classifying.
 */
public virtual class PricingException extends AppException {}
