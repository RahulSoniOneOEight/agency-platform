import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';

import '../fixtures/fixture_repository.dart';
import '../registry/prototype_registry.dart';
import '../runtime/prototype_runtime.dart';

/// Pure renderer for one reviewed client screen.
///
/// It resolves the requested runtime direction, reuses the governed prototype
/// renderer ([PrototypeRegistry.buildPattern]) without duplicating any screen
/// implementation, and wraps only the reviewed client surface in the direction's
/// resolved theme (B.1E). It owns no review state and never applies review
/// chrome to the evaluated surface.
class ReviewComparisonHost extends StatelessWidget {
  const ReviewComparisonHost({
    super.key,
    required this.runtime,
    required this.fixtures,
    required this.directionId,
    required this.screenId,
  });

  final PrototypeRuntime runtime;
  final FixtureRepository fixtures;
  final String directionId;
  final String screenId;

  @override
  Widget build(BuildContext context) {
    final direction = runtime.directions[directionId];
    if (direction == null) {
      throw ArgumentError.value(directionId, 'directionId', 'Unknown runtime direction');
    }
    return Theme(
      data: AgencyTheme.light(runtime.themeForDirection(directionId)),
      child: PrototypeRegistry.buildPattern(screenId, direction, fixtures),
    );
  }
}
