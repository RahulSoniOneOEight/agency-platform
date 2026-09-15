import 'generated_design_bindings.dart';

/// Governed canonical-ID resolver for Flutter implementations.
///
/// The binding projection is generated from `design-contract/bindings/flutter/`
/// (canonical authority) into [generatedDesignBindings]. This resolver performs
/// exact lookups only: it never strips prefixes, guesses registry keys, or
/// selects a default. Unknown canonical IDs, variants, or densities fail
/// deterministically.
abstract final class DesignContractResolver {
  static DesignBinding binding(String canonicalId) {
    final descriptor = generatedDesignBindings[canonicalId];
    if (descriptor == null) {
      throw ArgumentError.value(
        canonicalId,
        'canonicalId',
        'Unknown canonical design contract id',
      );
    }
    return descriptor;
  }

  static String patternKey(String canonicalId) {
    final descriptor = binding(canonicalId);
    if (descriptor.kind != 'pattern') {
      throw ArgumentError.value(
        canonicalId,
        'canonicalId',
        'Canonical id is not a pattern binding',
      );
    }
    return descriptor.registryKey;
  }

  static DesignBinding component(String canonicalId) {
    final descriptor = binding(canonicalId);
    if (descriptor.kind != 'component') {
      throw ArgumentError.value(
        canonicalId,
        'canonicalId',
        'Canonical id is not a component binding',
      );
    }
    return descriptor;
  }

  static String componentVariant(String canonicalId, String canonicalVariant) {
    final descriptor = component(canonicalId);
    final resolved = descriptor.variants[canonicalVariant];
    if (resolved == null) {
      throw ArgumentError.value(
        canonicalVariant,
        'canonicalVariant',
        'Unsupported variant for $canonicalId',
      );
    }
    return resolved;
  }

  static String density(String canonicalId, String canonicalDensity) {
    final descriptor = binding(canonicalId);
    final resolved = descriptor.density[canonicalDensity];
    if (resolved == null) {
      throw ArgumentError.value(
        canonicalDensity,
        'canonicalDensity',
        'Unsupported density for $canonicalId',
      );
    }
    return resolved;
  }
}
