import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';

import 'direction/direction_loader.dart';
import 'fixtures/fixture_repository.dart';
import 'runtime/prototype_runtime.dart';
import 'runtime/runtime_exception.dart';
import 'screens/prototype_shell.dart';
import 'screens/runtime_error_screen.dart';

class PrototypeApp extends StatefulWidget {
  const PrototypeApp({
    super.key,
    required this.runtime,
    this.requestedDirection,
  });

  final PrototypeRuntime runtime;

  /// Explicit `?direction=` value. When null the runtime's declared
  /// `default_direction` is used. An explicit unknown value is an error and
  /// never falls back to Direction A.
  final String? requestedDirection;

  @override
  State<PrototypeApp> createState() => _PrototypeAppState();
}

class _PrototypeAppState extends State<PrototypeApp> {
  late final FixtureRepository _fixtures = FixtureRepository.fromRuntime(widget.runtime);
  String? _directionId;
  RuntimeException? _error;

  @override
  void initState() {
    super.initState();
    final requested = widget.requestedDirection ?? widget.runtime.defaultDirection;
    try {
      DirectionLoader.resolve(widget.runtime, requested);
      _directionId = requested;
    } on RuntimeException catch (error) {
      _error = error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final theme = AgencyTheme.light(seedColor: _seedColor(widget.runtime.seedColor));
    if (error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Agency Prototype',
        theme: theme,
        home: RuntimeErrorScreen(error: error),
      );
    }

    final direction = widget.runtime.directions[_directionId]!;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Agency Prototype',
      theme: theme,
      home: Scaffold(
        appBar: AppBar(
          title: Text(direction.name),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SegmentedButton<String>(
                  segments: [
                    for (final id in widget.runtime.allowedDirections)
                      ButtonSegment(value: id, label: Text(id.toUpperCase())),
                  ],
                  selected: {_directionId!},
                  onSelectionChanged: (selection) =>
                      setState(() => _directionId = selection.first),
                  showSelectedIcon: false,
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Text(
                '${direction.strategicGoal} · ${direction.primaryJourney}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: PrototypeShell(direction: direction, fixtures: _fixtures),
            ),
          ],
        ),
      ),
    );
  }
}

Color _seedColor(String hex) {
  final value = int.parse(hex.substring(1), radix: 16);
  return Color(0xFF000000 | value);
}
