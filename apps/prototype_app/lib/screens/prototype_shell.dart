import 'package:flutter/material.dart';

import '../direction/prototype_direction.dart';
import '../fixtures/fixture_repository.dart';
import '../registry/prototype_registry.dart';

class PrototypeShell extends StatefulWidget {
  const PrototypeShell({
    super.key,
    required this.direction,
    required this.fixtures,
  });

  final PrototypeDirection direction;
  final FixtureRepository fixtures;

  @override
  State<PrototypeShell> createState() => _PrototypeShellState();
}

class _PrototypeShellState extends State<PrototypeShell> {
  var _index = 0;

  @override
  void didUpdateWidget(covariant PrototypeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.direction.id != widget.direction.id) {
      _index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final patterns = widget.direction.patterns;
    final safeIndex = _index.clamp(0, patterns.length - 1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final body = PrototypeRegistry.buildPattern(
          patterns[safeIndex],
          widget.direction,
          widget.fixtures,
        );
        if (patterns.length < 2) {
          return Scaffold(body: body);
        }
        if (wide) {
          return Row(
            children: [
              NavigationRail(
                selectedIndex: safeIndex,
                onDestinationSelected: (value) => setState(() => _index = value),
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final id in patterns)
                    NavigationRailDestination(
                      icon: const Icon(Icons.layers_outlined),
                      selectedIcon: const Icon(Icons.layers),
                      label: Text(id),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          );
        }
        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: safeIndex,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: [
              for (final id in patterns)
                NavigationDestination(icon: const Icon(Icons.layers_outlined), label: id),
            ],
          ),
        );
      },
    );
  }
}
