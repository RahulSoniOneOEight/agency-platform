import 'package:flutter/material.dart';

import '../runtime/prototype_runtime.dart';
import 'review_actor.dart';
import 'review_controller.dart';
import 'review_coordinator.dart';
import 'review_feedback_panel.dart';
import 'review_screen_registry.dart';
import 'review_state.dart';

/// Sentinel used so the optional direction dropdown always has a non-null value
/// while still modelling "no direction" as `null` in review state.
const String _noDirection = '__none__';

/// The Comments destination: the C.4 feedback panel plus the legacy comment
/// capture retained for C.1–C.3 persisted-state compatibility.
///
/// New review feedback flows through [ReviewCoordinator] and [FeedbackRecord];
/// the legacy [ReviewComment] form is preserved where it is not superseded and
/// still stores through [ReviewController]. Blank text is rejected at this UI
/// boundary (the controller is not called), a screen comment cannot be saved
/// without a governed screen selection, and IDs are generated as the smallest
/// unused `review-<n>` so repeated adds never collide.
class ReviewComments extends StatefulWidget {
  const ReviewComments({
    super.key,
    required this.runtime,
    required this.controller,
    required this.coordinator,
    required this.actor,
  });

  /// Marks the retained C.1–C.3 comment capture as legacy/back-compat.
  static const Key legacyCommentsLabelKey = Key('review-comments-legacy-label');

  static const Key generalTextFieldKey = Key('review-comments-general-text');
  static const Key generalDirectionFieldKey =
      Key('review-comments-general-direction');
  static const Key addGeneralButtonKey = Key('review-comments-add-general');
  static const Key screenFieldKey = Key('review-comments-screen');
  static const Key screenTextFieldKey = Key('review-comments-screen-text');
  static const Key screenDirectionFieldKey =
      Key('review-comments-screen-direction');
  static const Key addScreenButtonKey = Key('review-comments-add-screen');

  /// Smallest `review-<n>` (n >= 1) not already present in [comments].
  static String nextCommentId(Iterable<ReviewComment> comments) {
    final used = comments.map((comment) => comment.id).toSet();
    var candidate = 1;
    while (used.contains('review-$candidate')) {
      candidate++;
    }
    return 'review-$candidate';
  }

  final PrototypeRuntime runtime;
  final ReviewController controller;
  final ReviewCoordinator coordinator;
  final ReviewActor actor;

  @override
  State<ReviewComments> createState() => _ReviewCommentsState();
}

class _ReviewCommentsState extends State<ReviewComments> {
  final TextEditingController _generalText = TextEditingController();
  final TextEditingController _screenText = TextEditingController();

  String? _generalDirection;
  String? _screenId;
  String? _screenDirection;

  String? _generalError;
  String? _screenError;

  @override
  void dispose() {
    _generalText.dispose();
    _screenText.dispose();
    super.dispose();
  }

  Future<void> _addGeneral() async {
    final text = _generalText.text.trim();
    if (text.isEmpty) {
      setState(() => _generalError = 'Comment text is required.');
      return;
    }
    setState(() => _generalError = null);
    await widget.controller.addComment(
      ReviewComment(
        id: ReviewComments.nextCommentId(widget.controller.state.comments),
        scope: ReviewCommentScope.general,
        text: text,
        direction: _generalDirection,
      ),
    );
    if (!mounted) return;
    _generalText.clear();
    setState(() => _generalDirection = null);
  }

  Future<void> _addScreen() async {
    final screenId = _screenId;
    if (screenId == null) {
      setState(() => _screenError = 'Select a screen for a screen comment.');
      return;
    }
    final text = _screenText.text.trim();
    if (text.isEmpty) {
      setState(() => _screenError = 'Comment text is required.');
      return;
    }
    setState(() => _screenError = null);
    await widget.controller.addComment(
      ReviewComment(
        id: ReviewComments.nextCommentId(widget.controller.state.comments),
        scope: ReviewCommentScope.screen,
        text: text,
        screen: screenId,
        direction: _screenDirection,
      ),
    );
    if (!mounted) return;
    _screenText.clear();
    setState(() {
      _screenId = null;
      _screenDirection = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenIds = ReviewScreenRegistry.screenIdsFor(widget.runtime).toList()
      ..sort();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReviewFeedbackPanel(
            runtime: widget.runtime,
            controller: widget.controller,
            coordinator: widget.coordinator,
            actor: widget.actor,
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'Legacy comments (retained for C.1-C.3 back-compat)',
            key: ReviewComments.legacyCommentsLabelKey,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Superseded by the review feedback panel above.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Text('Review comments',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _SectionTitle('Add a general comment'),
          const SizedBox(height: 8),
          TextField(
            key: ReviewComments.generalTextFieldKey,
            controller: _generalText,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Comment',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          _directionField(
            key: ReviewComments.generalDirectionFieldKey,
            label: 'Direction (optional)',
            value: _generalDirection,
            onChanged: (value) => setState(() => _generalDirection = value),
          ),
          if (_generalError != null) ...[
            const SizedBox(height: 8),
            _ErrorText(_generalError!),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: ReviewComments.addGeneralButtonKey,
              onPressed: _addGeneral,
              child: const Text('Add general comment'),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          _SectionTitle('Add a screen comment'),
          const SizedBox(height: 8),
          DropdownButton<String>(
            key: ReviewComments.screenFieldKey,
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
            onChanged: (value) => setState(() => _screenId = value),
          ),
          const SizedBox(height: 12),
          TextField(
            key: ReviewComments.screenTextFieldKey,
            controller: _screenText,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Comment',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          _directionField(
            key: ReviewComments.screenDirectionFieldKey,
            label: 'Direction (optional)',
            value: _screenDirection,
            onChanged: (value) => setState(() => _screenDirection = value),
          ),
          if (_screenError != null) ...[
            const SizedBox(height: 8),
            _ErrorText(_screenError!),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: ReviewComments.addScreenButtonKey,
              onPressed: _addScreen,
              child: const Text('Add screen comment'),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) {
              final comments = widget.controller.state.comments;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Comment count: ${comments.length}'),
                  const SizedBox(height: 12),
                  if (comments.isEmpty)
                    const Text('No comments yet.')
                  else
                    for (final comment in comments)
                      ListTile(
                        key: ValueKey('review-comment-${comment.id}'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(comment.text),
                        subtitle: Text(_subtitle(comment)),
                      ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _directionField({
    required Key key,
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        DropdownButton<String>(
          key: key,
          value: value ?? _noDirection,
          isExpanded: true,
          items: [
            const DropdownMenuItem<String>(
              value: _noDirection,
              child: Text('No direction'),
            ),
            for (final id in widget.runtime.allowedDirections)
              DropdownMenuItem<String>(
                value: id,
                child: Text(id.toUpperCase()),
              ),
          ],
          onChanged: (selected) =>
              onChanged(selected == _noDirection ? null : selected),
        ),
      ],
    );
  }

  String _subtitle(ReviewComment comment) {
    if (comment.scope == ReviewCommentScope.screen) {
      return '${comment.screen} · ${comment.direction ?? 'all directions'}';
    }
    return comment.direction ?? 'general';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleSmall);
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}
