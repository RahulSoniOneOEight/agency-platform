import 'package:flutter/material.dart';

import '../runtime/prototype_runtime.dart';
import 'approval_snapshot.dart';
import 'feedback_record.dart';
import 'review_actor.dart';
import 'review_controller.dart';
import 'review_coordinator.dart';
import 'review_domain_error.dart';

/// Reviewer/approver-facing C.5 approval surface.
///
/// Shows the exact approval eligibility gates, captures reviewer and approver
/// identities separately (the same person may occupy both), creates approvals
/// only through [ReviewCoordinator], and renders existing approval versions and
/// carried-forward non-blocking feedback read-only. Visual evidence is shown as
/// context only; the panel never grants a provider lifecycle authority.
class ReviewApprovalPanel extends StatefulWidget {
  const ReviewApprovalPanel({
    super.key,
    required this.runtime,
    required this.controller,
    required this.coordinator,
    required this.actor,
  });

  static const Key reviewerIdFieldKey = Key('review-approval-reviewer-id');
  static const Key reviewerNameFieldKey = Key('review-approval-reviewer-name');
  static const Key approverIdFieldKey = Key('review-approval-approver-id');
  static const Key approverNameFieldKey = Key('review-approval-approver-name');
  static const Key commitShaFieldKey = Key('review-approval-commit-sha');
  static const Key createButtonKey = Key('review-approval-create');
  static const Key eligibilityBannerKey = Key('review-approval-eligible');
  static const Key blockersKey = Key('review-approval-blockers');
  static const Key errorKey = Key('review-approval-error');
  static const Key unresolvedNonBlockingKey =
      Key('review-approval-unresolved-non-blocking');
  static const Key visualEvidenceKey = Key('review-approval-visual-evidence');

  static Key versionTileKey(int version) =>
      ValueKey<String>('review-approval-v$version');

  static Key visualEvidenceItemKey(String feedbackId) =>
      ValueKey<String>('review-approval-visual-$feedbackId');

  final PrototypeRuntime runtime;
  final ReviewController controller;
  final ReviewCoordinator coordinator;
  final ReviewActor actor;

  @override
  State<ReviewApprovalPanel> createState() => _ReviewApprovalPanelState();
}

class _ReviewApprovalPanelState extends State<ReviewApprovalPanel> {
  late final TextEditingController _reviewerId;
  late final TextEditingController _reviewerName;
  final TextEditingController _approverId = TextEditingController();
  final TextEditingController _approverName = TextEditingController();
  final TextEditingController _commitSha = TextEditingController();

  String? _error;
  List<String> _reasons = const <String>[];
  List<ApprovalSnapshot> _approvals = const <ApprovalSnapshot>[];
  List<FeedbackRecord> _feedback = const <FeedbackRecord>[];

  bool get _isReviewer => widget.actor.isReviewer;

  @override
  void initState() {
    super.initState();
    _reviewerId = TextEditingController(text: widget.actor.id);
    _reviewerName = TextEditingController(text: widget.actor.name);
    widget.controller.addListener(_onControllerChanged);
    _refresh();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _reviewerId.dispose();
    _reviewerName.dispose();
    _approverId.dispose();
    _approverName.dispose();
    _commitSha.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    _refresh();
  }

  Future<void> _refresh() async {
    final reasons = await widget.coordinator.approvalBlockingReasons();
    final approvals = await widget.coordinator.listApprovals();
    final feedback = await widget.coordinator.allFeedback();
    if (!mounted) return;
    setState(() {
      _reasons = reasons;
      _approvals = approvals;
      _feedback = feedback;
    });
  }

  Future<void> _create() async {
    final reviewerId = _reviewerId.text.trim();
    final reviewerName = _reviewerName.text.trim();
    final approverId = _approverId.text.trim();
    final approverName = _approverName.text.trim();
    final commitSha = _commitSha.text.trim();
    if (reviewerId.isEmpty ||
        reviewerName.isEmpty ||
        approverId.isEmpty ||
        approverName.isEmpty ||
        commitSha.isEmpty) {
      setState(() => _error = 'Reviewer, approver and commit SHA are required.');
      return;
    }
    setState(() => _error = null);
    try {
      await widget.coordinator.createApproval(
        reviewer: ReviewActor(
          id: reviewerId,
          name: reviewerName,
          role: ReviewRole.reviewer,
        ),
        approver: ReviewActor(
          id: approverId,
          name: approverName,
          role: ReviewRole.approver,
        ),
        sourceCommitSha: commitSha,
      );
      if (!mounted) return;
      _approverId.clear();
      _approverName.clear();
      await _refresh();
    } on ReviewDomainError catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Approval', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _buildEligibility(context),
          if (_isReviewer) ...[
            const SizedBox(height: 24),
            _buildCreateForm(context),
          ],
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          _buildApprovalHistory(context),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          _buildUnresolvedNonBlocking(context),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          _buildVisualEvidence(context),
        ],
      ),
    );
  }

  Widget _buildEligibility(BuildContext context) {
    if (_reasons.isEmpty) {
      return const Text(
        'Eligible for approval',
        key: ReviewApprovalPanel.eligibilityBannerKey,
      );
    }
    return Column(
      key: ReviewApprovalPanel.blockersKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Approval blocked',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        for (final reason in _reasons) Text('• $reason'),
      ],
    );
  }

  Widget _buildCreateForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Create approval', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          key: ReviewApprovalPanel.reviewerIdFieldKey,
          controller: _reviewerId,
          decoration: const InputDecoration(
            labelText: 'Reviewer id',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: ReviewApprovalPanel.reviewerNameFieldKey,
          controller: _reviewerName,
          decoration: const InputDecoration(
            labelText: 'Reviewer name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: ReviewApprovalPanel.approverIdFieldKey,
          controller: _approverId,
          decoration: const InputDecoration(
            labelText: 'Approver id (same person allowed)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: ReviewApprovalPanel.approverNameFieldKey,
          controller: _approverName,
          decoration: const InputDecoration(
            labelText: 'Approver name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: ReviewApprovalPanel.commitShaFieldKey,
          controller: _commitSha,
          decoration: const InputDecoration(
            labelText: 'Source commit SHA',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            key: ReviewApprovalPanel.errorKey,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: ReviewApprovalPanel.createButtonKey,
            onPressed: _reasons.isEmpty ? _create : null,
            child: const Text('Create approval'),
          ),
        ),
      ],
    );
  }

  Widget _buildApprovalHistory(BuildContext context) {
    if (_approvals.isEmpty) {
      return const Text('No approvals yet.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Approval history', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final snapshot in _approvals) _buildApprovalTile(context, snapshot),
      ],
    );
  }

  Widget _buildApprovalTile(BuildContext context, ApprovalSnapshot snapshot) {
    final theme = Theme.of(context);
    return Container(
      key: ReviewApprovalPanel.versionTileKey(snapshot.version),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Approval v${snapshot.version}'),
          const SizedBox(height: 4),
          Text(
            'round ${snapshot.reviewRound} · reviewed_by '
            '${snapshot.reviewedBy.id} (${snapshot.reviewedBy.name}) · '
            'approved_by ${snapshot.approvedBy.id} '
            '(${snapshot.approvedBy.name})',
            style: theme.textTheme.bodySmall,
          ),
          Text(
            'commit ${snapshot.sourceCommitSha} · '
            '${snapshot.reviewStateHash}',
            style: theme.textTheme.bodySmall,
          ),
          if (snapshot.supersedes != null)
            Text(
              'supersedes v${snapshot.supersedes}',
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _buildUnresolvedNonBlocking(BuildContext context) {
    final unresolved = <FeedbackRecord>[
      for (final record in _feedback)
        if (!record.blocking && record.status != FeedbackStatus.resolved) record,
    ];
    return Column(
      key: ReviewApprovalPanel.unresolvedNonBlockingKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Unresolved non-blocking feedback carried forward',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        if (unresolved.isEmpty)
          const Text('None')
        else
          for (final record in unresolved)
            Text('${record.id}: ${record.text}'),
      ],
    );
  }

  Widget _buildVisualEvidence(BuildContext context) {
    final withEvidence = <FeedbackRecord>[
      for (final record in _feedback)
        if (record.visualAttachment != null) record,
    ];
    return Column(
      key: ReviewApprovalPanel.visualEvidenceKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Visual evidence', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        if (withEvidence.isEmpty)
          const Text('No visual evidence.')
        else
          for (final record in withEvidence)
            Text(
              '${record.visualAttachment!.screenshotRef} · '
              '${record.visualAttachment!.providerName} · '
              '${record.visualAttachment!.screenId}'
              '${record.visualAttachment!.sectionId == null ? '' : ' · ${record.visualAttachment!.sectionId}'}',
              key: ReviewApprovalPanel.visualEvidenceItemKey(record.id),
              style: Theme.of(context).textTheme.bodySmall,
            ),
      ],
    );
  }
}
