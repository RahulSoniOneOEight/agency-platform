import 'dart:convert';
import 'dart:io';

import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/fixtures/fixture_repository.dart';
import 'package:prototype_app/prototype_app.dart';
import 'package:prototype_app/qa/memory_qa_finding_repository.dart';
import 'package:prototype_app/qa/qa_coordinator.dart';
import 'package:prototype_app/qa/qa_finding.dart';
import 'package:prototype_app/registry/prototype_registry.dart';
import 'package:prototype_app/review/memory_approval_repository.dart';
import 'package:prototype_app/review/memory_feedback_repository.dart';
import 'package:prototype_app/review/memory_refinement_batch_repository.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/review_actor.dart';
import 'package:prototype_app/review/review_comparison_host.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_coordinator.dart';
import 'package:prototype_app/review/review_screen_registry.dart';
import 'package:prototype_app/review/review_shell.dart';
import 'package:prototype_app/review/review_state.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';
import 'package:prototype_app/screens/prototype_shell.dart';

import '../support/runtime_fixtures.dart';

const ReviewActor _reviewer = ReviewActor(
  id: 'reviewer-1',
  name: 'Reviewer',
  role: ReviewRole.reviewer,
);

/// Keys that belong to the review-state contract. They must never appear inside
/// the B.1B runtime bundle input (review state is separate from the runtime).
///
/// `direction`/`sections` are the nested ReviewState v2 decision keys introduced
/// by C.3 (`screen_selections.<screen>.{direction,sections}`); they must not leak
/// into runtime data either.
const Set<String> _reviewStateKeys = {
  'review_round',
  'selected_direction',
  'screen_selections',
  'comments',
  'feedback_ids',
  'direction',
  'sections',
};

/// Recursively collects every map key reachable from [node].
Set<String> _allKeys(Object? node) {
  final keys = <String>{};
  if (node is Map) {
    for (final entry in node.entries) {
      keys.add(entry.key.toString());
      keys.addAll(_allKeys(entry.value));
    }
  } else if (node is List) {
    for (final item in node) {
      keys.addAll(_allKeys(item));
    }
  }
  return keys;
}

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
  expect(
    files,
    isNotEmpty,
    reason: 'Expected the review subsystem to have Dart sources to scan.',
  );
  return files;
}

/// Whether [file] lives under the file-backed `persistence/` adapter layer.
///
/// Per R1, only `persistence/` may perform file I/O; every other review source
/// file must stay I/O-free.
bool _isPersistenceFile(File file) =>
    file.path.replaceAll('\\', '/').contains('/persistence/');

/// Review source files that must remain free of any file I/O.
List<File> _domainReviewSourceFiles() =>
    _reviewSourceFiles().where((file) => !_isPersistenceFile(file)).toList();

PrototypeRuntime _threeDirectionRuntime() {
  return PrototypeRuntime.fromMap(
    canonicalBundle(
      directionIds: const ['a', 'b', 'c'],
      patterns: const {
        'a': ['commerce.home', 'commerce.search'],
        'b': ['commerce.search', 'commerce.plp'],
        'c': ['commerce.pdp', 'commerce.plp'],
      },
    ),
  );
}

void main() {
  // 1. Normal PrototypeApp still renders without Review Mode.
  group('normal prototype mode', () {
    testWidgets('PrototypeApp renders the prototype UI and never mounts ReviewShell',
        (tester) async {
      final runtime = PrototypeRuntime.fromMap(canonicalBundle());

      await tester.pumpWidget(
        PrototypeApp(runtime: runtime, requestedDirection: 'a'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PrototypeApp), findsOneWidget);
      expect(find.byType(PrototypeShell), findsOneWidget);
      expect(find.byType(ReviewShell), findsNothing);
      expect(find.text('Review Mode · prototype-demo'), findsNothing);
      expect(find.textContaining('Overall direction'), findsNothing);
      expect(find.text('A'), findsOneWidget);
    });
  });

  // 2. Review State keys are NOT present in runtime bundle JSON.
  group('runtime bundle boundary', () {
    test('canonical bundle input carries no review-state keys at any level', () {
      final bundle = canonicalBundle(
        directionIds: const ['a', 'b', 'c'],
        patterns: const {
          'a': ['commerce.home', 'commerce.search'],
          'b': ['commerce.search', 'commerce.plp'],
          'c': ['commerce.pdp', 'commerce.plp'],
        },
      );
      final decoded = json.decode(json.encode(bundle)) as Map<String, dynamic>;

      // Sanity: the bundle is a real runtime bundle (so the absence assertions
      // below are meaningful rather than vacuous).
      expect(decoded['directions'], isA<Map>());
      expect(decoded['review'], isA<Map>());
      expect(decoded.keys.toSet().intersection(_reviewStateKeys), isEmpty);
      expect(_allKeys(decoded).intersection(_reviewStateKeys), isEmpty);
      for (final key in _reviewStateKeys) {
        expect(
          bundle.containsKey(key),
          isFalse,
          reason: 'review-state key "$key" leaked into the runtime bundle',
        );
      }
    });

    test('a parsed PrototypeRuntime is not a container for review state', () {
      final runtime = _threeDirectionRuntime();

      expect(runtime.directions.containsKey('review_round'), isFalse);
      expect(runtime.fixtures.containsKey('selected_direction'), isFalse);
      expect(runtime.resources.containsKey('screen_selections'), isFalse);
    });
  });

  // 3. Review actions do not mutate PrototypeRuntime data.
  group('runtime immutability under review actions', () {
    testWidgets(
        'controller mutations and comparison-host renders leave runtime data unchanged',
        (tester) async {
      final bundle = canonicalBundle(
        directionIds: const ['a', 'b', 'c'],
        directionThemes: {
          'a': resolvedThemeMap(primary: '#1155CC'),
          'b': resolvedThemeMap(primary: '#CC1155'),
          'c': resolvedThemeMap(primary: '#11CC55'),
        },
      );
      final runtime = PrototypeRuntime.fromMap(bundle);
      final fixtures = FixtureRepository.fromRuntime(runtime);

      final directionsBefore = Map.of(runtime.directions);
      final themesBefore = Map.of(runtime.directionThemes);
      final resourcesBefore = Map.of(runtime.resources);
      final overridesBefore = runtime.directionOverrides;
      final baseThemeBefore = runtime.theme;
      final allowedBefore = List<String>.of(runtime.allowedDirections);
      final patternsBefore = {
        for (final entry in runtime.directions.entries)
          entry.key: List<String>.of(entry.value.patterns),
      };
      final bundleJsonBefore = json.encode(bundle);

      final controller = ReviewController(
        clientId: runtime.clientId,
        repository: MemoryReviewRepository(),
        runtime: runtime,
      );
      await controller.selectDirection('b');
      await controller.setScreenDirection('commerce.search', 'a');
      await controller.addComment(
        const ReviewComment(
          id: 'review-1',
          scope: ReviewCommentScope.general,
          text: 'Prefer the quieter visual hierarchy.',
        ),
      );
      await controller.updateComment(
        const ReviewComment(
          id: 'review-1',
          scope: ReviewCommentScope.screen,
          text: 'Reduce hero height.',
          screen: 'commerce.search',
        ),
      );
      await controller.setStatus(ReviewStatus.needsRevision);
      await controller.advanceRound();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReviewComparisonHost(
              runtime: runtime,
              fixtures: fixtures,
              directionId: 'c',
              screenId: 'commerce.search',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.state.selectedDirection, 'b');
      expect(controller.state.screenSelections['commerce.search']!.direction, 'a');
      expect(controller.state.reviewRound, 2);

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
      expect(json.encode(bundle), equals(bundleJsonBefore));
    });
  });

  // 4. B.1F refinement notes remain non-runtime for the review domain.
  group('B.1F refinement notes', () {
    test('the review domain never references B.1F refinement-note metadata', () {
      // C.7 legitimately introduces RefinementBatch, so this guard pins the
      // B.1F *refinement-notes* artifact rather than the bare word.
      const needles = <String>[
        'refinement-notes',
        'refinement_notes',
        'refinement note',
      ];
      final offenders = <String>[];
      for (final file in _domainReviewSourceFiles()) {
        final source = file.readAsStringSync().toLowerCase();
        if (needles.any(source.contains)) {
          offenders.add(file.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'refinement-notes must stay non-runtime metadata for Review Mode',
      );
    });
  });

  // 5. No approved-experience generation exists in the review subsystem, and
  //    only `persistence/` performs file I/O (R1).
  group('approval artifact exclusion', () {
    test('no review file references or writes approved-experience artifacts', () {
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
        expect(source.contains('writeAsString'), isFalse,
            reason: '${file.path} writes files');
        expect(source.contains('writeAsBytes'), isFalse,
            reason: '${file.path} writes files');
        expect(source.contains('File('), isFalse,
            reason: '${file.path} opens files');
      }
    });

    test('persistence adapters never write runtime bundles', () {
      final persistenceFiles =
          _reviewSourceFiles().where(_isPersistenceFile).toList();
      expect(
        persistenceFiles,
        isNotEmpty,
        reason: 'Expected the file-backed persistence layer to exist.',
      );
      for (final file in persistenceFiles) {
        final lower = file.readAsStringSync().toLowerCase();
        expect(lower.contains('assets/generated'), isFalse,
            reason: '${file.path} writes a runtime bundle');
        expect(lower.contains('runtime_bundle'), isFalse,
            reason: '${file.path} writes a runtime bundle');
      }
    });
  });

  // 6. Reviewed client screen uses runtime.themeForDirection(directionId).
  group('reviewed client theme (B.1E)', () {
    testWidgets('client Theme matches AgencyTheme.light(runtime.themeForDirection(id))',
        (tester) async {
      final runtime = PrototypeRuntime.fromMap(
        canonicalBundle(
          directionIds: const ['a', 'b'],
          directionThemes: {
            'a': resolvedThemeMap(primary: '#1155CC'),
            'b': resolvedThemeMap(primary: '#CC1155'),
          },
        ),
      );
      final fixtures = FixtureRepository.fromRuntime(runtime);

      final primaryA =
          AgencyTheme.light(runtime.themeForDirection('a')).colorScheme.primary;
      final primaryB =
          AgencyTheme.light(runtime.themeForDirection('b')).colorScheme.primary;
      expect(primaryA, isNot(equals(primaryB)));

      for (final id in const ['a', 'b']) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReviewComparisonHost(
                runtime: runtime,
                fixtures: fixtures,
                directionId: id,
                screenId: 'commerce.search',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final expected = AgencyTheme.light(runtime.themeForDirection(id));
        final rendered = tester.widget<Theme>(
          find.descendant(
            of: find.byType(ReviewComparisonHost),
            matching: find.byType(Theme),
          ),
        );
        expect(rendered.data.colorScheme.primary, expected.colorScheme.primary,
            reason: 'direction $id did not use its resolved theme');
        expect(rendered.data.scaffoldBackgroundColor,
            expected.scaffoldBackgroundColor);
      }
    });
  });

  // 7. Review screen IDs come from canonical runtime pattern IDs / the registry.
  group('governed review screen registry', () {
    test('screenIdsFor equals the sorted union of runtime direction patterns', () {
      final runtime = _threeDirectionRuntime();

      final expected = <String>{
        for (final direction in runtime.directions.values) ...direction.patterns,
      };
      final expectedSorted = expected.toList()..sort();

      expect(ReviewScreenRegistry.screenIdsFor(runtime), equals(expected));
      expect(ReviewScreenRegistry.screenIdsFor(runtime).toList(),
          equals(expectedSorted));
    });

    test('labelFor delegates to PrototypeRegistry.labelFor for every screen', () {
      final runtime = _threeDirectionRuntime();

      for (final id in ReviewScreenRegistry.screenIdsFor(runtime)) {
        expect(ReviewScreenRegistry.labelFor(id),
            equals(PrototypeRegistry.labelFor(id)));
      }
    });
  });

  // 8. No silent overall direction selection occurs.
  group('no silent direction selection', () {
    test('a fresh ReviewController has no selected direction', () {
      final controller = ReviewController(
        clientId: 'prototype-demo',
        repository: MemoryReviewRepository(),
        runtime: _threeDirectionRuntime(),
      );

      expect(controller.state.selectedDirection, isNull);
      expect(controller.state.screenSelections, isEmpty);
      expect(controller.state.reviewRound, 1);
    });

    testWidgets('a fresh ReviewShell shows Not selected and never defaults to A',
        (tester) async {
      final runtime = _threeDirectionRuntime();
      final controller = ReviewController(
        clientId: runtime.clientId,
        repository: MemoryReviewRepository(),
        runtime: runtime,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReviewShell(
            runtime: runtime,
            controller: controller,
            coordinator: ReviewCoordinator(
              controller: controller,
              feedbackRepository: MemoryFeedbackRepository(),
              approvalRepository: MemoryApprovalRepository(),
              refinementBatchRepository: MemoryRefinementBatchRepository(),
            ),
            actor: _reviewer,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.state.selectedDirection, isNull);
      expect(find.text('Overall direction: Not selected'), findsOneWidget);
      expect(find.text('Overall direction: a'), findsNothing);
      expect(find.text('Overall direction: A'), findsNothing);
    });
  });

  // 9. Automated QA stays a separate authority (Milestone D).
  group('automated QA boundary', () {
    test('ReviewState carries no QA finding collection', () {
      final runtime = _threeDirectionRuntime();
      final controller = ReviewController(
        clientId: runtime.clientId,
        repository: MemoryReviewRepository(),
        runtime: runtime,
      );

      final json = controller.state.toJson();
      expect(json.keys.toSet(), {
        'version',
        'client_id',
        'review_round',
        'status',
        'selected_direction',
        'screen_selections',
        'comments',
        'feedback_ids',
      });
      for (final key in json.keys) {
        expect(key.contains('qa'), isFalse, reason: 'QA state leaked into $key');
      }
    });

    testWidgets('the QA destination appears only when a QA coordinator is supplied',
        (tester) async {
      final runtime = _threeDirectionRuntime();
      final controller = ReviewController(
        clientId: runtime.clientId,
        repository: MemoryReviewRepository(),
        runtime: runtime,
      );
      final coordinator = ReviewCoordinator(
        controller: controller,
        feedbackRepository: MemoryFeedbackRepository(),
        approvalRepository: MemoryApprovalRepository(),
        refinementBatchRepository: MemoryRefinementBatchRepository(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReviewShell(
            runtime: runtime,
            controller: controller,
            coordinator: coordinator,
            actor: _reviewer,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('QA'), findsNothing);

      final qaCoordinator = QaCoordinator(
        findings: MemoryQaFindingRepository(),
        review: coordinator,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewShell(
            runtime: runtime,
            controller: controller,
            coordinator: coordinator,
            actor: _reviewer,
            qaCoordinator: qaCoordinator,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('QA'), findsWidgets);
    });

    testWidgets('promotion leaves runtime data byte-identical', (tester) async {
      final bundle = canonicalBundle(
        directionIds: const ['a', 'b'],
        patterns: const {
          'a': ['commerce.home'],
          'b': ['commerce.home'],
        },
      );
      final runtime = PrototypeRuntime.fromMap(bundle);
      final controller = ReviewController(
        clientId: runtime.clientId,
        repository: MemoryReviewRepository(),
        runtime: runtime,
      );
      final coordinator = ReviewCoordinator(
        controller: controller,
        feedbackRepository: MemoryFeedbackRepository(),
        approvalRepository: MemoryApprovalRepository(),
        refinementBatchRepository: MemoryRefinementBatchRepository(),
      );
      final qa = QaCoordinator(
        findings: MemoryQaFindingRepository(),
        review: coordinator,
      );
      final bundleJsonBefore = json.encode(bundle);
      final directionsBefore = Map.of(runtime.directions);
      final themesBefore = Map.of(runtime.directionThemes);

      await qa.recordFinding(
        QaFinding.detected(
          id: 'qa-001',
          clientId: 'prototype-demo',
          severity: QaSeverity.major,
          category: 'spacing',
          surface: QaSurface.prototype,
          screen: 'commerce.home',
          state: 'default',
          direction: 'a',
          section: 'home.product-grid',
          screenshotRef: 'sha256:capture-1',
          sourceCommitSha: 'abc123',
          ruleSource: QaRuleSource.designContract,
          ruleRef: 'spacing.card.gap',
          summary: 'spacing drift',
          actorId: 'visual-qa',
          at: DateTime.utc(2026, 9, 17, 10),
        ),
      );
      await qa.triageFinding(findingId: 'qa-001', actor: _reviewer);
      await qa.promoteFinding(findingId: 'qa-001', actor: _reviewer);

      expect(json.encode(bundle), bundleJsonBefore);
      expect(runtime.directions.keys.toSet(), directionsBefore.keys.toSet());
      expect(runtime.directionThemes.keys.toSet(), themesBefore.keys.toSet());
      expect(identical(runtime.theme, runtime.theme), isTrue);
      expect(await coordinator.listApprovals(), isEmpty);
      expect(await coordinator.allBatches(), isEmpty);
    });
  });
}
