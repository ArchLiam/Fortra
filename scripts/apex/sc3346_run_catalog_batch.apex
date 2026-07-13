// SC-3346 go-forward catalog completion — enqueue the additive catalog batch (COMMIT).
// Scope 50 products/chunk (~1,050 DML rows/exec, 10k-safe). Idempotent; re-run fills only gaps.
// For a projection-only run, pass true (dry-run) instead of false.
Id jobId = Database.executeBatch(new RenewalMaintenanceCatalogProvisionBatch(false), 50);
System.debug(LoggingLevel.ERROR, 'RenewalMaintenanceCatalogProvisionBatch enqueued: ' + jobId);
