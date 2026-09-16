import 'package:flutter/material.dart';

import '../fixtures/fixture_repository.dart';
import '../runtime/prototype_runtime.dart';
import 'review_controller.dart';
import 'review_directions.dart';
import 'review_overview.dart';
import 'review_screens.dart';
import 'review_state.dart';

/// Width at or above which the review destinations are presented as a rail.
const double _wideBreakpoint = 900;

/// Responsive Review Mode shell.
///
/// It exposes the five review destinations (Overview, Directions, Screens,
/// Selection, Comments) with a [NavigationRail] at wide widths and a
/// [NavigationBar] at compact widths. The destination index is local UI state;
/// all review decisions live in the injected [ReviewController], which is owned
/// by the composition root, so switching destinations never loses review state.
class ReviewShell extends StatefulWidget {
  const ReviewShell({
    super.key,
    required this.runtime,
    required this.controller,
  });

  final PrototypeRuntime runtime;
  final ReviewController controller;

  @override
  State<ReviewShell> createState() => _ReviewShellState();
}

class _ReviewShellState extends State<ReviewShell> {
  static const List<_ReviewDestination> _destinations = [
    _ReviewDestination('Overview', Icons.dashboard_outlined, Icons.dashboard),
    _ReviewDestination('Directions', Icons.explore_outlined, Icons.explore),
    _ReviewDestination('Screens', Icons.layers_outlined, Icons.layers),
    _ReviewDestination('Selection', Icons.check_circle_outline, Icons.check_circle),
    _ReviewDestination('Comments', Icons.comment_outlined, Icons.comment),
  ];

  late final FixtureRepository _fixtures;

  int _destinationIndex = 0;

  @override
  void initState() {
    super.initState();
    _fixtures = FixtureRepository.fromRuntime(widget.runtime);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Review Mode · ${widget.runtime.clientId}')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final content = _buildDestination(_destinationIndex);
          if (constraints.maxWidth >= _wideBreakpoint) {
            return Row(
              children: [
                NavigationRail(
                  selectedIndex: _destinationIndex,
                  onDestinationSelected: (value) =>
                      setState(() => _destinationIndex = value),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final destination in _destinations)
                      NavigationRailDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.selectedIcon),
                        label: Text(destination.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            );
          }
          return Column(
            children: [
              Expanded(child: content),
              NavigationBar(
                selectedIndex: _destinationIndex,
                onDestinationSelected: (value) =>
                    setState(() => _destinationIndex = value),
                destinations: [
                  for (final destination in _destinations)
                    NavigationDestination(
                      icon: Icon(destination.icon),
                      selectedIcon: Icon(destination.selectedIcon),
                      label: destination.label,
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDestination(int index) {
    return switch (index) {
      0 => ReviewOverview(runtime: widget.runtime, controller: widget.controller),
      1 => ReviewDirections(runtime: widget.runtime, controller: widget.controller),
      2 => ReviewScreens(runtime: widget.runtime, fixtures: _fixtures),
      3 => _SelectionSummary(controller: widget.controller),
      _ => _CommentsSummary(controller: widget.controller),
    };
  }
}

class _ReviewDestination {
  const _ReviewDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Real read-only selection summary from the controller state.
///
/// The interactive overall selection and per-screen mix editors are added by the
/// next task; this destination is a genuine summary rather than a placeholder.
class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({required this.controller});

  final ReviewController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        final selections = state.screenSelections.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Overall selection', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text('Overall direction: ${state.selectedDirection ?? 'Not selected'}'),
            const SizedBox(height: 8),
            Text('Mixed screens: ${selections.length}'),
            const SizedBox(height: 12),
            if (selections.isEmpty)
              const Text('No screens mixed yet.')
            else
              for (final entry in selections) Text('${entry.key} → ${entry.value}'),
          ],
        );
      },
    );
  }
}

/// Real read-only comments summary from the controller state.
///
/// The comment capture/editor is added by the comments task; this destination is
/// a genuine list/count rather than a placeholder.
class _CommentsSummary extends StatelessWidget {
  const _CommentsSummary({required this.controller});

  final ReviewController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final comments = controller.state.comments;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Review comments', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text('Comment count: ${comments.length}'),
            const SizedBox(height: 12),
            if (comments.isEmpty)
              const Text('No comments yet.')
            else
              for (final comment in comments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(comment.text),
                  subtitle: Text(
                    comment.scope == ReviewCommentScope.screen
                        ? '${comment.screen} · ${comment.direction ?? 'all directions'}'
                        : comment.direction ?? 'general',
                  ),
                ),
          ],
        );
      },
    );
  }
}
