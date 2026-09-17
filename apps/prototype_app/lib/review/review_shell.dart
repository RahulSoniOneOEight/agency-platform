import 'package:flutter/material.dart';

import '../fixtures/fixture_repository.dart';
import '../qa/qa_coordinator.dart';
import '../qa/review_qa_panel.dart';
import '../runtime/prototype_runtime.dart';
import 'review_actor.dart';
import 'review_approval_panel.dart';
import 'review_comments.dart';
import 'review_controller.dart';
import 'review_coordinator.dart';
import 'review_direction_comparison.dart';
import 'review_overview.dart';
import 'review_screen_comparison.dart';
import 'review_selection.dart';

/// Width at or above which the review destinations are presented as a rail.
const double _wideBreakpoint = 900;

/// Responsive Review Mode shell.
///
/// It exposes the review destinations (Overview, Directions, Screens,
/// Selection, Comments, Approval, and — when a QA coordinator is supplied — the
/// automated QA triage destination) with a [NavigationRail] at wide widths and a
/// [NavigationBar] at compact widths. The destination index is local UI state;
/// all review decisions live in the injected [ReviewController], which is owned
/// by the composition root, so switching destinations never loses review state.
///
/// QA triage is deliberately a separate destination backed by [QaCoordinator]:
/// it never moves automated findings into `ReviewState`.
class ReviewShell extends StatefulWidget {
  const ReviewShell({
    super.key,
    required this.runtime,
    required this.controller,
    required this.coordinator,
    required this.actor,
    this.qaCoordinator,
    this.onOpenPrototype,
  });

  final PrototypeRuntime runtime;
  final ReviewController controller;
  final ReviewCoordinator coordinator;
  final ReviewActor actor;

  /// Optional automated-QA triage coordinator; when present a QA destination is
  /// offered. Its absence leaves the C.1–C.7 destinations unchanged.
  final QaCoordinator? qaCoordinator;

  /// Optional exit path back to normal prototype mode.
  final VoidCallback? onOpenPrototype;

  @override
  State<ReviewShell> createState() => _ReviewShellState();
}

class _ReviewShellState extends State<ReviewShell> {
  static const List<_ReviewDestination> _coreDestinations = [
    _ReviewDestination('Overview', Icons.dashboard_outlined, Icons.dashboard),
    _ReviewDestination('Directions', Icons.explore_outlined, Icons.explore),
    _ReviewDestination('Screens', Icons.layers_outlined, Icons.layers),
    _ReviewDestination(
        'Selection', Icons.check_circle_outline, Icons.check_circle),
    _ReviewDestination('Comments', Icons.comment_outlined, Icons.comment),
    _ReviewDestination('Approval', Icons.verified_outlined, Icons.verified),
  ];

  static const _ReviewDestination _qaDestination =
      _ReviewDestination('QA', Icons.bug_report_outlined, Icons.bug_report);

  late final FixtureRepository _fixtures;

  int _destinationIndex = 0;

  List<_ReviewDestination> get _destinations => [
        ..._coreDestinations,
        if (widget.qaCoordinator != null) _qaDestination,
      ];

  @override
  void initState() {
    super.initState();
    _fixtures = FixtureRepository.fromRuntime(widget.runtime);
  }

  @override
  Widget build(BuildContext context) {
    final destinations = _destinations;
    final index = _destinationIndex.clamp(0, destinations.length - 1);
    return Scaffold(
      appBar: AppBar(
        title: Text('Review Mode · ${widget.runtime.clientId}'),
        actions: [
          if (widget.onOpenPrototype != null)
            TextButton(
              onPressed: widget.onOpenPrototype,
              child: const Text('Prototype'),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final content = _buildDestination(index);
          if (constraints.maxWidth >= _wideBreakpoint) {
            return Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: (value) =>
                      setState(() => _destinationIndex = value),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final destination in destinations)
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
                selectedIndex: index,
                onDestinationSelected: (value) =>
                    setState(() => _destinationIndex = value),
                destinations: [
                  for (final destination in destinations)
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
    if (index == _coreDestinations.length && widget.qaCoordinator != null) {
      return ReviewQaPanel(
        runtime: widget.runtime,
        coordinator: widget.qaCoordinator!,
        actor: widget.actor,
      );
    }
    return switch (index) {
      0 =>
        ReviewOverview(runtime: widget.runtime, controller: widget.controller),
      1 => ReviewDirectionComparison(
          runtime: widget.runtime, controller: widget.controller),
      2 => ReviewScreenComparison(
          runtime: widget.runtime,
          fixtures: _fixtures,
          controller: widget.controller),
      3 => ReviewSelection(
          runtime: widget.runtime,
          controller: widget.controller,
          fixtures: _fixtures,
        ),
      4 => ReviewComments(
          runtime: widget.runtime,
          controller: widget.controller,
          coordinator: widget.coordinator,
          actor: widget.actor,
        ),
      _ => ReviewApprovalPanel(
          runtime: widget.runtime,
          controller: widget.controller,
          coordinator: widget.coordinator,
          actor: widget.actor,
        ),
    };
  }
}

class _ReviewDestination {
  const _ReviewDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
