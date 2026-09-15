import '../direction/prototype_direction.dart';
import 'generated_design_bindings.dart';

/// Governed canonical-ID resolver for Flutter implementations.
///
/// The binding projection is generated from `design-contract/bindings/flutter/`
/// (canonical authority) into [generatedDesignBindings]. This resolver performs
/// exact lookups only: it never strips prefixes, guesses registry keys, or
/// selects a default. Unknown canonical IDs, variants, or densities fail
/// deterministically.
abstract final class DesignContractResolver {
  static DesignBinding _binding(String canonicalId) {
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
    final descriptor = _binding(canonicalId);
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
    final descriptor = _binding(canonicalId);
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
    final descriptor = _binding(canonicalId);
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

  /// Validates every canonical reference in [direction] against the generated
  /// binding projection: patterns, components, component variants, and the
  /// direction density for each referenced component.
  ///
  /// This is a pure parity helper for tests and runtime validation. It performs
  /// no rendering and never falls back for an unknown reference.
  static void validateDirection(PrototypeDirection direction) {
    for (final patternId in direction.patterns) {
      patternKey(patternId);
    }
    for (final componentId in direction.components) {
      component(componentId);
      density(componentId, direction.canonicalDensity);
    }
    for (final variant in direction.componentVariants) {
      if (!direction.components.contains(variant.component)) {
        throw ArgumentError.value(
          variant.component,
          'component',
          'Variant component must be listed in components',
        );
      }
      componentVariant(variant.component, variant.variant);
    }
  }
}
