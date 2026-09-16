import '../runtime/prototype_runtime.dart';
import 'review_state.dart';

/// Display-only preview direction: the restored client selection when present,
/// otherwise the runtime's declared default. Never a decision.
String resolvePreviewDirection(PrototypeRuntime runtime, ReviewState state) =>
    state.selectedDirection ?? runtime.defaultDirection;
