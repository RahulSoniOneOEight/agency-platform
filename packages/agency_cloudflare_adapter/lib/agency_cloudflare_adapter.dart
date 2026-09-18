library;

// Public boundary: the provider-neutral deployment adapter, the narrow
// injectable transport seam, and the credential holder. No Cloudflare SDK type
// is exported; provider HTTP details stay inside the concrete transport.
export 'src/cloudflare_pages_deployment_adapter.dart';
export 'src/http_cloudflare_pages_transport.dart';
