import 'package:flutter/material.dart';

import '../runtime/prototype_runtime.dart';
import 'feedback_record.dart';
import 'review_actor.dart';
import 'review_controller.dart';
import 'review_coordinator.dart';
import 'review_domain_error.dart';
import 'review_screen_registry.dart';
import 'review_section_registry.dart';

/// Reviewer-facing C.4 feedback surface.
///
/// Every mutation goes through [ReviewCoordinator]; the panel never mutates raw
/// maps or feedback records directly. Reviewer-only controls (create, resolve,
/// reopen, blocking classification, round closure) are gated by [actor] role,
/// and the explicit `Close review round` action is enabled only when every
/// blocking item is resolved. Feedback from prior rounds stays visible.
class ReviewFeedbackPanel extends StatefulWidget {
  const ReviewFeedbackPanel({
    super.key,
    required this.runtime,
    required this.controller,
    required this.coordinator,
    required this.actor,
  });

  static const Key textFieldKey = Key('review-feedback-text');
  static const Key scopeFieldKey = Key('review-feedback-scope');
  static const Key screenFieldKey = Key('review-feedback-screen');
  static const Key sectionFieldKey = Key('review-feedback-section');
  static const Key directionFieldKey = Key('review-feedback-direction');
  static const Key blockingFieldKey = Key('review-feedback-blocking');
  static const Key createButtonKey = Key('review-feedback-create');
  static const Key closeRoundButtonKey = Key('review-feedback-close-round');
  static const Key eligibilityBannerKey = Key('review-feedback-eligible');
  static const Key errorKey = Key('review-feedback-error');

  static Key roundSectionKey(int round) =>
      ValueKey<String>('review-feedback-round-$round');

  static Key tileKey(String id) => ValueKey<String>('review-feedback-$id');

  static Key statusChipKey(String id) =>
      ValueKey<String>('review-feedback-status-$id');

  static Key resolveButtonKey(String id) =>
      ValueKey<String>('review-feedback-resolve-$id');

  static Key reopenButtonKey(String id) =>
      ValueKey<String>('review-feedback-reopen-$id');

  static Key blockingToggleKey(String id) =>
      ValueKey<String>('review-feedback-blocking-$id');

  static const List<FeedbackScope> scopeOptions = <FeedbackScope>[
    FeedbackScope.general,
    FeedbackScope.screen,
    FeedbackScope.section,
    FeedbackScope.decision,
  ];

  final PrototypeRuntime runtime;
  final ReviewController controller;
  final ReviewCoordinator coordinator;
  final ReviewActor actor;

  @override
  State<ReviewFeedbackPanel> createState() => _ReviewFeedbackPanelState();
}

class _ReviewFeedbackPanelState extends State<ReviewFeedbackPanel> {
  final TextEditingController _text = TextEditingController();

  FeedbackScope _scope = FeedbackScope.general;
  String? _screenId;
  String? _sectionId;
  String? _direction;
  bool _blocking = true;

  String? _formError;
  String? _actionError;
  List<FeedbackRecord> _records = const <FeedbackRecord>[];
  bool _eligible = true;

  bool get _isReviewer => widget.actor.isReviewer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _refresh();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _text.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    _refresh();
  }

  Future<void> _refresh() async {
    final records = await widget.coordinator.allFeedback();
    final eligible = await widget.coordinator.isEligibleToCloseRound();
    if (!mounted) return;
    setState(() {
      _records = records;
      _eligible = eligible;
    });
  }

  FeedbackTarget? _targetForScope() {
    switch (_scope) {
      case FeedbackScope.general:
        return const FeedbackTarget();
      case FeedbackScope.screen:
        final screen = _screenId;
        return screen == null ? null : FeedbackTarget(screen: screen);
      case FeedbackScope.section:
        final screen = _screenId;
        final section = _sectionId;
        if (screen == null || section == null) return null;
        return FeedbackTarget(screen: screen, section: section);
      case FeedbackScope.decision:
        final direction = _direction;
        return direction == null ? null : FeedbackTarget(direction: direction);
      case FeedbackScope.visualAnnotation:
        return const FeedbackTarget();
    }
  }

  String _nextFeedbackId() {
    final used = _records.map((record) => record.id).toSet();
    var candidate = 1;
    while (used.contains('feedback-$candidate')) {
      candidate++;
    }
    return 'feedback-$candidate';
  }

  Future<void> _create() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _formError = 'Feedback text is required.');
      return;
    }
    final target = _targetForScope();
    if (target == null) {
      setState(() => _formError = 'Select a target for this scope.');
      return;
    }
    setState(() {
      _formError = null;
      _actionError = null;
    });
    try {
      await widget.coordinator.createFeedback(
        actor: widget.actor,
        id: _nextFeedbackId(),
        scope: _scope,
        text: text,
        target: target,
        blocking: _blocking,
      );
      if (!mounted) return;
      _text.clear();
      setState(() {
        _blocking = true;
        _screenId = null;
        _sectionId = null;
        _direction = null;
      });
      await _refresh();
    } on ReviewDomainError catch (error) {
      if (!mounted) return;
      setState(() => _formError = error.message);
    }
  }

  Future<void> _resolve(String feedbackId) async {
    await _run(
      () => widget.coordinator.resolveFeedback(
        actor: widget.actor,
        feedbackId: feedbackId,
      ),
    );
  }

  Future<void> _reopen(String feedbackId) async {
    await _run(
      () => widget.coordinator.reopenFeedback(
        actor: widget.actor,
        feedbackId: feedbackId,
      ),
    );
  }

  Future<void> _toggleBlocking(FeedbackRecord record) async {
    await _run(
      () => widget.coordinator.setBlocking(
        actor: widget.actor,
        feedbackId: record.id,
        blocking: !record.blocking,
      ),
    );
  }

  Future<void> _closeRound() async {
    await _run(() => widget.coordinator.closeCurrentRound(actor: widget.actor));
  }

  Future<void> _run(Future<void> Function() operation) async {
    setState(() => _actionError = null);
    try {
      await operation();
      if (!mounted) return;
      await _refresh();
    } on ReviewDomainError catch (error) {
      if (!mounted) return;
      setState(() => _actionError = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Review feedback', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        if (_isReviewer) _buildCreateForm(context),
        if (_isReviewer) const SizedBox(height: 24),
        ..._buildRoundSections(context),
        if (_isReviewer) ...[
          const Divider(),
          const SizedBox(height: 12),
          _buildCloseSection(context),
        ],
        if (_actionError != null) ...[
          const SizedBox(height: 12),
          _ErrorText(_actionError!),
        ],
      ],
    );
  }

  Widget _buildCreateForm(BuildContext context) {
    final screenIds = ReviewScreenRegistry.screenIdsFor(widget.runtime).toList()
      ..sort();
    final sections = _screenId == null
        ? const <ReviewSectionDefinition>[]
        : ReviewSectionRegistry.sectionsForScreen(_screenId!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Add feedback', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        DropdownButton<FeedbackScope>(
          key: ReviewFeedbackPanel.scopeFieldKey,
          value: _scope,
          isExpanded: true,
          items: [
            for (final scope in ReviewFeedbackPanel.scopeOptions)
              DropdownMenuItem<FeedbackScope>(
                value: scope,
                child: Text(feedbackScopeToWire(scope)),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _scope = value;
              _sectionId = null;
            });
          },
        ),
        if (_scope == FeedbackScope.screen || _scope == FeedbackScope.section) ...[
          const SizedBox(height: 12),
          DropdownButton<String>(
            key: ReviewFeedbackPanel.screenFieldKey,
            value: _screenId,
            isExpanded: true,
            hint: const Text('Select screen'),
            items: [
              for (final id in screenIds)
                DropdownMenuItem<String>(
                  value: id,
                  child: Text(ReviewScreenRegistry.labelFor(id)),
                ),
            ],
            onChanged: (value) => setState(() {
              _screenId = value;
              _sectionId = null;
            }),
          ),
        ],
        if (_scope == FeedbackScope.section) ...[
          const SizedBox(height: 12),
          DropdownButton<String>(
            key: ReviewFeedbackPanel.sectionFieldKey,
            value: _sectionId,
            isExpanded: true,
            hint: const Text('Select section'),
            items: [
              for (final definition in sections)
                DropdownMenuItem<String>(
                  value: definition.id,
                  child: Text(definition.label),
                ),
            ],
            onChanged: (value) => setState(() => _sectionId = value),
          ),
        ],
        if (_scope == FeedbackScope.decision) ...[
          const SizedBox(height: 12),
          DropdownButton<String>(
            key: ReviewFeedbackPanel.directionFieldKey,
            value: _direction,
            isExpanded: true,
            hint: const Text('Select direction'),
            items: [
              for (final id in widget.runtime.allowedDirections)
                DropdownMenuItem<String>(
                  value: id,
                  child: Text(id.toUpperCase()),
                ),
            ],
            onChanged: (value) => setState(() => _direction = value),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          key: ReviewFeedbackPanel.textFieldKey,
          controller: _text,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Feedback',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: ReviewFeedbackPanel.blockingFieldKey,
          contentPadding: EdgeInsets.zero,
          value: _blocking,
          title: const Text('Blocking'),
          onChanged: (value) => setState(() => _blocking = value),
        ),
        if (_formError != null) ...[
          const SizedBox(height: 4),
          _ErrorText(_formError!, key: ReviewFeedbackPanel.errorKey),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: ReviewFeedbackPanel.createButtonKey,
            onPressed: _create,
            child: const Text('Add feedback'),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildRoundSections(BuildContext context) {
    if (_records.isEmpty) {
      return [const Text('No feedback yet.')];
    }
    final rounds = _records.map((record) => record.createdRound).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final currentRound = widget.controller.state.reviewRound;
    final widgets = <Widget>[];
    for (final round in rounds) {
      widgets.add(
        Padding(
          key: ReviewFeedbackPanel.roundSectionKey(round),
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            round == currentRound ? 'Round $round (current)' : 'Round $round',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      );
      for (final record in _records.where((r) => r.createdRound == round)) {
        widgets.add(_buildTile(context, record));
      }
    }
    return widgets;
  }

  Widget _buildTile(BuildContext context, FeedbackRecord record) {
    final theme = Theme.of(context);
    return Container(
      key: ReviewFeedbackPanel.tileKey(record.id),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(record.text),
          const SizedBox(height: 4),
          Text(
            '${feedbackScopeToWire(record.scope)} · ${_targetLabel(record)} · '
            'round ${record.createdRound}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                key: ReviewFeedbackPanel.statusChipKey(record.id),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(feedbackStatusToWire(record.status)),
              ),
              Text(record.blocking ? 'Blocking' : 'Non-blocking'),
              if (_isReviewer) ...[
                if (record.status == FeedbackStatus.addressed)
                  TextButton(
                    key: ReviewFeedbackPanel.resolveButtonKey(record.id),
                    onPressed: () => _resolve(record.id),
                    child: const Text('Resolve'),
                  ),
                if (record.status == FeedbackStatus.resolved)
                  TextButton(
                    key: ReviewFeedbackPanel.reopenButtonKey(record.id),
                    onPressed: () => _reopen(record.id),
                    child: const Text('Reopen'),
                  ),
                Switch(
                  key: ReviewFeedbackPanel.blockingToggleKey(record.id),
                  value: record.blocking,
                  onChanged: (_) => _toggleBlocking(record),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCloseSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_eligible)
          const Text(
            'Eligible to close round',
            key: ReviewFeedbackPanel.eligibilityBannerKey,
          ),
        const SizedBox(height: 8),
        FilledButton(
          key: ReviewFeedbackPanel.closeRoundButtonKey,
          onPressed: _eligible ? _closeRound : null,
          child: const Text('Close review round'),
        ),
      ],
    );
  }

  String _targetLabel(FeedbackRecord record) {
    final parts = <String>[
      if (record.target.screen != null) record.target.screen!,
      if (record.target.section != null) record.target.section!,
      if (record.target.direction != null) record.target.direction!,
    ];
    return parts.isEmpty ? 'no target' : parts.join(' · ');
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}
