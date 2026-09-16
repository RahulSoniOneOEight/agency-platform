import '../runtime/prototype_runtime.dart';
import 'review_screen_registry.dart';

/// Thin governed adapter over the review screen surface.
///
/// This is not a second registry: it holds no alias table and invents no
/// identity. Direction order comes from [PrototypeRuntime.allowedDirections],
/// the governed screen list is delegated to [ReviewScreenRegistry], and
/// availability is derived from the direction's declared patterns alone.
abstract final class ReviewScreenAvailability {
  /// The runtime's declared direction order, copied and unmodifiable.
  static List<String> orderedDirections(PrototypeRuntime runtime) =>
      List<String>.unmodifiable(runtime.allowedDirections);

  /// The governed screen list: the sorted union from [ReviewScreenRegistry].
  static List<String> screens(PrototypeRuntime runtime) {
    final sorted = ReviewScreenRegistry.screenIdsFor(runtime).toList()..sort();
    return List<String>.unmodifiable(sorted);
  }

  /// True only when [directionId] exists and declares [screenId].
  ///
  /// Unknown direction or screen IDs return `false`; they never throw.
  static bool isSupported(
    PrototypeRuntime runtime,
    String directionId,
    String screenId,
  ) {
    final direction = runtime.directions[directionId];
    if (direction == null) return false;
    return direction.patterns.contains(screenId);
  }

  /// Delegates to [ReviewScreenRegistry.labelFor]; unknown IDs throw.
  static String labelFor(String screenId) => ReviewScreenRegistry.labelFor(screenId);
}
