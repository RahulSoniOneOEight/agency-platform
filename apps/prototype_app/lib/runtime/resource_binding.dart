/// Typed representation of a canonical B.1C resource binding.
///
/// The `id` is the canonical semantic resource ID (for example
/// `asset.home.hero`, `icon.commerce.cart`, `motion.checkout.success`). The
/// remaining fields are passed through unchanged from the generated bundle so
/// that provider-specific descriptors survive generation and parsing.
class ResourceBinding {
  const ResourceBinding({
    required this.id,
    required this.candidateId,
    required this.source,
    required this.type,
    required this.asset,
    this.providerExtension,
  });

  final String id;
  final String candidateId;
  final String source;
  final String type;
  final Map<String, dynamic> asset;
  final Map<String, dynamic>? providerExtension;

  factory ResourceBinding.fromMap(String id, Map<String, dynamic> map) {
    String requiredString(String key) {
      final value = map[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Missing resource binding field: $id.$key');
      }
      return value;
    }

    final asset = map['asset'];
    if (asset is! Map) {
      throw FormatException('Missing resource binding asset: $id');
    }

    final providerExtension = map['provider_extension'];
    if (providerExtension != null && providerExtension is! Map) {
      throw FormatException('Invalid resource binding provider_extension: $id');
    }

    return ResourceBinding(
      id: id,
      candidateId: requiredString('candidate_id'),
      source: requiredString('source'),
      type: requiredString('type'),
      asset: Map<String, dynamic>.from(asset),
      providerExtension: providerExtension == null
          ? null
          : Map<String, dynamic>.from(providerExtension),
    );
  }
}
