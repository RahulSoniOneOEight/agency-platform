/// Deterministic Review Mode entry request derived from the browser [Uri].
///
/// Review Mode is addressed with `/review?client=<client-id>` (or the hash-based
/// equivalent `#/review?client=<client-id>`). The parser never substitutes a
/// default client id; an absent `client` is reported as `null` so the caller can
/// surface a governed error.
final class ReviewRouteRequest {
  const ReviewRouteRequest({required this.isReviewMode, this.clientId});

  final bool isReviewMode;
  final String? clientId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReviewRouteRequest &&
        other.isReviewMode == isReviewMode &&
        other.clientId == clientId;
  }

  @override
  int get hashCode => Object.hash(isReviewMode, clientId);

  @override
  String toString() =>
      'ReviewRouteRequest(isReviewMode: $isReviewMode, clientId: $clientId)';
}

const String _reviewPath = '/review';

bool _isReviewPath(String path) => path == _reviewPath || path == '$_reviewPath/';

Uri? _parseFragment(String fragment) {
  if (fragment.isEmpty) return null;
  final Uri parsed;
  try {
    parsed = Uri.parse(fragment);
  } on FormatException {
    return null;
  }
  return parsed.path.isEmpty ? null : parsed;
}

/// Parses [uri] into a [ReviewRouteRequest].
///
/// Review Mode is detected when the path is `/review` (trailing slash tolerated)
/// or when the URL fragment path is `/review` for hash-based hosting. The client
/// id always comes from a `client` query parameter; hash-based URLs are also
/// parsed from the fragment query.
ReviewRouteRequest parseReviewRoute(Uri uri) {
  final fragmentUri = _parseFragment(uri.fragment);
  final reviewViaFragment = fragmentUri != null && _isReviewPath(fragmentUri.path);
  final reviewViaPath = _isReviewPath(uri.path);
  final isReviewMode = reviewViaPath || reviewViaFragment;

  final String? clientId;
  if (reviewViaFragment) {
    clientId =
        fragmentUri.queryParameters['client'] ?? uri.queryParameters['client'];
  } else if (reviewViaPath) {
    clientId =
        uri.queryParameters['client'] ?? fragmentUri?.queryParameters['client'];
  } else {
    clientId = uri.queryParameters['client'];
  }

  return ReviewRouteRequest(isReviewMode: isReviewMode, clientId: clientId);
}
