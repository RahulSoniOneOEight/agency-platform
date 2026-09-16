import 'package:flutter/material.dart';

import '../runtime/prototype_runtime.dart';
import 'memory_review_repository.dart';
import 'review_controller.dart';
import 'review_state.dart';

/// Minimal, genuinely usable Review Mode shell.
///
/// It renders the review client identity, review round/status, and the current
/// overall direction from [ReviewController] state. The full five-destination
/// navigation (Overview, Directions, Screens, Selection, Comments) is added by
/// the next review-shell task; this shell intentionally keeps the surface small
/// while remaining real rather than a placeholder.
class ReviewShell extends StatefulWidget {
  const ReviewShell({super.key, required this.runtime, this.controller});

  final PrototypeRuntime runtime;

  /// Tests may inject a controller; otherwise an in-memory one is created.
  final ReviewController? controller;

  @override
  State<ReviewShell> createState() => _ReviewShellState();
}

class _ReviewShellState extends State<ReviewShell> {
  ReviewController? _ownedController;

  ReviewController get _controller => widget.controller ?? _ownedController!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      final controller = ReviewController(
        clientId: widget.runtime.clientId,
        repository: MemoryReviewRepository(),
      );
      _ownedController = controller;
      controller.load();
    }
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review Mode')),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final state = _controller.state;
          final theme = Theme.of(context);
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Client: ${widget.runtime.clientId}', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Review round: ${state.reviewRound}'),
              const SizedBox(height: 8),
              Text('Status: ${reviewStatusToWire(state.status)}'),
              const SizedBox(height: 8),
              Text('Overall direction: ${state.selectedDirection ?? 'Not selected'}'),
              const SizedBox(height: 24),
              Text(
                'Full review navigation (Overview, Directions, Screens, '
                'Selection, Comments) arrives in the next task.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}
