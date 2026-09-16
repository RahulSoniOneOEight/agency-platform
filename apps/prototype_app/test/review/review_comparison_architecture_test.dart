import 'dart:convert';
import 'dart:io';

import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/fixtures/fixture_repository.dart';
import 'package:prototype_app/registry/prototype_registry.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_comparison_host.dart';
import 'package:prototype_app/review/review_comparison_layout.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_direction_comparison.dart';
import 'package:prototype_app/review/review_direction_summary.dart';
import 'package:prototype_app/review/review_screen_availability.dart';
import 'package:prototype_app/review/review_screen_comparison.dart';
import 'package:prototype_app/review/review_state.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

/// The C.2 comparison sources under architecture scrutiny. Unlike the C.1
/// source scan these are the only files where the C.2 comparison guarantees
/// (no ranking vocabulary, no concrete pattern widgets) must hold.
const Set<String> _comparisonSourceNames = {
  'review_screen_availability.dart',
  'review_direction_comparison.dart',
  'review_screen_comparison.dart',
  'review_comparison_host.dart',
  'review_comparison_layout.dart',
  'review_direction_summary.dart',
};

/// Ranking / recommendation vocabulary C.2 must never render.
final RegExp _rankingVocabulary = RegExp(
  'best|recommend|winner|rank|score|rating|prefer|favorite|better|ideal',
  caseSensitive: false,
);

/// Source files of the review subsystem. Tests run on the VM from
/// `apps/prototype_app`, so the relative path resolves against the package root.
List<File> _reviewSourceFiles() {
  final directory = Directory('lib/review');
  expect(
    directory.existsSync(),
    isTrue,
    reason: 'Expected to run from apps/prototype_app (lib/review not found).',
  );
  final files = directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();
  expect(files, isNotEmpty, reason: 'Expected review Dart sources to scan.');
  return files;
}

/// Whether [file] lives under the file-backed `persistence/` adapter layer.
///
/// Per R1 only `persistence/` may perform file I/O; the review domain must stay
/// I/O-free.
bool _isPersistenceFile(File file) =>
    file.path.replaceAll('\\', '/').contains('/persistence/');

List<File> _domainReviewSourceFiles() =>
    _reviewSourceFiles().where((file) => !_isPersistenceFile(file)).toList();

List<File> _comparisonSourceFiles() {
  final files = _reviewSourceFiles()
      .where((file) => _comparisonSourceNames.contains(file.uri.pathSegments.last))
      .toList();
  expect(
    files.length,
    _comparisonSourceNames.length,
    reason: 'Every C.2 comparison source must exist to be scanned.',
  );
  return files;
}

/// Removes `//` line comments and `/* */` block comments while preserving
/// string literals. Ranking vocabulary legitimately appears in the doc
/// comments that *state* the neutrality rule ("never ranks, scores, or
/// recommends"), so the scan must inspect code/strings, not prose.
String _stripComments(String source) {
  final buffer = StringBuffer();
  var index = 0;
  var inLineComment = false;
  var inBlockComment = false;
  var inSingleQuote = false;
  var inDoubleQuote = false;

  while (index < source.length) {
    final char = source[index];
    final next = index + 1 < source.length ? source[index + 1] : '';

    if (inLineComment) {
      if (char == '\n') {
        inLineComment = false;
        buffer.write(char);
      }
      index++;
      continue;
    }
    if (inBlockComment) {
      if (char == '*' && next == '/') {
        inBlockComment = false;
        index += 2;
        continue;
      }
      if (char == '\n') buffer.write(char);
      index++;
      continue;
    }
    if (inSingleQuote || inDoubleQuote) {
      buffer.write(char);
      if (char == '\\' && next.isNotEmpty) {
        buffer.write(next);
        index += 2;
        continue;
      }
      if (inSingleQuote && char == "'") inSingleQuote = false;
      if (inDoubleQuote && char == '"') inDoubleQuote = false;
      index++;
      continue;
    }
    if (char == '/' && next == '/') {
      inLineComment = true;
      index += 2;
      continue;
    }
    if (char == '/' && next == '*') {
      inBlockComment = true;
      index += 2;
      continue;
    }
    if (char == "'") inSingleQuote = true;
    if (char == '"') inDoubleQuote = true;
    buffer.write(char);
    index++;
  }
  return buffer.toString();
}

/// Three-direction runtime with deliberately partial availability.
/// `a` = home/search, `b` = search/plp, `c` = pdp/plp.
PrototypeRuntime _comparisonRuntime({Map<String, Map<String, Object?>>? directionThemes}) {
  return PrototypeRuntime.fromMap(
    canonicalBundle(
      directionIds: const ['a', 'b', 'c'],
      patterns: const {
        'a': ['commerce.home', 'commerce.search'],
        'b': ['commerce.search', 'commerce.plp'],
        'c': ['commerce.pdp', 'commerce.plp'],
      },
      // Compact spacing keeps the shared ProductCard within its fixed grid
      // extent (a shared-component concern, not a C.2 one).
      theme: resolvedThemeMap(cardSpacing: 12, tileGap: 8),
      directionThemes: directionThemes,
    ),
  );
}

ReviewController _freshController(PrototypeRuntime runtime) => ReviewController(
      clientId: runtime.clientId,
      repository: MemoryReviewRepository(),
      runtime: runtime,
    );

Future<void> _pumpScreenComparison(
  WidgetTester tester,
  PrototypeRuntime runtime,
  ReviewController controller,
  Size size,
) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReviewScreenComparison(
          runtime: runtime,
          fixtures: FixtureRepository.fromRuntime(runtime),
          controller: controller,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDirectionComparison(
  WidgetTester tester,
  PrototypeRuntime runtime,
  ReviewController controller,
  Size size,
) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReviewDirectionComparison(runtime: runtime, controller: controller),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('source boundaries (B.1B/D/F + approval)', () {
    test('lib/review never references approval artifacts', () {
      for (final file in _reviewSourceFiles()) {
        final lower = file.readAsStringSync().toLowerCase();

        expect(lower.contains('approved-experience'), isFalse,
            reason: '${file.path} references approved-experience');
        expect(lower.contains('approved_experience'), isFalse,
            reason: '${file.path} references approved_experience');
      }
    });

    test('the review domain performs no file I/O', () {
      for (final file in _domainReviewSourceFiles()) {
        final source = file.readAsStringSync();
        expect(source.contains('dart:io'), isFalse,
            reason: '${file.path} performs file I/O');
        expect(source.contains('File('), isFalse,
            reason: '${file.path} opens files');
        expect(source.contains('writeAsString'), isFalse,
            reason: '${file.path} writes files');
        expect(source.contains('writeAsBytes'), isFalse,
            reason: '${file.path} writes files');
      }
    });

    test('the review domain never references B.1F refinement notes', () {
      final offenders = <String>[
        for (final file in _domainReviewSourceFiles())
          if (file.readAsStringSync().toLowerCase().contains('refinement'))
            file.path,
      ];
      expect(offenders, isEmpty,
          reason: 'refinement notes must stay non-runtime for Review Mode');
    });

    test('review subsystem sources render no ranking vocabulary', () {
      final offenders = <String>[];
      for (final file in _domainReviewSourceFiles()) {
        final code = _stripComments(file.readAsStringSync());
        if (_rankingVocabulary.hasMatch(code)) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'comparison must not score, rank, or recommend a direction');
    });
  });

  group('renderer reuse (no duplicated screen implementation)', () {
    test('comparison sources never reference concrete pattern widgets', () {
      final concretePatterns = RegExp(
        'HomePattern|SearchPattern|PlpPattern|PdpPattern|CartPattern|'
        'RfqPattern|TradeDashboardPattern|BookingPattern',
      );
      for (final file in _comparisonSourceFiles()) {
        final code = _stripComments(file.readAsStringSync());
        expect(concretePatterns.hasMatch(code), isFalse,
            reason: '${file.path} duplicates screen rendering instead of '
                'delegating to PrototypeRegistry/ReviewComparisonHost');
      }
    });

    test('screen comparison delegates rendering to ReviewComparisonHost', () {
      final screenComparison = File('lib/review/review_screen_comparison.dart');
      final code = _stripComments(screenComparison.readAsStringSync());
      expect(code.contains('ReviewComparisonHost'), isTrue,
          reason: 'screen comparison must reuse the existing client renderer');
    });

    testWidgets('supported pairs render through ReviewComparisonHost',
        (tester) async {
      final runtime = _comparisonRuntime();
      final controller = _freshController(runtime);

      await _pumpScreenComparison(
        tester,
        runtime,
        controller,
        const Size(1200, 800),
      );
      await tester.tap(
        find.byKey(ReviewScreenComparison.screenChipKey('commerce.search')),
      );
      await tester.pumpAndSettle();

      // search is supported by a and b only; each supported pair is rendered by
      // the one shared host, never a duplicated screen widget.
      expect(find.byType(ReviewComparisonHost), findsNWidgets(2));
      expect(
        find.byKey(ReviewScreenComparison.unavailableKey('c')),
        findsOneWidget,
      );
    });
  });

  group('B.1B runtime immutability under comparison interactions', () {
    testWidgets('viewing, previewing, and selecting never mutate runtime data',
        (tester) async {
      final bundle = canonicalBundle(
        directionIds: const ['a', 'b', 'c'],
        patterns: const {
          'a': ['commerce.home', 'commerce.search'],
          'b': ['commerce.search', 'commerce.plp'],
          'c': ['commerce.pdp', 'commerce.plp'],
        },
        theme: resolvedThemeMap(cardSpacing: 12, tileGap: 8),
        directionThemes: {
          'a': resolvedThemeMap(primary: '#1155CC', cardSpacing: 12, tileGap: 8),
          'b': resolvedThemeMap(primary: '#CC1155', cardSpacing: 12, tileGap: 8),
          'c': resolvedThemeMap(primary: '#11CC55', cardSpacing: 12, tileGap: 8),
        },
      );
      final runtime = PrototypeRuntime.fromMap(bundle);

      final directionsBefore = Map.of(runtime.directions);
      final themesBefore = Map.of(runtime.directionThemes);
      final resourcesBefore = Map.of(runtime.resources);
      final overridesBefore = runtime.directionOverrides;
      final baseThemeBefore = runtime.theme;
      final allowedBefore = List<String>.of(runtime.allowedDirections);
      final bundleJsonBefore = json.encode(bundle);

      final controller = _freshController(runtime);

      // Screen comparison: select a screen and switch the preview direction.
      await _pumpScreenComparison(
        tester,
        runtime,
        controller,
        const Size(400, 800),
      );
      await tester.tap(
        find.byKey(ReviewScreenComparison.screenChipKey('commerce.search')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(ReviewComparisonLayout.switcherKey),
          matching: find.text('B'),
        ),
      );
      await tester.pumpAndSettle();

      // Directions comparison: take the explicit selection (wide shows all
      // panels side by side, so there is no switcher here).
      await _pumpDirectionComparison(
        tester,
        runtime,
        controller,
        const Size(1200, 800),
      );
      final select = find.byKey(ReviewDirectionSummary.selectButtonKey('b'));
      await tester.ensureVisible(select);
      await tester.pumpAndSettle();
      await tester.tap(select);
      await tester.pumpAndSettle();

      expect(controller.state.selectedDirection, 'b');

      expect(runtime.directions.keys.toSet(), equals(directionsBefore.keys.toSet()));
      for (final id in directionsBefore.keys) {
        expect(identical(runtime.directions[id], directionsBefore[id]), isTrue,
            reason: 'direction $id instance was replaced');
      }
      expect(runtime.directionThemes.keys.toSet(), equals(themesBefore.keys.toSet()));
      for (final id in themesBefore.keys) {
        expect(identical(runtime.directionThemes[id], themesBefore[id]), isTrue,
            reason: 'direction theme $id instance was replaced');
      }
      expect(runtime.resources.keys.toSet(), equals(resourcesBefore.keys.toSet()));
      for (final id in resourcesBefore.keys) {
        expect(identical(runtime.resources[id], resourcesBefore[id]), isTrue,
            reason: 'resource $id instance was replaced');
      }
      expect(identical(runtime.theme, baseThemeBefore), isTrue);
      expect(identical(runtime.directionOverrides, overridesBefore), isTrue);
      expect(runtime.allowedDirections, equals(allowedBefore));
      expect(json.encode(bundle), equals(bundleJsonBefore));
    });
  });

  group('B.1D canonical IDs remain authoritative', () {
    test('labelFor delegates to PrototypeRegistry for every governed screen', () {
      final runtime = _comparisonRuntime();

      for (final screenId in ReviewScreenAvailability.screens(runtime)) {
        expect(
          ReviewScreenAvailability.labelFor(screenId),
          equals(PrototypeRegistry.labelFor(screenId)),
        );
      }
    });

    test('every governed screen is a canonical pattern declared by a direction', () {
      final runtime = _comparisonRuntime();

      for (final screenId in ReviewScreenAvailability.screens(runtime)) {
        final declared = runtime.directions.values
            .any((direction) => direction.patterns.contains(screenId));
        expect(declared, isTrue,
            reason: '$screenId is not declared by any runtime direction');
        // Canonical binding must resolve (throws ArgumentError otherwise).
        expect(() => PrototypeRegistry.labelFor(screenId), returnsNormally);
      }
    });

    test('availability adapter delegates and hard-codes no canonical screen ids', () {
      final source =
          File('lib/review/review_screen_availability.dart').readAsStringSync();
      final code = _stripComments(source);

      expect(code.contains('ReviewScreenRegistry'), isTrue,
          reason: 'availability must delegate to the governed registry');
      expect(RegExp(r'commerce\.').hasMatch(code), isFalse,
          reason: 'adapter must not hard-code canonical screen ids or hold a '
              'second alias table');
    });
  });

  group('B.1E direction-resolved theme per panel', () {
    testWidgets('each supported panel uses its direction-resolved theme',
        (tester) async {
      final runtime = _comparisonRuntime(
        directionThemes: {
          'a': resolvedThemeMap(primary: '#1155CC', cardSpacing: 12, tileGap: 8),
          'b': resolvedThemeMap(primary: '#CC1155', cardSpacing: 12, tileGap: 8),
        },
      );
      final controller = _freshController(runtime);

      await _pumpScreenComparison(
        tester,
        runtime,
        controller,
        const Size(1200, 800),
      );
      await tester.tap(
        find.byKey(ReviewScreenComparison.screenChipKey('commerce.search')),
      );
      await tester.pumpAndSettle();

      final primaryA =
          AgencyTheme.light(runtime.themeForDirection('a')).colorScheme.primary;
      final primaryB =
          AgencyTheme.light(runtime.themeForDirection('b')).colorScheme.primary;
      expect(primaryA, isNot(equals(primaryB)));

      for (final entry in {'a': primaryA, 'b': primaryB}.entries) {
        final host = find.descendant(
          of: find.byKey(ReviewComparisonLayout.panelKey(entry.key)),
          matching: find.byType(ReviewComparisonHost),
        );
        final rendered = tester.widget<Theme>(
          find.descendant(of: host, matching: find.byType(Theme)).first,
        );
        expect(rendered.data.colorScheme.primary, entry.value,
            reason: 'direction ${entry.key} did not use its resolved theme');
        expect(
          rendered.data.scaffoldBackgroundColor,
          AgencyTheme.light(runtime.themeForDirection(entry.key))
              .scaffoldBackgroundColor,
        );
      }
    });
  });

  group('C.1 ReviewState contract compatibility', () {
    const canonicalKeys = <String>{
      'version',
      'client_id',
      'review_round',
      'status',
      'selected_direction',
      'screen_selections',
      'comments',
      'feedback_ids',
    };

    test('toJson emits exactly the canonical eight keys and round-trips', () {
      final state = ReviewState.fromJson({
        'version': 1,
        'client_id': 'prototype-demo',
        'review_round': 2,
        'status': 'in_review',
        'selected_direction': 'b',
        'screen_selections': {'commerce.search': 'b'},
        'comments': [
          {'id': 'c1', 'scope': 'general', 'text': 'hello'},
        ],
      });

      expect(state.toJson().keys.toSet(), equals(canonicalKeys));
      expect(ReviewState.fromJson(state.toJson()), equals(state));
    });

    test('canonical v2 decisions keep the eight-key contract and round-trip', () {
      final state = ReviewState.fromJson({
        'version': 2,
        'client_id': 'prototype-demo',
        'review_round': 2,
        'status': 'in_review',
        'selected_direction': 'a',
        'screen_selections': {
          'commerce.plp': {
            'direction': 'c',
            'sections': {'plp.product-grid': 'a'},
          },
        },
        'comments': [
          {'id': 'c1', 'scope': 'general', 'text': 'hello'},
        ],
      });

      final json = state.toJson();
      expect(json.keys.toSet(), equals(canonicalKeys));
      expect(
        (json['screen_selections'] as Map<String, dynamic>)['commerce.plp'],
        {
          'direction': 'c',
          'sections': {'plp.product-grid': 'a'},
        },
      );
      expect(ReviewState.fromJson(json), equals(state));
    });

    testWidgets('comparison viewing interactions never mutate controller state',
        (tester) async {
      final runtime = _comparisonRuntime();
      final controller = _freshController(runtime);
      final before = controller.state;

      await _pumpScreenComparison(
        tester,
        runtime,
        controller,
        const Size(400, 800),
      );
      await tester.tap(
        find.byKey(ReviewScreenComparison.screenChipKey('commerce.search')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(ReviewComparisonLayout.switcherKey),
          matching: find.text('B'),
        ),
      );
      await tester.pumpAndSettle();

      await _pumpDirectionComparison(
        tester,
        runtime,
        controller,
        const Size(400, 800),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(ReviewComparisonLayout.switcherKey),
          matching: find.text('B'),
        ),
      );
      await tester.pumpAndSettle();

      expect(identical(controller.state, before), isTrue,
          reason: 'viewing/previewing must not replace controller state');
      expect(controller.state.selectedDirection, isNull);
      expect(controller.state.screenSelections, isEmpty);
      expect(controller.state.comments, isEmpty);
    });
  });

  group('C.3 section mix decisions stay display-only in comparison', () {
    testWidgets('a persisted section mix never changes comparison panels',
        (tester) async {
      final runtime = PrototypeRuntime.fromMap(
        canonicalBundle(
          directionIds: const ['a', 'b', 'c'],
          patterns: const {
            'a': ['commerce.plp', 'commerce.search'],
            'b': ['commerce.search', 'commerce.plp'],
            'c': ['commerce.pdp', 'commerce.plp'],
          },
          components: const {
            'a': ['commerce.product-card'],
            'b': ['commerce.product-card'],
            'c': ['commerce.product-card'],
          },
          theme: resolvedThemeMap(cardSpacing: 12, tileGap: 8),
          directionThemes: {
            'a': resolvedThemeMap(primary: '#1155CC', cardSpacing: 12, tileGap: 8),
            'b': resolvedThemeMap(primary: '#CC1155', cardSpacing: 12, tileGap: 8),
            'c': resolvedThemeMap(primary: '#11CC55', cardSpacing: 12, tileGap: 8),
          },
        ),
      );
      final controller = _freshController(runtime);
      await controller.selectDirection('a');
      await controller.setSectionDirection(
        'commerce.plp',
        'plp.product-grid',
        'c',
      );
      expect(
        controller.state.screenSelections['commerce.plp']!
            .sections['plp.product-grid'],
        'c',
      );

      await _pumpScreenComparison(
        tester,
        runtime,
        controller,
        const Size(1600, 900),
      );
      await tester.tap(
        find.byKey(ReviewScreenComparison.screenChipKey('commerce.plp')),
      );
      await tester.pumpAndSettle();

      // commerce.plp is supported by a, b and c. Every comparison panel keeps
      // its own direction-resolved theme; the persisted C.3 section mix is not
      // consulted by the display-only comparison surfaces.
      for (final id in const ['a', 'b', 'c']) {
        final expected = AgencyTheme.light(runtime.themeForDirection(id));
        final host = find.descendant(
          of: find.byKey(ReviewComparisonLayout.panelKey(id)),
          matching: find.byType(ReviewComparisonHost),
        );
        final rendered = tester.widget<Theme>(
          find.descendant(of: host, matching: find.byType(Theme)).first,
        );
        expect(
          rendered.data.colorScheme.primary,
          expected.colorScheme.primary,
          reason: 'direction $id panel was contaminated by the section mix',
        );
      }
    });
  });

  group('neutrality', () {
    testWidgets('directions comparison renders no ranking vocabulary',
        (tester) async {
      final runtime = _comparisonRuntime();
      final controller = _freshController(runtime);

      await _pumpDirectionComparison(
        tester,
        runtime,
        controller,
        const Size(1200, 800),
      );
      expect(find.textContaining(_rankingVocabulary), findsNothing);

      await _pumpDirectionComparison(
        tester,
        runtime,
        controller,
        const Size(400, 800),
      );
      expect(find.textContaining(_rankingVocabulary), findsNothing);
    });

    testWidgets('screen comparison renders no ranking vocabulary',
        (tester) async {
      final runtime = _comparisonRuntime();
      final controller = _freshController(runtime);

      await _pumpScreenComparison(
        tester,
        runtime,
        controller,
        const Size(1200, 800),
      );
      expect(find.textContaining(_rankingVocabulary), findsNothing);

      await _pumpScreenComparison(
        tester,
        runtime,
        controller,
        const Size(400, 800),
      );
      expect(find.textContaining(_rankingVocabulary), findsNothing);
    });
  });
}
