import 'package:flutter/material.dart';

import '../review/feedback_record.dart';
import '../review/review_actor.dart';
import '../runtime/prototype_runtime.dart';
import 'qa_coordinator.dart';
import 'qa_finding.dart';

/// Reviewer-facing triage surface for automated QA findings.
///
/// It exposes exactly the QA triage operations — triage, dismiss, accept risk,
/// and explicit **promote** into human review — and nothing else. Resolving
/// feedback, changing blocking, approving, and updating baselines are
/// deliberately absent: those remain `ReviewCoordinator` / baseline-governance
/// authority, reachable only through their own governed flows.
class ReviewQaPanel extends StatefulWidget {
  const ReviewQaPanel({
    super.key,
    required this.runtime,
    required this.coordinator,
    required this.actor,
    this.onPromoted,
  });

  final PrototypeRuntime runtime;
  final QaCoordinator coordinator;
  final ReviewActor actor;

  /// Invoked after a successful promotion so the host can surface the record.
  final void Function(FeedbackRecord record)? onPromoted;

  @override
  State<ReviewQaPanel> createState() => _ReviewQaPanelState();
}

class _ReviewQaPanelState extends State<ReviewQaPanel> {
  late Future<List<QaFinding>> _findings;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _findings = widget.coordinator.allFindings();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    }
    if (mounted) {
      setState(_refresh);
    }
  }

  Future<void> _triage(QaFinding finding) => _run(() async {
        await widget.coordinator.triageFinding(
          findingId: finding.id,
          actor: widget.actor,
        );
      });

  Future<void> _promote(QaFinding finding) => _run(() async {
        final record = await widget.coordinator.promoteFinding(
          findingId: finding.id,
          actor: widget.actor,
        );
        widget.onPromoted?.call(record);
      });

  Future<void> _disposition(QaFinding finding, {required bool acceptRisk}) async {
    final reason = await _askReason(
      acceptRisk ? 'Accept risk' : 'Dismiss finding',
    );
    if (reason == null || reason.trim().isEmpty) {
      return;
    }
    await _run(() async {
      if (acceptRisk) {
        await widget.coordinator.acceptRiskFinding(
          findingId: finding.id,
          actor: widget.actor,
          reason: reason,
        );
      } else {
        await widget.coordinator.dismissFinding(
          findingId: finding.id,
          actor: widget.actor,
          reason: reason,
        );
      }
    });
  }

  Future<String?> _askReason(String title) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<QaFinding>>(
      future: _findings,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final findings = snapshot.data ?? const <QaFinding>[];
        if (findings.isEmpty) {
          return const Center(child: Text('No QA findings.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: findings.length,
          itemBuilder: (context, index) => _FindingCard(
            finding: findings[index],
            onTriage: _triage,
            onPromote: _promote,
            onDismiss: (finding) => _disposition(finding, acceptRisk: false),
            onAcceptRisk: (finding) => _disposition(finding, acceptRisk: true),
          ),
        );
      },
    );
  }
}

class _FindingCard extends StatelessWidget {
  const _FindingCard({
    required this.finding,
    required this.onTriage,
    required this.onPromote,
    required this.onDismiss,
    required this.onAcceptRisk,
  });

  final QaFinding finding;
  final void Function(QaFinding) onTriage;
  final void Function(QaFinding) onPromote;
  final void Function(QaFinding) onDismiss;
  final void Function(QaFinding) onAcceptRisk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(finding.summary, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '${qaSeverityToWire(finding.severity)} · ${finding.category} · '
              '${qaFindingStatusToWire(finding.status)} · '
              '${qaRuleSourceToWire(finding.ruleSource)}:${finding.ruleRef}',
              style: theme.textTheme.bodySmall,
            ),
            if (finding.isNoLongerReproducible)
              Text('No longer reproducible', style: theme.textTheme.bodySmall),
            if (finding.isPromoted)
              Text(
                'Promoted → ${finding.feedbackId}',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (finding.status == QaFindingStatus.detected)
                  TextButton(
                    onPressed: () => onTriage(finding),
                    child: const Text('Triage'),
                  ),
                if (finding.canPromote) ...[
                  FilledButton(
                    onPressed: () => onPromote(finding),
                    child: const Text('Promote'),
                  ),
                  TextButton(
                    onPressed: () => onDismiss(finding),
                    child: const Text('Dismiss'),
                  ),
                  TextButton(
                    onPressed: () => onAcceptRisk(finding),
                    child: const Text('Accept risk'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
