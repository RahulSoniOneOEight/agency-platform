library;

// Public boundary: the provider-neutral analytics adapter, the narrow
// injectable transport seam, and the credential holder. No GA4 SDK type is
// exported; Measurement Protocol HTTP details stay inside the concrete
// transport.
export 'src/ga4_analytics_adapter.dart';
export 'src/http_ga4_transport.dart';
