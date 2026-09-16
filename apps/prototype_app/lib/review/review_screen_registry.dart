import '../registry/prototype_registry.dart';
import '../runtime/prototype_runtime.dart';

/// Governed adapter that exposes the review screen surface.
///
/// Review Mode must not invent its own screen identity: the available screens
/// are exactly the canonical pattern IDs declared by the runtime directions
/// (B.1D authority). There is no review-only alias table.
final class ReviewScreenRegistry {
  const ReviewScreenRegistry._();

  /// Deterministic union of canonical pattern IDs across all runtime directions.
  static Set<String> screenIdsFor(PrototypeRuntime runtime) {
    final ids = <String>{};
    for (final direction in runtime.directions.values) {
      ids.addAll(direction.patterns);
    }
    final sorted = ids.toList()..sort();
    return Set<String>.unmodifiable(sorted);
  }

  /// Delegates to [PrototypeRegistry.labelFor]; unknown IDs fail governedly.
  static String labelFor(String screenId) => PrototypeRegistry.labelFor(screenId);
}
