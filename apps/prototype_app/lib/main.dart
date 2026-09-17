import 'dart:async';

import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';

import 'prototype_app.dart';
import 'qa/memory_qa_finding_repository.dart';
import 'qa/qa_coordinator.dart';
import 'review/memory_approval_repository.dart';
import 'review/memory_feedback_repository.dart';
import 'review/memory_refinement_batch_repository.dart';
import 'review/memory_review_repository.dart';
import 'review/review_actor.dart';
import 'review/review_controller.dart';
import 'review/review_coordinator.dart';
import 'review/review_route.dart';
import 'review/review_shell.dart';
import 'runtime/prototype_runtime.dart';
import 'runtime/runtime_exception.dart';
import 'runtime/runtime_loader.dart';
import 'screens/runtime_error_screen.dart';

/// Local/demo convenience default. This is a declared default, not a fallback
/// for invalid explicit client IDs, and it is never applied to Review Mode.
const String kDefaultClientId = 'prototype-demo';

/// The local reviewer identity used by the standalone Review Mode shell.
///
/// A real deployment supplies reviewer/approver identities from its own
/// identity layer; the prototype composition root uses one explicit default.
const ReviewActor kLocalReviewer = ReviewActor(
  id: 'reviewer-local',
  name: 'Local Reviewer',
  role: ReviewRole.reviewer,
);

void main() {
  runApp(const PrototypeBootstrap());
}

class PrototypeBootstrap extends StatefulWidget {
  const PrototypeBootstrap({super.key, this.uri, this.loadRuntime});

  /// Overrides `Uri.base` in tests. Review Mode is detected from this URI.
  final Uri? uri;

  /// Overrides `RuntimeLoader.loadClient` in tests. Both modes share one load.
  final Future<PrototypeRuntime> Function(String clientId)? loadRuntime;

  @override
  State<PrototypeBootstrap> createState() => _PrototypeBootstrapState();
}

class _PrototypeBootstrapState extends State<PrototypeBootstrap> {
  late final ReviewRouteRequest _route;
  late final Future<PrototypeRuntime>? _runtime;
  RuntimeException? _routeError;
  String? _requestedDirection;
  ReviewController? _reviewController;
  ReviewCoordinator? _reviewCoordinator;
  bool _showPrototype = false;

  @override
  void initState() {
    super.initState();
    final uri = widget.uri ?? Uri.base;
    _route = parseReviewRoute(uri);

    final reviewClientId = _route.clientId;
    if (_route.isReviewMode &&
        (reviewClientId == null || reviewClientId.trim().isEmpty)) {
      _routeError = const RuntimeException(
        code: RuntimeException.clientNotFound,
        message:
            'Review Mode requires an explicit client id (use /review?client=<id>).',
      );
      _runtime = null;
      return;
    }

    // `?direction=` only ever influences normal prototype mode; Review Mode
    // starts with no selected direction.
    _requestedDirection =
        _route.isReviewMode ? null : uri.queryParameters['direction'];
    final clientId =
        _route.isReviewMode ? reviewClientId! : (_route.clientId ?? kDefaultClientId);
    final loader = widget.loadRuntime ?? RuntimeLoader.loadClient;
    _runtime = loader(clientId);
  }

  @override
  void dispose() {
    _reviewController?.dispose();
    super.dispose();
  }

  /// Composition root: Review Mode storage is chosen here, never in the UI.
  ///
  /// A persisted state (when one exists) is restored; otherwise the controller
  /// keeps its initial state (round 1, no selected direction).
  ReviewController _controllerFor(PrototypeRuntime runtime) {
    final existing = _reviewController;
    if (existing != null) {
      return existing;
    }
    final controller = ReviewController(
      clientId: runtime.clientId,
      repository: MemoryReviewRepository(),
      runtime: runtime,
    );
    unawaited(controller.load());
    _reviewController = controller;
    return controller;
  }

  /// Composition root for C.4 feedback storage, chosen here and never in the UI.
  ReviewCoordinator _coordinatorFor(ReviewController controller) {
    final existing = _reviewCoordinator;
    if (existing != null) {
      return existing;
    }
    final coordinator = ReviewCoordinator(
      controller: controller,
      feedbackRepository: MemoryFeedbackRepository(),
      approvalRepository: MemoryApprovalRepository(),
      refinementBatchRepository: MemoryRefinementBatchRepository(),
    );
    _reviewCoordinator = coordinator;
    return coordinator;
  }

  /// Builds the automated-QA triage coordinator for [controller].
  ///
  /// QA findings are separate from `ReviewState`; the prototype composition root
  /// uses an in-memory repository, and promotion still flows through the
  /// validated [ReviewCoordinator] feedback seam.
  QaCoordinator _qaCoordinatorFor(ReviewController controller) {
    final existing = _qaCoordinator;
    if (existing != null && identical(_qaController, controller)) {
      return existing;
    }
    final coordinator = QaCoordinator(
      findings: MemoryQaFindingRepository(),
      review: _coordinatorFor(controller),
    );
    _qaController = controller;
    _qaCoordinator = coordinator;
    return coordinator;
  }

  ReviewController? _qaController;
  QaCoordinator? _qaCoordinator;

  @override
  Widget build(BuildContext context) {
    final routeError = _routeError;
    if (routeError != null) {
      return _shell(RuntimeErrorScreen(error: routeError));
    }

    return FutureBuilder<PrototypeRuntime>(
      future: _runtime,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _shell(const Scaffold(body: Center(child: CircularProgressIndicator())));
        }
        final error = snapshot.error;
        if (error != null) {
          return _shell(
            RuntimeErrorScreen(
              error: error is RuntimeException
                  ? error
                  : RuntimeException(
                      code: RuntimeException.invalidBundle,
                      message: error.toString(),
                    ),
            ),
          );
        }
        final runtime = snapshot.requireData;
        if (_route.isReviewMode && !_showPrototype) {
          final controller = _controllerFor(runtime);
          return _shell(
            ReviewShell(
              runtime: runtime,
              controller: controller,
              coordinator: _coordinatorFor(controller),
              actor: kLocalReviewer,
              qaCoordinator: _qaCoordinatorFor(controller),
              onOpenPrototype: () => setState(() => _showPrototype = true),
            ),
          );
        }
        final requested = _route.isReviewMode ? null : _requestedDirection;
        return PrototypeApp(
          runtime: runtime,
          requestedDirection: (requested == null || requested.isEmpty) ? null : requested,
        );
      },
    );
  }

  Widget _shell(Widget home) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Agency Prototype',
        theme: AgencyTheme.lightDefault(),
        home: home,
      );
}
