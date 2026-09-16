import '../registry/design_contract_resolver.dart';
import '../runtime/prototype_runtime.dart';
import 'review_section_registry.dart';

/// Result of evaluating whether a section may be sourced from a direction.
///
/// Deterministic and non-ranking: [reason] is neutral explanatory copy.
final class ReviewSectionCompatibilityResult {
  const ReviewSectionCompatibilityResult._(this.allowed, this.reason);

  const ReviewSectionCompatibilityResult.allowed() : this._(true, null);

  const ReviewSectionCompatibilityResult.rejected(String reason) : this._(false, reason);

  final bool allowed;
  final String? reason;
}

/// Governed availability + render-compatibility evaluation for section mixes.
///
/// Availability: the source direction must actually expose the screen and the
/// governed component backing the slot.
/// Compatibility: the section must belong to the screen, the B.1D binding must
/// resolve, and the source density must be supported by that binding.
abstract final class ReviewSectionCompatibility {
  static ReviewSectionCompatibilityResult evaluate({
    required PrototypeRuntime runtime,
    required String screenId,
    required String sectionId,
    required String sourceDirectionId,
    required String baseDirectionId,
  }) {
    final definition = ReviewSectionRegistry.definition(sectionId);
    if (definition == null) {
      return const ReviewSectionCompatibilityResult.rejected('Unknown section');
    }
    if (definition.screenId != screenId) {
      return const ReviewSectionCompatibilityResult.rejected(
        'Section does not belong to this screen',
      );
    }

    final baseDirection = runtime.directions[baseDirectionId];
    final sourceDirection = runtime.directions[sourceDirectionId];
    if (baseDirection == null || sourceDirection == null) {
      return const ReviewSectionCompatibilityResult.rejected('Unknown direction');
    }

    // The base screen must actually be composed from this slot.
    if (!baseDirection.patterns.contains(definition.screenId)) {
      return const ReviewSectionCompatibilityResult.rejected(
        'Not compatible with this screen layout',
      );
    }

    final directionLabel = sourceDirectionId.toUpperCase();
    if (!sourceDirection.patterns.contains(definition.screenId)) {
      return ReviewSectionCompatibilityResult.rejected(
        'Not present in Direction $directionLabel',
      );
    }
    if (!sourceDirection.components.contains(definition.componentId)) {
      return ReviewSectionCompatibilityResult.rejected(
        'Not present in Direction $directionLabel',
      );
    }

    // B.1D render contract: the governed component binding must resolve and
    // support the source direction's density.
    try {
      final binding = DesignContractResolver.component(definition.componentId);
      if (!binding.density.containsKey(sourceDirection.canonicalDensity)) {
        return const ReviewSectionCompatibilityResult.rejected(
          'Not compatible with this screen layout',
        );
      }
    } on ArgumentError {
      return const ReviewSectionCompatibilityResult.rejected(
        'Not compatible with this screen layout',
      );
    }

    return const ReviewSectionCompatibilityResult.allowed();
  }
}
