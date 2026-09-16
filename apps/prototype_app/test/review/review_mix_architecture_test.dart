import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/fixtures/fixture_repository.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_mixed_preview.dart';
import 'package:prototype_app/review/review_section_registry.dart';
import 'package:prototype_app/review/review_state.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

/// The tracked reference-client bundle. Tests run on the VM from
/// `apps/prototype_app`, so the relative path resolves against the package root.
const String _referenceBundlePath = 'assets/generated/prototype-demo.json';

PrototypeRuntime _loadReferenceRuntime() {
  final file = File(_referenceBundlePath);
  return PrototypeRuntime.fromMap(
    Map<String, dynamic>.from(
      json.decode(file.readAsStringSync()) as Map,
    ),
  );
}

/// Source files of the review subsystem (see review_architecture_test.dart).
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

Set<String> _generatedFileNames() {
  final directory = Directory('assets/generated');
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => file.uri.pathSegments.last)
      .toSet();
}

void main() {
  group('B.1B runtime bundle stays read-only under C.3 mix operations', () {
    testWidgets(
        'mix decisions leave runtime identity and generated bundle bytes unchanged',
        (tester) async {
      final bytesBefore = File(_referenceBundlePath).readAsBytesSync();
      final generatedBefore = _generatedFileNames();

      final runtime = _loadReferenceRuntime();
      final fixtures = FixtureRepository.fromRuntime(runtime);

      final directionsBefore = Map.of(runtime.directions);
      final themesBefore = Map.of(runtime.directionThemes);
      final resourcesBefore = Map.of(runtime.resources);
      final baseThemeBefore = runtime.theme;
      final overridesBefore = runtime.directionOverrides;
      final allowedBefore = List<String>.of(runtime.allowedDirections);
      final patternsBefore = {
        for (final entry in runtime.directions.entries)
          entry.key: List<String>.of(entry.value.patterns),
      };

      final controller = ReviewController(
        clientId: runtime.clientId,
        repository: MemoryReviewRepository(),
        runtime: runtime,
      );

      await controller.selectDirection('a');
      await controller.setSectionDirection('commerce.pdp', 'pdp.price', 'c');
      await controller.setScreenDirection('commerce.plp', 'c');
      await controller.resetScreenMix('commerce.plp');

      expect(controller.state.selectedDirection, 'a');
      expect(
        controller.state.screenSelections['commerce.pdp']!.sections['pdp.price'],
        'c',
      );

      // The mixed preview is derived rendering; it must not touch the runtime.
      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReviewMixedPreview(
              runtime: runtime,
              fixtures: fixtures,
              screenId: 'commerce.pdp',
              state: controller.state,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(runtime.directions.keys.toSet(), equals(directionsBefore.keys.toSet()));
      for (final id in directionsBefore.keys) {
        expect(identical(runtime.directions[id], directionsBefore[id]), isTrue,
            reason: 'direction $id instance was replaced');
        expect(runtime.directions[id]!.patterns, equals(patternsBefore[id]));
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

      expect(File(_referenceBundlePath).readAsBytesSync(), equals(bytesBefore),
          reason: 'mix decisions must not rewrite the generated runtime bundle');
      expect(_generatedFileNames(), equals(generatedBefore),
          reason: 'no synthetic runtime artifact may be written');
    });
  });

  group('no synthetic runtime artifact', () {
    test('lib/review performs no file I/O', () {
      for (final file in _reviewSourceFiles()) {
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
  });

  group('renderer reuse (no duplicated full-screen implementation)', () {
    test('no lib/review source references concrete pattern widgets', () {
      final concretePatterns = RegExp(
        'HomePattern|SearchPattern|PlpPattern|PdpPattern|CartPattern|'
        'RfqPattern|TradeDashboardPattern|BookingPattern',
      );
      final offenders = <String>[];
      for (final file in _reviewSourceFiles()) {
        if (concretePatterns.hasMatch(file.readAsStringSync())) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'Review Mode must reuse PrototypeRegistry/shared sections '
              'instead of duplicating full-screen implementations');
    });

    test('the mixed preview composes shared sections via PrototypeRegistry', () {
      final source =
          File('lib/review/review_mixed_preview.dart').readAsStringSync();

      expect(source.contains('PrototypeRegistry'), isTrue);
      expect(source.contains('compositionFor'), isTrue);
      expect(source.contains('buildPatternComposition'), isTrue);
      expect(source.contains('PatternComposition'), isTrue);
    });
  });

  group('governed section identity is the only mix authority', () {
    test('ReviewSectionRegistry is the sole section-id authority in lib/review', () {
      const authority = 'review_section_registry.dart';
      final sectionIds =
          ReviewSectionRegistry.all.map((definition) => definition.id).toList();
      expect(sectionIds, isNotEmpty);

      final offenders = <String>[];
      for (final file in _reviewSourceFiles()) {
        if (file.uri.pathSegments.last == authority) {
          continue;
        }
        final source = file.readAsStringSync();
        if (source.contains('ReviewSectionDefinition(')) {
          offenders.add('${file.path} (defines section definitions)');
        }
        for (final id in sectionIds) {
          if (source.contains(id)) {
            offenders.add('${file.path} (contains section id "$id")');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'section ids must be defined once, by the governed registry');
    });

    test('no arbitrary component-level mix API exists in lib/review', () {
      final componentApi = RegExp(
        'setComponent|clearComponent|componentDirection|ComponentOverride|'
        'ReviewComponentRegistry|componentMix',
      );
      final offenders = <String>[
        for (final file in _reviewSourceFiles())
          if (componentApi.hasMatch(file.readAsStringSync())) file.path,
      ];
      expect(offenders, isEmpty,
          reason: 'C.3 allows section mixes only, never component-level mixing');
    });
  });

  group('B.1F refinement notes remain non-runtime', () {
    test('lib/review never references refinement notes', () {
      final offenders = <String>[
        for (final file in _reviewSourceFiles())
          if (file.readAsStringSync().toLowerCase().contains('refinement'))
            file.path,
      ];
      expect(offenders, isEmpty,
          reason: 'refinement notes must stay non-runtime metadata for Review Mode');
    });
  });

  group('no approval artifact and no terminal approval status', () {
    test('lib/review generates no approved-experience artifact', () {
      for (final file in _reviewSourceFiles()) {
        final lower = file.readAsStringSync().toLowerCase();
        expect(lower.contains('approved-experience'), isFalse,
            reason: '${file.path} references approved-experience');
        expect(lower.contains('approved_experience'), isFalse,
            reason: '${file.path} references approved_experience');
      }
    });

    test('ReviewStatus exposes no approval/terminal status value', () {
      expect(
        ReviewStatus.values.map((value) => value.name).toSet(),
        equals(<String>{'inReview', 'needsRevision', 'readyForFinalReview'}),
      );
      for (final status in ReviewStatus.values) {
        expect(status.name.toLowerCase().contains('approv'), isFalse);
        expect(reviewStatusToWire(status).toLowerCase().contains('approv'), isFalse);
      }
    });
  });

  group('C.1/C.2 migration compatibility under C.3', () {
    test('a version-1 state loads, migrates to v2, and persists v2', () async {
      final runtime = _loadReferenceRuntime();

      final migrated = ReviewState.fromJson({
        'version': 1,
        'client_id': runtime.clientId,
        'review_round': 3,
        'status': 'needs_revision',
        'selected_direction': 'a',
        'screen_selections': {'commerce.plp': 'c'},
        'comments': [
          {'id': 'c1', 'scope': 'general', 'text': 'keep me'},
        ],
      });
      expect(migrated.version, ReviewState.currentVersion);
      expect(migrated.screenSelections['commerce.plp']!.direction, 'c');
      expect(migrated.screenSelections['commerce.plp']!.sections, isEmpty);

      final repository = MemoryReviewRepository();
      await repository.save(migrated);

      final controller = ReviewController(
        clientId: runtime.clientId,
        repository: repository,
        runtime: runtime,
      );
      await controller.load();

      expect(controller.loadErrors, isEmpty);
      expect(controller.state.version, 2);
      expect(controller.state.reviewRound, 3);
      expect(controller.state.status, ReviewStatus.needsRevision);
      expect(controller.state.selectedDirection, 'a');
      expect(controller.state.comments.map((comment) => comment.id), ['c1']);
      expect(
        controller.state.screenSelections['commerce.plp']!.direction,
        'c',
      );

      // The next mutation persists the canonical v2 representation only.
      await controller.setSectionDirection(
        'commerce.plp',
        'plp.product-grid',
        'a',
      );

      final saved = await repository.load(runtime.clientId);
      expect(saved, isNotNull);
      expect(saved!.version, 2);
      final json = saved.toJson();
      expect(json['version'], 2);
      final selections = json['screen_selections'] as Map<String, dynamic>;
      expect(selections['commerce.plp'], {
        'direction': 'c',
        'sections': {'plp.product-grid': 'a'},
      });
      expect(json['comments'], hasLength(1));
    });

    test('a canonical v2 mix round-trips deterministically', () {
      final runtime = _loadReferenceRuntime();
      final state = ReviewState.fromJson({
        'version': 2,
        'client_id': runtime.clientId,
        'review_round': 1,
        'status': 'in_review',
        'selected_direction': 'a',
        'screen_selections': {
          'commerce.pdp': {
            'sections': {'pdp.price': 'c'},
          },
        },
        'comments': <dynamic>[],
      });

      expect(state.screenSelections['commerce.pdp']!.direction, isNull);
      expect(state.screenSelections['commerce.pdp']!.sections, {'pdp.price': 'c'});
      expect(ReviewState.fromJson(state.toJson()), equals(state));
    });
  });
}
