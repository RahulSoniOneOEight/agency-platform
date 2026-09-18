library;

// Public boundary: the provider-neutral observability adapter, the narrow
// injectable transport seam, and the redaction helper. No Sentry SDK type is
// exported; provider HTTP details stay inside the concrete transport.
export 'src/http_sentry_transport.dart';
export 'src/sentry_observability_adapter.dart';
