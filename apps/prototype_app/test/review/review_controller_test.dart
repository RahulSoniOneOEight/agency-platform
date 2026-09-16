import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/review_controller.dart';
import 'package:prototype_app/review/review_repository.dart';
import 'package:prototype_app/review/review_screen_decision.dart';
import 'package:prototype_app/review/review_state.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

/// Governed runtime for the controller boundary tests:
///   a = plp + search, product-card + search-field
///   b = search,       product-card                (no plp, no search-field)
///   c = plp,          product-card
///
/// So `commerce.plp` is declared by a and c (both expose product-card) but not
/// b, and `commerce.search` is declared by a and b with `commerce.search-field`
/// exposed only by a.
PrototypeRuntime buildRuntime() {
  return PrototypeRuntime.fromMap(
    canonicalBundle(
      directionIds: const ['a', 'b', 'c'],
      patterns: const {
        'a': ['commerce.plp', 'commerce.search'],
        'b': ['commerce.search'],
        'c': ['commerce.plp'],
      },
      components: const {
        'a': ['commerce.product-card', 'commerce.search-field'],
        'b': ['commerce.product-card'],
        'c': ['commerce.product-card'],
      },
    ),
  );
}

ReviewComment comment(String id, {String text = 'note', String? screen}) {
  return ReviewComment(
    id: id,
    scope: screen == null ? ReviewCommentScope.general : ReviewCommentScope.screen,
    text: text,
    screen: screen,
  );
}

ReviewState buildState({
  String clientId = 'prototype-demo',
  int reviewRound = 1,
  String? selectedDirection,
  Map<String, ReviewScreenDecision> screenSelections = const {},
}) {
  return ReviewState(
    version: ReviewState.currentVersion,
    clientId: clientId,
    reviewRound: reviewRound,
    status: ReviewStatus.inReview,
    selectedDirection: selectedDirection,
    screenSelections: screenSelections,
    comments: const [],
  );
}

/// Records every save so tests can prove a rejected mutation has zero
/// persistence side effects.
final class RecordingRepository implements ReviewRepository {
  ReviewState? _stored;
  int saveCount = 0;

  @override
  Future<ReviewState?> load(String clientId) async => _stored;

  @override
  Future<void> save(ReviewState state) async {
    saveCount++;
    _stored = state;
  }
}

/// JSON-backed fake: mirrors a real persistence layer that parses/serializes
/// through the wire contract, so a v1 seed genuinely exercises migration.
final class JsonReviewRepository implements ReviewRepository {
  JsonReviewRepository([this.seed]);

  final Map<String, dynamic>? seed;
  Map<String, dynamic>? stored;
  int saveCount = 0;

  @override
  Future<ReviewState?> load(String clientId) async =>
      seed == null ? null : ReviewState.fromJson(seed!);

  @override
  Future<void> save(ReviewState state) async {
    saveCount++;
    stored = state.toJson();
  }
}

void main() {
  late PrototypeRuntime runtime;
  late RecordingRepository repository;
  late ReviewController controller;

  setUp(() {
    runtime = buildRuntime();
    repository = RecordingRepository();
    controller = ReviewController(
      clientId: runtime.clientId,
      repository: repository,
      runtime: runtime,
    );
  });

  group('initial state', () {
    test('starts with no selection, round 1, in review', () {
      expect(controller.clientId, 'prototype-demo');
      expect(controller.state.version, ReviewState.currentVersion);
      expect(controller.state.clientId, 'prototype-demo');
      expect(controller.state.selectedDirection, isNull);
      expect(controller.state.reviewRound, 1);
      expect(controller.state.status, ReviewStatus.inReview);
      expect(controller.state.screenSelections, isEmpty);
      expect(controller.state.comments, isEmpty);
    });
  });

  group('selectDirection', () {
    test('stores a runtime direction and auto-persists it', () async {
      await controller.selectDirection('b');

      expect(controller.state.selectedDirection, 'b');
      expect((await repository.load('prototype-demo'))!.selectedDirection, 'b');
      expect(repository.saveCount, 1);
    });

    test('clears the overall selection back to null', () async {
      await controller.selectDirection('b');
      await controller.selectDirection(null);

      expect(controller.state.selectedDirection, isNull);
      expect((await repository.load('prototype-demo'))!.selectedDirection, isNull);
    });

    test('rejects a direction that is not declared by the runtime', () async {
      var notifications = 0;
      controller.addListener(() => notifications++);

      await expectLater(
        () => controller.selectDirection('z'),
        throwsStateError,
      );

      expect(controller.state.selectedDirection, isNull);
      expect(repository.saveCount, 0);
      expect(notifications, 0);
    });

    test('normalizes away a screen override made redundant by the new overall',
        () async {
      await controller.setScreenDirection('commerce.search', 'a');
      expect(controller.state.screenSelections, {
        'commerce.search': ReviewScreenDecision(direction: 'a'),
      });

      await controller.selectDirection('a');

      expect(controller.state.selectedDirection, 'a');
      expect(controller.state.screenSelections, isEmpty);
      expect((await repository.load('prototype-demo'))!.screenSelections, isEmpty);
    });
  });

  group('setScreenDirection', () {
    test('adds one governed screen override without clearing others', () async {
      await controller.setScreenDirection('commerce.plp', 'c');
      await controller.setScreenDirection('commerce.search', 'a');

      expect(controller.state.screenSelections, {
        'commerce.plp': ReviewScreenDecision(direction: 'c'),
        'commerce.search': ReviewScreenDecision(direction: 'a'),
      });
      expect(
        (await repository.load('prototype-demo'))!.screenSelections,
        {
          'commerce.plp': ReviewScreenDecision(direction: 'c'),
          'commerce.search': ReviewScreenDecision(direction: 'a'),
        },
      );
    });

    test('updates an existing screen override in place', () async {
      await controller.setScreenDirection('commerce.search', 'a');
      await controller.setScreenDirection('commerce.search', 'b');

      expect(controller.state.screenSelections, {
        'commerce.search': ReviewScreenDecision(direction: 'b'),
      });
    });

    test('rejects a direction that does not include the screen', () async {
      var notifications = 0;
      controller.addListener(() => notifications++);

      await expectLater(
        () => controller.setScreenDirection('commerce.plp', 'b'),
        throwsStateError,
      );

      expect(controller.state.screenSelections, isEmpty);
      expect(repository.saveCount, 0);
      expect(notifications, 0);
    });

    test('rejects an unknown screen id', () async {
      await expectLater(
        () => controller.setScreenDirection('commerce.unknown', 'a'),
        throwsStateError,
      );
      expect(repository.saveCount, 0);
    });
  });

  group('clearScreenDirection', () {
    test('clears the screen direction and re-normalizes its sections', () async {
      await controller.selectDirection('a');
      await controller.setScreenDirection('commerce.search', 'b');
      await controller.setSectionDirection(
        'commerce.search',
        'search.results-grid',
        'a',
      );
      expect(controller.state.screenSelections['commerce.search']!.direction, 'b');
      expect(
        controller.state.screenSelections['commerce.search']!.sections,
        {'search.results-grid': 'a'},
      );

      await controller.clearScreenDirection('commerce.search');

      // The effective screen direction is now the overall 'a', so the 'a'
      // section override is redundant and the empty screen entry is dropped.
      expect(controller.state.screenSelections, isEmpty);
    });

    test('removes the entry entirely when nothing meaningful remains', () async {
      await controller.setScreenDirection('commerce.plp', 'c');

      await controller.clearScreenDirection('commerce.plp');

      expect(controller.state.screenSelections, isEmpty);
      expect((await repository.load('prototype-demo'))!.screenSelections, isEmpty);
    });

    test('setScreenDirection(screenId, null) is the same as clearing', () async {
      await controller.setScreenDirection('commerce.plp', 'c');

      await controller.setScreenDirection('commerce.plp', null);

      expect(controller.state.screenSelections, isEmpty);
    });

    test('is a no-op when the screen has no explicit direction', () async {
      await controller.setScreenDirection('commerce.plp', 'c');
      await controller.clearScreenDirection('commerce.plp');
      final savesAfterClear = repository.saveCount;

      var notifications = 0;
      controller.addListener(() => notifications++);
      await controller.clearScreenDirection('commerce.plp');

      expect(notifications, 0);
      expect(repository.saveCount, savesAfterClear);
    });
  });

  group('setSectionDirection', () {
    test('sets a compatible section override and auto-persists it', () async {
      await controller.selectDirection('b');

      await controller.setSectionDirection(
        'commerce.search',
        'search.search-field',
        'a',
      );

      expect(controller.state.screenSelections, {
        'commerce.search': ReviewScreenDecision(
          sections: const {'search.search-field': 'a'},
        ),
      });
      expect(
        (await repository.load('prototype-demo'))!.screenSelections,
        {
          'commerce.search': ReviewScreenDecision(
            sections: const {'search.search-field': 'a'},
          ),
        },
      );
    });

    test('removes a redundant override equal to the effective screen', () async {
      await controller.selectDirection('a');
      await controller.setSectionDirection(
        'commerce.search',
        'search.results-grid',
        'b',
      );
      expect(
        controller.state.screenSelections['commerce.search']!.sections,
        {'search.results-grid': 'b'},
      );

      await controller.setSectionDirection(
        'commerce.search',
        'search.results-grid',
        'a',
      );

      expect(controller.state.screenSelections, isEmpty);
    });

    test('rejects a source direction that does not expose the section', () async {
      await controller.selectDirection('a');
      final savesBefore = repository.saveCount;
      var notifications = 0;
      controller.addListener(() => notifications++);

      await expectLater(
        () => controller.setSectionDirection(
          'commerce.search',
          'search.search-field',
          'b',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Not present in Direction B'),
          ),
        ),
      );

      expect(controller.state.screenSelections, isEmpty);
      expect(repository.saveCount, savesBefore);
      expect(notifications, 0);
    });

    test('rejects a section that does not belong to the named screen', () async {
      await controller.selectDirection('a');
      final savesBefore = repository.saveCount;

      await expectLater(
        () => controller.setSectionDirection(
          'commerce.search',
          'plp.product-grid',
          'c',
        ),
        throwsStateError,
      );
      expect(repository.saveCount, savesBefore);
    });

    test('rejects a section override when no effective screen direction exists',
        () async {
      await expectLater(
        () => controller.setSectionDirection(
          'commerce.search',
          'search.results-grid',
          'b',
        ),
        throwsStateError,
      );
      expect(repository.saveCount, 0);
    });
  });

  group('clearSectionDirection', () {
    test('removes only the named section override', () async {
      await controller.selectDirection('b');
      await controller.setSectionDirection(
        'commerce.search',
        'search.search-field',
        'a',
      );

      await controller.clearSectionDirection(
        'commerce.search',
        'search.search-field',
      );

      expect(controller.state.screenSelections, isEmpty);
    });
  });

  group('resetScreenMix', () {
    test('removes the screen direction and all its section overrides', () async {
      await controller.selectDirection('a');
      await controller.setScreenDirection('commerce.search', 'b');
      await controller.setSectionDirection(
        'commerce.search',
        'search.results-grid',
        'a',
      );
      expect(controller.state.screenSelections['commerce.search'], isNotNull);

      await controller.resetScreenMix('commerce.search');

      expect(controller.state.screenSelections, isEmpty);
      expect((await repository.load('prototype-demo'))!.screenSelections, isEmpty);
    });

    test('leaves other screens untouched', () async {
      await controller.selectDirection('a');
      await controller.setScreenDirection('commerce.plp', 'c');
      await controller.setScreenDirection('commerce.search', 'b');

      await controller.resetScreenMix('commerce.search');

      expect(controller.state.screenSelections, {
        'commerce.plp': ReviewScreenDecision(direction: 'c'),
      });
    });
  });

  group('parent-change normalization', () {
    test('a screen parent change prunes a newly redundant child override',
        () async {
      await controller.setScreenDirection('commerce.search', 'a');
      await controller.setSectionDirection(
        'commerce.search',
        'search.results-grid',
        'b',
      );
      expect(
        controller.state.screenSelections['commerce.search']!.sections,
        {'search.results-grid': 'b'},
      );

      await controller.setScreenDirection('commerce.search', 'b');

      final decision = controller.state.screenSelections['commerce.search'];
      expect(decision, isNotNull);
      expect(decision!.direction, 'b');
      expect(decision.sections, isEmpty);
    });

    test('an overall change revalidates inherited screens and prunes stale overrides',
        () async {
      await controller.selectDirection('a');
      await controller.setSectionDirection(
        'commerce.search',
        'search.results-grid',
        'b',
      );
      expect(controller.state.screenSelections, isNotEmpty);

      await controller.selectDirection('b');

      expect(controller.state.selectedDirection, 'b');
      expect(controller.state.screenSelections, isEmpty);
    });
  });

  group('comments', () {
    test('addComment appends and persists', () async {
      await controller.addComment(comment('c1'));

      expect(controller.state.comments.map((c) => c.id), ['c1']);
      expect((await repository.load('prototype-demo'))!.comments, hasLength(1));
    });

    test('addComment rejects a duplicate id with StateError', () async {
      await controller.addComment(comment('c1'));

      expect(() => controller.addComment(comment('c1')), throwsStateError);
      expect(controller.state.comments, hasLength(1));
    });

    test('updateComment replaces the comment with the same id', () async {
      await controller.addComment(comment('c1', text: 'old'));
      await controller.updateComment(comment('c1', text: 'new'));

      expect(controller.state.comments.single.text, 'new');
      expect((await repository.load('prototype-demo'))!.comments.single.text, 'new');
    });

    test('updateComment throws StateError for an unknown id', () async {
      await controller.addComment(comment('c1'));

      expect(() => controller.updateComment(comment('missing')), throwsStateError);
    });

    test('comments are preserved across decision mutations', () async {
      await controller.selectDirection('b');
      await controller.addComment(comment('c1'));
      await controller.setScreenDirection('commerce.search', 'a');

      expect(controller.state.comments.map((c) => c.id), ['c1']);
      expect(controller.state.selectedDirection, 'b');
      expect(
        controller.state.screenSelections['commerce.search']!.direction,
        'a',
      );
    });
  });

  group('setStatus', () {
    test('sets the given status and persists', () async {
      await controller.setStatus(ReviewStatus.needsRevision);

      expect(controller.state.status, ReviewStatus.needsRevision);
      expect((await repository.load('prototype-demo'))!.status, ReviewStatus.needsRevision);
    });
  });

  group('advanceRound', () {
    test('increments by exactly one and preserves selections and comments', () async {
      await controller.selectDirection('b');
      await controller.setScreenDirection('commerce.search', 'a');
      await controller.addComment(comment('c1'));

      await controller.advanceRound();

      expect(controller.state.reviewRound, 2);
      expect(controller.state.selectedDirection, 'b');
      expect(controller.state.screenSelections, {
        'commerce.search': ReviewScreenDecision(direction: 'a'),
      });
      expect(controller.state.comments.map((c) => c.id), ['c1']);
      expect((await repository.load('prototype-demo'))!.reviewRound, 2);
    });

    test('never drops below one', () async {
      final low = ReviewController(
        clientId: 'prototype-demo',
        repository: repository,
        runtime: runtime,
        initialState: buildState(reviewRound: 0),
      );

      await low.advanceRound();

      expect(low.state.reviewRound, 1);
    });
  });

  group('load', () {
    test('restores persisted state when one exists', () async {
      await repository.save(buildState(reviewRound: 2, selectedDirection: 'c'));

      await controller.load();

      expect(controller.state.reviewRound, 2);
      expect(controller.state.selectedDirection, 'c');
    });

    test('keeps the initial state when nothing is persisted', () async {
      await controller.load();

      expect(controller.state.reviewRound, 1);
      expect(controller.state.selectedDirection, isNull);
    });

    test('migrates a v1 loaded state to v2 and the next mutation saves v2',
        () async {
      final jsonRepository = JsonReviewRepository({
        'version': 1,
        'client_id': 'prototype-demo',
        'review_round': 3,
        'status': 'needs_revision',
        'selected_direction': 'a',
        'screen_selections': {'commerce.search': 'b'},
        'comments': [
          {'id': 'c1', 'scope': 'general', 'text': 'keep me'},
        ],
      });
      final migrating = ReviewController(
        clientId: 'prototype-demo',
        repository: jsonRepository,
        runtime: runtime,
      );

      await migrating.load();

      expect(migrating.loadErrors, isEmpty);
      expect(migrating.state.version, ReviewState.currentVersion);
      expect(
        migrating.state.screenSelections['commerce.search']!.direction,
        'b',
      );
      expect(migrating.state.reviewRound, 3);
      expect(migrating.state.status, ReviewStatus.needsRevision);
      expect(migrating.state.comments.single.text, 'keep me');

      await migrating.selectDirection('a');

      expect(jsonRepository.stored!['version'], 2);
      final reloaded = ReviewState.fromJson(jsonRepository.stored!);
      expect(reloaded.selectedDirection, 'a');
    });

    test('load adopts a valid persisted state', () async {
      await repository.save(buildState(selectedDirection: 'b'));
      final validating = ReviewController(
        clientId: 'prototype-demo',
        repository: repository,
        runtime: runtime,
        validate: (state) => <String>[],
      );

      await validating.load();

      expect(validating.state.selectedDirection, 'b');
      expect(validating.loadErrors, isEmpty);
    });

    test('load never adopts invalid persisted state', () async {
      await repository.save(buildState(reviewRound: 0));
      final validating = ReviewController(
        clientId: 'prototype-demo',
        repository: repository,
        runtime: runtime,
        validate: (state) => state.reviewRound < 1
            ? <String>['invalid review round: ${state.reviewRound}']
            : <String>[],
      );

      await validating.load();

      expect(validating.state.reviewRound, 1);
      expect(validating.loadErrors, ['invalid review round: 0']);
    });
  });

  group('listeners', () {
    test('notifies after each successful mutation', () async {
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.selectDirection('b');
      await controller.setScreenDirection('commerce.search', 'a');
      await controller.addComment(comment('c1'));
      await controller.updateComment(comment('c1', text: 'edited'));
      await controller.setStatus(ReviewStatus.needsRevision);
      await controller.advanceRound();

      expect(notifications, 6);
    });

    test('does not notify when a mutation is rejected', () async {
      await controller.addComment(comment('c1'));
      var notifications = 0;
      controller.addListener(() => notifications++);

      await expectLater(
        () => controller.addComment(comment('c1')),
        throwsStateError,
      );

      expect(notifications, 0);
    });

    test('rejected mutations neither persist nor notify', () async {
      await controller.addComment(comment('c1'));
      final persistedBefore = await repository.load('prototype-demo');
      final savesBefore = repository.saveCount;
      final stateBefore = controller.state;
      var notifications = 0;
      controller.addListener(() => notifications++);

      await expectLater(
        () => controller.addComment(comment('c1', text: 'duplicate')),
        throwsStateError,
      );
      await expectLater(
        () => controller.updateComment(comment('missing', text: 'nope')),
        throwsStateError,
      );
      await expectLater(
        () => controller.setScreenDirection('commerce.plp', 'b'),
        throwsStateError,
      );
      await expectLater(
        () => controller.selectDirection('z'),
        throwsStateError,
      );

      expect(notifications, 0);
      expect(repository.saveCount, savesBefore);
      expect(await repository.load('prototype-demo'), persistedBefore);
      expect(identical(controller.state, stateBefore), isTrue);
      expect(controller.state.comments.single.text, 'note');
    });
  });

  group('transactional persistence', () {
    test('a failing save leaves state and listeners untouched', () async {
      final failing = _FailingRepository();
      final failingController = ReviewController(
        clientId: 'prototype-demo',
        repository: failing,
        runtime: runtime,
      );
      final before = failingController.state;
      var notifications = 0;
      failingController.addListener(() => notifications++);

      await expectLater(
        () => failingController.selectDirection('a'),
        throwsA(isA<Exception>()),
      );

      expect(identical(failingController.state, before), isTrue);
      expect(notifications, 0);
    });

    test('load normalizes a redundant legacy v1 state instead of rejecting it',
        () async {
      final repo = JsonReviewRepository({
        'version': 1,
        'client_id': 'prototype-demo',
        'review_round': 3,
        'status': 'in_review',
        'selected_direction': 'a',
        'screen_selections': {'commerce.plp': 'a'},
        'comments': [],
      });
      final loaded = ReviewController(
        clientId: 'prototype-demo',
        repository: repo,
        runtime: runtime,
      );

      await loaded.load();

      expect(loaded.loadErrors, isEmpty);
      expect(loaded.state.reviewRound, 3);
      // The redundant screen override equal to the overall direction is pruned.
      expect(loaded.state.screenSelections, isEmpty);
      expect(loaded.state.selectedDirection, 'a');
    });
  });
}

/// Repository whose save always fails, to prove the save-before-adopt contract.
final class _FailingRepository implements ReviewRepository {
  @override
  Future<ReviewState?> load(String clientId) async => null;

  @override
  Future<void> save(ReviewState state) async {
    throw Exception('save failed');
  }
}
