import 'dart:convert';
import 'dart:io';

import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/fixtures/fixture_repository.dart';
import 'package:prototype_app/review/feedback_record.dart';
import 'package:prototype_app/review/memory_approval_repository.dart';
import 'package:prototype_app/review/memory_feedback_repository.dart';
import 'package:prototype_app/review/memory_refinement_batch_repository.dart';
import 'package:prototype_app/review/memory_review_repository.dart';
import 'package:prototype_app/review/refinement_batch.dart';
import 'package:prototype_app/review/refinement_execution_result.dart';
import 'package:prototype_app/review/review_actor.dart';
import 'package:prototype_app/review/review_comparison_host.dart';
import 'package:prototype_app/review/review_coordinator.dart';
import 'package:prototype_app/review/review_comparison_layout.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_direction_comparison.dart';
import 'package:prototype_app/review/review_mixed_preview.dart';
import 'package:prototype_app/review/review_screen_availability.dart';
import 'package:prototype_app/review/review_screen_comparison.dart';
import 'package:prototype_app/review/review_section_compatibility.dart';
import 'package:prototype_app/review/review_section_registry.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

/// Loads the committed reference-client bundle exactly as the app does.
///
/// Tests run on the VM from `apps/prototype_app`, so the relative asset path
/// resolves against the package root.
PrototypeRuntime _loadReferenceRuntime() {
  final decoded =
      json.decode(File('assets/generated/prototype-demo.json').readAsStringSync())
          as Map;
  return PrototypeRuntime.fromMap(Map<String, dynamic>.from(decoded));
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

const _reviewer = ReviewActor(
  id: 'reviewer-123',
  name: 'Rahul',
  role: ReviewRole.reviewer,
);
const _agent = ReviewActor(
  id: 'opencode',
  name: 'OpenCode',
  role: ReviewRole.agent,
);
const _approver = ReviewActor(
  id: 'approver-456',
  name: 'Priya',
  role: ReviewRole.approver,
);

void main() {
  final runtime = _loadReferenceRuntime();

  group('reference client · direction order and availability', () {
    test('orderedDirections is the runtime declared order', () {
      expect(
        ReviewScreenAvailability.orderedDirections(runtime),
        equals(<String>['a', 'b', 'c']),
      );
      expect(
        ReviewScreenAvailability.orderedDirections(runtime),
        equals(runtime.allowedDirections),
      );
    });

    test('per-pair availability matches the declared direction patterns', () {
      // NOTE: the committed reference bundle declares
      //   a = search/plp/pdp/cart/rfq
      //   b = trade-dashboard/reorder/cart
      //   c = home/plp/pdp/rfq/trade-dashboard
      // so `commerce.search` is declared only by a; b and c are unavailable.
      expect(
        ReviewScreenAvailability.isSupported(runtime, 'a', 'commerce.search'),
        isTrue,
      );
      expect(
        ReviewScreenAvailability.isSupported(runtime, 'b', 'commerce.search'),
        isFalse,
      );
      expect(
        ReviewScreenAvailability.isSupported(runtime, 'c', 'commerce.search'),
        isFalse,
      );
      expect(
        ReviewScreenAvailability.isSupported(runtime, 'c', 'commerce.home'),
        isTrue,
      );
      expect(
        ReviewScreenAvailability.isSupported(runtime, 'a', 'commerce.home'),
        isFalse,
      );
      expect(
        ReviewScreenAvailability.isSupported(runtime, 'b', 'commerce.trade-dashboard'),
        isTrue,
      );
      expect(
        ReviewScreenAvailability.isSupported(runtime, 'b', 'commerce.reorder'),
        isTrue,
      );
      expect(
        ReviewScreenAvailability.isSupported(runtime, 'b', 'commerce.cart'),
        isTrue,
      );
    });

    test('screens is the sorted union of every direction pattern', () {
      final expected = <String>{
        for (final direction in runtime.directions.values) ...direction.patterns,
      }.toList()
        ..sort();

      expect(ReviewScreenAvailability.screens(runtime), equals(expected));
      expect(
        ReviewScreenAvailability.screens(runtime),
        containsAll(<String>[
          'commerce.home',
          'commerce.search',
          'commerce.trade-dashboard',
        ]),
      );
    });

    test('directions resolve to distinct direction themes', () {
      final dataA = AgencyTheme.light(runtime.themeForDirection('a'));
      final dataB = AgencyTheme.light(runtime.themeForDirection('b'));
      final dataC = AgencyTheme.light(runtime.themeForDirection('c'));

      // The committed reference bundle intentionally shares one brand primary
      // (#1155CC) across all three directions, so `colorScheme.primary` does
      // NOT discriminate them. Directions differ through B.1E theme overrides
      // (density, section spacing, card radius); lock those discriminating
      // values instead of the shared brand color.
      final tokensA = dataA.extension<AgencyThemeTokens>()!;
      final tokensB = dataB.extension<AgencyThemeTokens>()!;
      final tokensC = dataC.extension<AgencyThemeTokens>()!;

      expect(tokensA.density, isNot(tokensB.density));
      expect(tokensA.sectionSpacing, isNot(tokensB.sectionSpacing));
      expect(tokensA.cardRadius, isNot(tokensB.cardRadius));

      expect(tokensA.density, isNot(tokensC.density));
      expect(tokensA.sectionSpacing, isNot(tokensC.sectionSpacing));
      expect(tokensA.cardRadius, isNot(tokensC.cardRadius));
    });
  });

  group('reference client · screen comparison', () {
    // CAVEAT: do NOT render `commerce.home` or `commerce.plp` with the real
    // reference theme in widget tests. Those two shared patterns have a
    // pre-existing `ProductCard`/`mainAxisExtent` overflow (also present in
    // normal prototype mode) that is out of C.2 scope. `commerce.search`,
    // `commerce.pdp`, and `commerce.cart` are safe.
    testWidgets(
        'wide surface renders the supporting directions and the unavailable state',
        (tester) async {
      final controller = _freshController(runtime);
      await _pumpScreenComparison(
        tester,
        runtime,
        controller,
        const Size(1600, 900),
      );

      await tester.tap(
        find.byKey(ReviewScreenComparison.screenChipKey('commerce.search')),
      );
      await tester.pumpAndSettle();

      // commerce.search is declared only by direction a; b and c show the
      // neutral unavailable state (b declares trade-dashboard/reorder/cart).
      expect(find.byType(ReviewComparisonHost), findsOneWidget);
      expect(
        find.byKey(ReviewScreenComparison.unavailableKey('b')),
        findsOneWidget,
      );
      expect(
        find.byKey(ReviewScreenComparison.unavailableKey('c')),
        findsOneWidget,
      );
      expect(
        find.text('This screen is not part of Direction B'),
        findsOneWidget,
      );
      expect(
        find.text('This screen is not part of Direction C'),
        findsOneWidget,
      );
      expect(controller.state.selectedDirection, isNull);
    });

    testWidgets('supported panels use the direction-resolved theme',
        (tester) async {
      final controller = _freshController(runtime);
      await _pumpScreenComparison(
        tester,
        runtime,
        controller,
        const Size(1600, 900),
      );

      // commerce.cart is declared by a and b, so two real panels render.
      await tester.tap(
        find.byKey(ReviewScreenComparison.screenChipKey('commerce.cart')),
      );
      await tester.pumpAndSettle();

      final supported = const ['a', 'b']
          .where((id) =>
              ReviewScreenAvailability.isSupported(runtime, id, 'commerce.cart'))
          .toList();
      expect(supported, equals(<String>['a', 'b']));

      for (final id in supported) {
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
          reason: 'direction $id did not use its resolved primary',
        );
        expect(
          rendered.data.scaffoldBackgroundColor,
          expected.scaffoldBackgroundColor,
          reason: 'direction $id did not use its resolved surface',
        );

        // The shared brand primary cannot discriminate directions; the
        // direction-resolved tokens can (and catch a base-theme leak).
        final tokens = rendered.data.extension<AgencyThemeTokens>()!;
        expect(tokens.sectionSpacing, runtime.themeForDirection(id).spacing['section']);
        expect(tokens.density, runtime.themeForDirection(id).density);
      }
    });
  });

  group('reference client · directions comparison', () {
    testWidgets('renders all three real direction names', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReviewDirectionComparison(
              runtime: runtime,
              controller: _freshController(runtime),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final id in const ['a', 'b', 'c']) {
        expect(
          find.text(runtime.directions[id]!.name),
          findsOneWidget,
          reason: 'missing real direction name for $id',
        );
      }
    });
  });

  group('reference client · section availability and compatibility', () {
    ReviewSectionCompatibilityResult evaluate({
      required String screenId,
      required String sectionId,
      required String source,
      String base = 'a',
    }) {
      return ReviewSectionCompatibility.evaluate(
        runtime: runtime,
        screenId: screenId,
        sectionId: sectionId,
        sourceDirectionId: source,
        baseDirectionId: base,
      );
    }

    test('governed sections exist for the composed reference screens', () {
      expect(
        ReviewSectionRegistry.sectionsForScreen('commerce.plp').map((d) => d.id),
        contains('plp.product-grid'),
      );
      expect(
        ReviewSectionRegistry.sectionsForScreen('commerce.pdp').map((d) => d.id),
        contains('pdp.price'),
      );
    });

    test('plp.product-grid mixes from c into a base a (both declare plp)', () {
      final result = evaluate(
        screenId: 'commerce.plp',
        sectionId: 'plp.product-grid',
        source: 'c',
      );
      expect(result.allowed, isTrue);
    });

    test('pdp.price mixes from c into a base a (both declare pdp)', () {
      final result = evaluate(
        screenId: 'commerce.pdp',
        sectionId: 'pdp.price',
        source: 'c',
      );
      expect(result.allowed, isTrue);
    });

    test('plp.product-grid is unavailable from b (b does not declare plp)', () {
      final result = evaluate(
        screenId: 'commerce.plp',
        sectionId: 'plp.product-grid',
        source: 'b',
      );
      expect(result.allowed, isFalse);
      expect(result.reason, 'Not present in Direction B');
    });

    test('search.search-field is unavailable from c (c does not declare search)', () {
      final result = evaluate(
        screenId: 'commerce.search',
        sectionId: 'search.search-field',
        source: 'c',
      );
      expect(result.allowed, isFalse);
      expect(result.reason, 'Not present in Direction C');
    });
  });

  group('reference client · controller mix and live preview', () {
    late MemoryReviewRepository repository;
    late ReviewController controller;

    setUp(() {
      repository = MemoryReviewRepository();
      controller = ReviewController(
        clientId: runtime.clientId,
        repository: repository,
        runtime: runtime,
      );
    });

    test('plp.product-grid mixes from c into a base a through the controller',
        () async {
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

      final persisted = await repository.load('prototype-demo');
      expect(persisted!.toJson()['version'], 2);
      expect(
        (persisted.toJson()['screen_selections'] as Map<String, dynamic>)[
            'commerce.plp'],
        {
          'sections': {'plp.product-grid': 'c'},
        },
      );
    });

    testWidgets(
        'pdp.price mixes from c into a base a and the preview applies the source theme',
        (tester) async {
      await controller.selectDirection('a');
      await controller.setSectionDirection('commerce.pdp', 'pdp.price', 'c');

      expect(
        controller.state.screenSelections['commerce.pdp']!.sections['pdp.price'],
        'c',
      );

      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReviewMixedPreview(
              runtime: runtime,
              fixtures: FixtureRepository.fromRuntime(runtime),
              screenId: 'commerce.pdp',
              state: controller.state,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final base = AgencyTheme.light(runtime.themeForDirection('a'));
      final source = AgencyTheme.light(runtime.themeForDirection('c'));
      expect(
        base.extension<AgencyThemeTokens>()!.cardRadius,
        isNot(source.extension<AgencyThemeTokens>()!.cardRadius),
      );

      expect(
        find.byKey(ReviewMixedPreview.overrideThemeKey('pdp.price')),
        findsOneWidget,
      );

      final priceFinder = find.descendant(
        of: find.byKey(ReviewMixedPreview.sectionKey('pdp.price')),
        matching: find.byType(PriceSection),
      );
      expect(priceFinder, findsOneWidget);
      final priceTheme = Theme.of(tester.element(priceFinder));
      expect(priceTheme.colorScheme.primary, source.colorScheme.primary);
      expect(
        AgencyThemeTokens.of(tester.element(priceFinder)).cardRadius,
        source.extension<AgencyThemeTokens>()!.cardRadius,
      );

      // An inherited sibling section stays under the base screen theme.
      final imageFinder = find.byType(ProductImageSection);
      expect(imageFinder, findsOneWidget);
      final imageTheme = Theme.of(tester.element(imageFinder));
      expect(imageTheme.colorScheme.primary, base.colorScheme.primary);
      expect(
        AgencyThemeTokens.of(tester.element(imageFinder)).cardRadius,
        base.extension<AgencyThemeTokens>()!.cardRadius,
      );
      expect(tester.takeException(), isNull);
    });

    test('an unavailable section source is rejected with a deterministic reason',
        () async {
      await controller.selectDirection('a');
      final before = controller.state;

      await expectLater(
        controller.setSectionDirection('commerce.plp', 'plp.product-grid', 'b'),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          'Not present in Direction B',
        )),
      );

      expect(identical(controller.state, before), isTrue);
      final persisted = await repository.load('prototype-demo');
      expect(persisted!.selectedDirection, 'a');
      expect(persisted.screenSelections, isEmpty);
    });
  });

  group('reference client · C.7 refinement loop', () {
    late ReviewController controller;
    late ReviewCoordinator coordinator;
    late MemoryFeedbackRepository feedback;

    setUp(() {
      controller = _freshController(runtime);
      feedback = MemoryFeedbackRepository();
      coordinator = ReviewCoordinator(
        controller: controller,
        feedbackRepository: feedback,
        approvalRepository: MemoryApprovalRepository(),
        refinementBatchRepository: MemoryRefinementBatchRepository(),
      );
    });

    test('refines a governed screen feedback to addressed, then approves',
        () async {
      await controller.selectDirection('a');
      await coordinator.createFeedback(
        actor: _reviewer,
        id: 'feedback-201',
        scope: FeedbackScope.section,
        text: 'Tighten the search field spacing',
        target: const FeedbackTarget(
          screen: 'commerce.search',
          section: 'search.search-field',
        ),
        blocking: true,
      );

      await coordinator.createDraftBatch(
        actor: _reviewer,
        id: 'batch-201',
        feedbackIds: const ['feedback-201'],
        intendedScope: IntendedScope(
          screens: const ['commerce.search'],
          sections: const ['search.search-field'],
        ),
        proposed: ChangeClassification.implementationOnly,
      );
      await coordinator.confirmBatchClassification(
        actor: _reviewer,
        batchId: 'batch-201',
        confirmed: ChangeClassification.implementationOnly,
      );
      await coordinator.markBatchReady(actor: _reviewer, batchId: 'batch-201');
      await coordinator.startBatch(actor: _agent, batchId: 'batch-201');
      final reviewed = await coordinator.recordBatchValidation(
        actor: _agent,
        batchId: 'batch-201',
        result: RefinementExecutionResult(
          status: RefinementExecutionStatus.passed,
          commitSha: 'abc123',
          checks: const [
            ValidationCheck(
              name: 'flutter test test/review',
              passed: true,
              details: 'all green',
            ),
          ],
        ),
      );

      expect(reviewed.status, RefinementBatchStatus.readyForReview);
      final addressed = (await coordinator.loadFeedback('feedback-201'))!;
      expect(addressed.status, FeedbackStatus.addressed);
      expect(addressed.status, isNot(FeedbackStatus.resolved));

      await coordinator.resolveFeedback(
        actor: _reviewer,
        feedbackId: 'feedback-201',
      );
      await coordinator.completeBatch(actor: _reviewer, batchId: 'batch-201');
      await coordinator.closeCurrentRound(actor: _reviewer);
      final snapshot = await coordinator.createApproval(
        reviewer: _reviewer,
        approver: _approver,
        sourceCommitSha: 'abc123',
      );

      expect(snapshot.version, 1);
      expect(snapshot.reviewRound, 1);
      expect((await coordinator.loadBatch('batch-201'))!.status,
          RefinementBatchStatus.completed);

      // C.3 section mixing still persists normally alongside the C.7 flow.
      await controller.setSectionDirection(
        'commerce.plp',
        'plp.product-grid',
        'c',
      );
      final persisted = controller.state.toJson();
      expect(persisted['version'], 2);
      expect(
        (persisted['screen_selections'] as Map<String, dynamic>)['commerce.plp'],
        {
          'sections': {'plp.product-grid': 'c'},
        },
      );
    });
  });
}
