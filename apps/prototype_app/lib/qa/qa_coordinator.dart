/// QA orchestration: intake, triage, deduplication, reviewer promotion, re-check.
///
/// [QaCoordinator] is a **thin** orchestration layer. It owns the automated QA
/// lifecycle ([QaFinding]) and the explicit, idempotent hand-off into human
/// review, but it never replaces `ReviewCoordinator`:
///
/// - feedback creation and every feedback lifecycle transition are delegated to
///   the existing validated `ReviewCoordinator.createFeedback` seam;
/// - `ReviewState`, approval snapshots, refinement batches, and runtime bundles
///   are never mutated here;
/// - Visual AI can never reach this class to approve, resolve, or block anything.
///
/// Promotion is create-first with idempotency (ledger RD5): an in-flight guard
/// plus a search for an existing record with the same `originQaFindingId` make
/// one QA finding produce exactly one feedback record, even after a crash or
/// under concurrent calls.
library;

import '../review/feedback_record.dart';
import '../review/review_actor.dart';
import '../review/review_coordinator.dart';
import '../review/review_domain_error.dart';
import 'memory_qa_run_repository.dart';
import 'qa_domain_error.dart';
import 'qa_finding.dart';
import 'qa_finding_repository.dart';
import 'qa_run.dart';
import 'qa_run_repository.dart';

final class QaCoordinator {
  QaCoordinator({
    required QaFindingRepository findings,
    required ReviewCoordinator review,
    QaRunRepository? runs,
    DateTime Function()? clock,
  })  : _findings = findings,
        _review = review,
        _runs = runs ?? MemoryQaRunRepository(),
        _clock = clock ?? (() => DateTime.now().toUtc());

  final QaFindingRepository _findings;
  final ReviewCoordinator _review;
  final QaRunRepository _runs;
  final DateTime Function() _clock;

  /// In-flight promotions, keyed by finding id, so concurrent calls share one
  /// transaction instead of racing to create two feedback records.
  final Map<String, Future<FeedbackRecord>> _inFlight = {};

  String get clientId => _review.clientId;

  /// All QA findings for this client, in deterministic id order.
  Future<List<QaFinding>> allFindings() => _findings.list(clientId);

  /// Loads a single QA finding, or `null` when it does not exist.
  Future<QaFinding?> loadFinding(String findingId) =>
      _findings.load(clientId, findingId);

  /// Records an automated finding, deduplicating against the active finding for
  /// the same issue.
  ///
  /// A rediscovery links its evidence to the existing `detected`/`triaged`/
  /// `promoted` finding (and records a recurrence when the finding had been
  /// marked no longer reproducible). A rediscovery of a finding the reviewer
  /// dismissed or accepted as risk creates a fresh finding so a disposition is
  /// never silently reused.
  Future<QaFinding> recordFinding(QaFinding candidate) async {
    if (candidate.clientId != clientId) {
      throw InvalidQaFinding(
        'finding belongs to client ${candidate.clientId}, not $clientId',
      );
    }
    final existing = await _activeFindingFor(candidate.dedupeKey);
    if (existing == null) {
      await _findings.create(clientId, candidate);
      return candidate;
    }
    final evidence = candidate.evidence;
    final next = existing.isNoLongerReproducible
        ? existing.recordRecurrence(
            actorId: candidate.history.first.actorId,
            at: _clock(),
            runId: candidate.sourceCommitSha,
            evidence: evidence.isEmpty ? null : evidence.first,
          )
        : evidence.isEmpty
            ? existing
            : existing.linkEvidence(
                actorId: candidate.history.first.actorId,
                at: _clock(),
                evidence: evidence,
                runId: candidate.sourceCommitSha,
              );
    if (identical(next, existing)) {
      return existing;
    }
    await _findings.replace(clientId, existing, next);
    return next;
  }

  /// Reviewer triage of an automated finding. QA-only lifecycle.
  Future<QaFinding> triageFinding({
    required String findingId,
    required ReviewActor actor,
  }) async {
    _requireReviewer(actor, 'triage a QA finding');
    final finding = await _requireFinding(findingId);
    return _replace(finding, finding.triage(actorId: actor.id, at: _clock()));
  }

  /// Reviewer dismissal of a finding as not actionable.
  Future<QaFinding> dismissFinding({
    required String findingId,
    required ReviewActor actor,
    required String reason,
  }) async {
    _requireReviewer(actor, 'dismiss a QA finding');
    final finding = await _requireFinding(findingId);
    return _replace(
      finding,
      finding.dismiss(actorId: actor.id, at: _clock(), reason: reason),
    );
  }

  /// Reviewer acceptance of a finding as a known, intentional risk.
  Future<QaFinding> acceptRiskFinding({
    required String findingId,
    required ReviewActor actor,
    required String reason,
  }) async {
    _requireReviewer(actor, 'accept risk on a QA finding');
    final finding = await _requireFinding(findingId);
    return _replace(
      finding,
      finding.acceptRisk(actorId: actor.id, at: _clock(), reason: reason),
    );
  }

  /// Explicitly promotes a finding into human review.
  ///
  /// The reviewer owns blocking classification; QA severity never sets it, so
  /// [blocking] defaults to `false`. Idempotent: repeating the promotion (or
  /// recovering after a crash) returns the same `FeedbackRecord` and never
  /// creates a second one.
  Future<FeedbackRecord> promoteFinding({
    required String findingId,
    required ReviewActor actor,
    bool blocking = false,
  }) async {
    _requireReviewer(actor, 'promote a QA finding');
    final inFlight = _inFlight[findingId];
    if (inFlight != null) {
      return inFlight;
    }
    final pending = _promote(findingId: findingId, actor: actor, blocking: blocking);
    _inFlight[findingId] = pending;
    try {
      return await pending;
    } finally {
      if (identical(_inFlight[findingId], pending)) {
        _inFlight.remove(findingId);
      }
    }
  }

  Future<FeedbackRecord> _promote({
    required String findingId,
    required ReviewActor actor,
    required bool blocking,
  }) async {
    final finding = await _requireFinding(findingId);
    if (finding.isPromoted) {
      final linked = await _review.loadFeedback(finding.feedbackId!);
      if (linked == null) {
        throw QaEvidenceMissing(
          'promoted QA finding $findingId references a missing feedback record',
        );
      }
      return linked;
    }
    if (!finding.canPromote) {
      throw QaFindingNotPromotable(
        'cannot promote ${finding.status.name} QA finding',
      );
    }

    // Crash recovery: a feedback record may already exist for this finding even
    // though the finding link was never persisted. Reconcile instead of
    // duplicating.
    final orphan = await _feedbackForFinding(findingId);
    if (orphan != null) {
      await _replace(
        finding,
        finding.promote(actorId: actor.id, at: _clock(), feedbackId: orphan.id),
      );
      return orphan;
    }

    final (scope, target) = _promotionTarget(finding);
    final record = await _review.createFeedback(
      actor: actor,
      id: 'feedback-${finding.id}',
      scope: scope,
      text: finding.summary,
      target: target,
      blocking: blocking,
      originQaFindingId: finding.id,
    );
    await _replace(
      finding,
      finding.promote(actorId: actor.id, at: _clock(), feedbackId: record.id),
    );
    return record;
  }

  /// Marks an unpromoted (or promoted) finding as no longer reproducible after a
  /// successful re-check. Never resolves or reclassifies linked feedback.
  Future<QaFinding> markFindingNoLongerReproducible({
    required String findingId,
    required String runId,
    String actorId = 'qa-runner',
  }) async {
    final finding = await _requireFinding(findingId);
    return _replace(
      finding,
      finding.markNoLongerReproducible(
        actorId: actorId,
        at: _clock(),
        runId: runId,
      ),
    );
  }

  /// Links additional QA evidence to a finding without changing its status.
  Future<QaFinding> linkEvidence({
    required String findingId,
    required List<QaEvidence> evidence,
    String actorId = 'qa-runner',
    String? runId,
  }) async {
    final finding = await _requireFinding(findingId);
    return _replace(
      finding,
      finding.linkEvidence(
        actorId: actorId,
        at: _clock(),
        evidence: evidence,
        runId: runId,
      ),
    );
  }

  /// All QA runs for this client, in deterministic id order.
  Future<List<QaRun>> allRuns() => _runs.list(clientId);

  /// Records a QA run and, when the run passed, marks [findingId] as no longer
  /// reproducible.
  ///
  /// Targeted re-check after refinement: only the affected surfaces are
  /// re-captured (see [affectedCaptureJobs]) and re-checked. This never resolves,
  /// reopens, or reclassifies a promoted `FeedbackRecord` — C.4 reviewer
  /// authority remains intact.
  ///
  /// Transactional: the finding is validated before the run is persisted, so an
  /// unknown finding id leaves no run record behind.
  Future<QaFinding> recordSuccessfulRecheck({
    required String findingId,
    required QaRun run,
  }) async {
    final finding = await _requireFinding(findingId);
    if (run.clientId != clientId) {
      throw InvalidQaFinding(
        'QA run belongs to client ${run.clientId}, not $clientId',
      );
    }
    await _runs.save(clientId, run);
    if (!run.passed) {
      return finding;
    }
    return _replace(
      finding,
      finding.markNoLongerReproducible(
        actorId: run.actorId,
        at: _clock(),
        runId: run.id,
      ),
    );
  }

  Future<QaFinding?> _activeFindingFor(String dedupeKey) async {
    final findings = await _findings.list(clientId);
    for (final finding in findings) {
      if (finding.dedupeKey != dedupeKey) continue;
      if (finding.status == QaFindingStatus.detected ||
          finding.status == QaFindingStatus.triaged ||
          finding.status == QaFindingStatus.promoted) {
        return finding;
      }
    }
    return null;
  }

  Future<FeedbackRecord?> _feedbackForFinding(String findingId) async {
    final records = await _review.allFeedback();
    for (final record in records) {
      if (record.originQaFindingId == findingId) {
        return record;
      }
    }
    return null;
  }

  /// Maps a finding onto the governed feedback scope/target it describes.
  ///
  /// A governed screen/section becomes a section or screen target, a bare
  /// direction becomes a decision target, and anything else (for example a
  /// Widgetbook story) becomes general feedback. Target validity is still owned
  /// and enforced by `ReviewCoordinator`.
  (FeedbackScope, FeedbackTarget) _promotionTarget(QaFinding finding) {
    final screen = finding.screen;
    final section = finding.section;
    if (screen != null && section != null) {
      return (
        FeedbackScope.section,
        FeedbackTarget(screen: screen, section: section),
      );
    }
    if (screen != null) {
      return (FeedbackScope.screen, FeedbackTarget(screen: screen));
    }
    final direction = finding.direction;
    if (direction != null) {
      return (FeedbackScope.decision, FeedbackTarget(direction: direction));
    }
    return (FeedbackScope.general, const FeedbackTarget());
  }

  Future<QaFinding> _requireFinding(String findingId) async {
    final finding = await _findings.load(clientId, findingId);
    if (finding == null) {
      throw QaFindingNotFound('unknown QA finding id: $findingId');
    }
    return finding;
  }

  Future<QaFinding> _replace(QaFinding current, QaFinding next) async {
    if (identical(current, next) || current == next) {
      return current;
    }
    await _findings.replace(clientId, current, next);
    return next;
  }

  void _requireReviewer(ReviewActor actor, String action) {
    if (!actor.isReviewer) {
      throw UnauthorizedReviewAction('reviewer authority is required to $action');
    }
  }
}
