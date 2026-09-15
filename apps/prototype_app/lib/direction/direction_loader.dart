import '../runtime/prototype_runtime.dart';
import '../runtime/runtime_exception.dart';
import 'prototype_direction.dart';

/// Resolves a direction from the loaded client runtime.
///
/// There is no hard-coded direction catalogue and no fallback: an unknown
/// direction is a governed [RuntimeException] rather than Direction A.
abstract final class DirectionLoader {
  static PrototypeDirection resolve(PrototypeRuntime runtime, String id) {
    final direction = runtime.directions[id];
    if (direction == null) {
      throw RuntimeException(
        code: RuntimeException.directionNotFound,
        message: 'Direction "$id" is not available for client "${runtime.clientId}".',
        clientId: runtime.clientId,
        directionId: id,
      );
    }
    return direction;
  }
}
