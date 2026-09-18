import 'dart:convert';
import 'dart:io';

import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/fixtures/fixture_repository.dart';
import 'package:prototype_app/registry/prototype_registry.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

/// Path of the committed generated bundle, resolved from the package root.
///
/// Tests run on the VM from `apps/prototype_app`, exactly like the existing
/// review reference-client test.
const String referenceBundlePath =
    'assets/generated/reference-commerce.json';

const String referenceClientId = 'reference-commerce';

/// Screens that are safe to render with the real reference theme.
///
/// `commerce.home` and `commerce.plp` are intentionally excluded: they have a
/// pre-existing `ProductCard`/`mainAxisExtent` overflow shared by the whole
/// prototype runtime.
const List<String> safeReferenceScreens = <String>[
  'commerce.search',
  'commerce.pdp',
  'commerce.cart',
  'commerce.rfq',
  'commerce.trade-dashboard',
];

/// Loads the committed reference-client bundle exactly as the app does.
PrototypeRuntime loadReferenceRuntime() {
  final decoded =
      json.decode(File(referenceBundlePath).readAsStringSync()) as Map;
  return PrototypeRuntime.fromMap(Map<String, dynamic>.from(decoded));
}

FixtureRepository referenceFixtures(PrototypeRuntime runtime) =>
    FixtureRepository.fromRuntime(runtime);

/// Pumps one governed pattern through the shared registry under the
/// direction-resolved theme.
Future<void> pumpReferencePattern(
  WidgetTester tester,
  PrototypeRuntime runtime,
  String directionId,
  String screenId, {
  Size size = const Size(420, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AgencyTheme.light(runtime.themeForDirection(directionId)),
      home: Scaffold(
        body: PrototypeRegistry.buildPattern(
          screenId,
          runtime.directions[directionId]!,
          referenceFixtures(runtime),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A deterministic, comparable snapshot of the runtime's declared state.
Map<String, Object?> runtimeSnapshot(PrototypeRuntime runtime) => {
      'clientId': runtime.clientId,
      'defaultDirection': runtime.defaultDirection,
      'allowedDirections': List<String>.from(runtime.allowedDirections),
      'directions': {
        for (final entry in runtime.directions.entries)
          entry.key: {
            'name': entry.value.name,
            'density': entry.value.density.name,
            'patterns': List<String>.from(entry.value.patterns),
          },
      },
      'directionThemeKeys': runtime.directionThemes.keys.toList()..sort(),
      'themeColorKeys': runtime.theme.colors.keys.toList()..sort(),
    };
