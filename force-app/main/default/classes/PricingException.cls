/**
 * @description Intentional pricing-domain exception type extending AppException,
 * available for deliberate, catchable, self-classifying throws in the pricing
 * domain; can be extended for finer-grained domain errors such as validation.
 * @author Liam Jeong <liam.jeong@coastalcloud.us>
 */
public virtual class PricingException extends AppException {}