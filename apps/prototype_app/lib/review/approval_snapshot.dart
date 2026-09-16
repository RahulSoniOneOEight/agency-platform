/// Immutable C.5 approval snapshot.
///
/// An [ApprovalSnapshot] freezes the reviewed experience at a point in time:
/// the review round, the C.3 decision tree, the unresolved non-blocking feedback
/// carried forward, and the source commit/review-state hash it was taken from.
/// Snapshots are append-only and never mutated; a later approval is a new,
/// higher [version] that may reference the snapshot it supersedes.
library;

import 'review_actor.dart';
import 'review_screen_decision.dart';

List<String> _normalizedIds(List<String> ids) {
  final seen = <String>{};
  final normalized = <String>[];
  for (final id in ids) {
    if (id.trim().isEmpty) {
      throw const FormatException('Approval feedback id must not be blank');
    }
    if (!seen.add(id)) {
      throw FormatException('Duplicate approval feedback id: $id');
    }
    normalized.add(id);
  }
  normalized.sort();
  return normalized;
}

final class ApprovalSnapshot {
  ApprovalSnapshot({
    required this.version,
    required this.clientId,
    required this.reviewRound,
    required this.reviewedBy,
    required this.approvedBy,
    required this.approvedAt,
    required this.selectedDirection,
    required Map<String, ReviewScreenDecision> screenSelections,
    required List<String> unresolvedNonBlockingFeedbackIds,
    required this.sourceCommitSha,
    required this.reviewStateHash,
    this.themePreset,
    this.supersedes,
  })  : screenSelections =
            Map<String, ReviewScreenDecision>.unmodifiable(screenSelections),
        unresolvedNonBlockingFeedbackIds =
            List<String>.unmodifiable(_normalizedIds(unresolvedNonBlockingFeedbackIds)) {
    if (version < 1) {
      throw const FormatException('Approval version must be positive');
    }
    if (clientId.trim().isEmpty) {
      throw const FormatException('Approval client id is required');
    }
    if (reviewRound < 1) {
      throw const FormatException('Approval review round must be positive');
    }
    if (reviewedBy.id.trim().isEmpty || reviewedBy.name.trim().isEmpty) {
      throw const FormatException('Approval reviewed_by identity is required');
    }
    if (!reviewedBy.isReviewer) {
      throw const FormatException('Approval reviewed_by must be a reviewer');
    }
    if (approvedBy.id.trim().isEmpty || approvedBy.name.trim().isEmpty) {
      throw const FormatException('Approval approved_by identity is required');
    }
    if (!approvedBy.isApprover) {
      throw const FormatException('Approval approved_by must be an approver');
    }
    if (selectedDirection != null && selectedDirection!.trim().isEmpty) {
      throw const FormatException('Approval selected_direction must not be blank');
    }
    if (sourceCommitSha.trim().isEmpty) {
      throw const FormatException('Approval source commit SHA is required');
    }
    if (reviewStateHash.trim().isEmpty) {
      throw const FormatException('Approval review state hash is required');
    }
    if (themePreset != null && themePreset!.trim().isEmpty) {
      throw const FormatException('Approval theme preset must not be blank');
    }
    final superseded = supersedes;
    if (superseded != null && (superseded < 1 || superseded >= version)) {
      throw const FormatException(
        'Approval supersedes must reference an earlier version',
      );
    }
    for (final screenId in screenSelections.keys) {
      if (screenId.trim().isEmpty) {
        throw const FormatException('Approval screen id must not be blank');
      }
    }
  }

  /// Monotonic, append-only approval version starting at 1.
  final int version;
  final String clientId;
  final int reviewRound;

  /// Identity that reviewed the round; role is always [ReviewRole.reviewer].
  final ReviewActor reviewedBy;

  /// Identity that issued approval; role is always [ReviewRole.approver].
  ///
  /// The same person may occupy both roles; they are still stored separately.
  final ReviewActor approvedBy;

  final DateTime approvedAt;
  final String? selectedDirection;
  final Map<String, ReviewScreenDecision> screenSelections;

  /// Unresolved non-blocking feedback carried forward into production backlog.
  final List<String> unresolvedNonBlockingFeedbackIds;

  final String sourceCommitSha;
  final String reviewStateHash;
  final String? themePreset;

  /// The version this snapshot directly supersedes, or `null` for the first.
  final int? supersedes;

  factory ApprovalSnapshot.fromJson(Map<String, dynamic> json) {
    final version = json['approval_version'];
    if (version is! int) {
      throw const FormatException('Missing approval version');
    }
    final clientId = json['client_id'];
    if (clientId is! String) {
      throw const FormatException('Missing approval client id');
    }
    final reviewRound = json['review_round'];
    if (reviewRound is! int) {
      throw const FormatException('Missing approval review round');
    }
    final reviewedBy = _actorFromJson(json['reviewed_by'], ReviewRole.reviewer);
    final approvedBy = _actorFromJson(json['approved_by'], ReviewRole.approver);
    final approvedAtValue = json['approved_at'];
    if (approvedAtValue is! String) {
      throw const FormatException('Missing approval timestamp');
    }
    final DateTime approvedAt;
    try {
      approvedAt = DateTime.parse(approvedAtValue);
    } on FormatException {
      throw const FormatException('Invalid approval timestamp');
    }
    final selectedDirection = json['selected_direction'];
    if (selectedDirection != null && selectedDirection is! String) {
      throw const FormatException('Invalid approval selected_direction');
    }
    final rawScreens = json['screens'];
    if (rawScreens is! Map || rawScreens.keys.any((key) => key is! String)) {
      throw const FormatException('Missing approval screens');
    }
    final screenSelections = <String, ReviewScreenDecision>{};
    for (final entry in rawScreens.entries) {
      final value = entry.value;
      if (value is! Map || value.keys.any((key) => key is! String)) {
        throw const FormatException('Invalid approval screen decision');
      }
      screenSelections[entry.key as String] =
          ReviewScreenDecision.fromJson(value.cast<String, dynamic>());
    }
    final rawUnresolved = json['unresolved_non_blocking'];
    if (rawUnresolved is! List) {
      throw const FormatException('Missing approval unresolved_non_blocking');
    }
    final unresolved = <String>[];
    for (final item in rawUnresolved) {
      if (item is! String) {
        throw const FormatException('Invalid approval unresolved feedback id');
      }
      unresolved.add(item);
    }
    final sourceCommitSha = json['source_commit_sha'];
    if (sourceCommitSha is! String) {
      throw const FormatException('Missing approval source commit SHA');
    }
    final reviewStateHash = json['review_state_hash'];
    if (reviewStateHash is! String) {
      throw const FormatException('Missing approval review state hash');
    }
    final themePreset = json['theme_preset'];
    if (themePreset != null && themePreset is! String) {
      throw const FormatException('Invalid approval theme preset');
    }
    final supersedes = json['supersedes'];
    if (supersedes != null && supersedes is! int) {
      throw const FormatException('Invalid approval supersedes');
    }
    return ApprovalSnapshot(
      version: version,
      clientId: clientId,
      reviewRound: reviewRound,
      reviewedBy: reviewedBy,
      approvedBy: approvedBy,
      approvedAt: approvedAt,
      selectedDirection: selectedDirection as String?,
      screenSelections: screenSelections,
      unresolvedNonBlockingFeedbackIds: unresolved,
      sourceCommitSha: sourceCommitSha,
      reviewStateHash: reviewStateHash,
      themePreset: themePreset as String?,
      supersedes: supersedes as int?,
    );
  }

  /// Deterministic canonical serialization; every key is always present.
  Map<String, dynamic> toJson() {
    final sortedScreens = screenSelections.keys.toList()..sort();
    return {
      'approval_version': version,
      'client_id': clientId,
      'review_round': reviewRound,
      'reviewed_by': {'id': reviewedBy.id, 'name': reviewedBy.name},
      'approved_by': {'id': approvedBy.id, 'name': approvedBy.name},
      'approved_at': approvedAt.toUtc().toIso8601String(),
      'selected_direction': selectedDirection,
      'screens': {
        for (final key in sortedScreens) key: screenSelections[key]!.toJson(),
      },
      'unresolved_non_blocking': [...unresolvedNonBlockingFeedbackIds],
      'source_commit_sha': sourceCommitSha,
      'review_state_hash': reviewStateHash,
      'theme_preset': themePreset,
      'supersedes': supersedes,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ApprovalSnapshot) return false;
    if (other.version != version ||
        other.clientId != clientId ||
        other.reviewRound != reviewRound ||
        other.reviewedBy != reviewedBy ||
        other.approvedBy != approvedBy ||
        other.approvedAt.toUtc() != approvedAt.toUtc() ||
        other.selectedDirection != selectedDirection ||
        other.sourceCommitSha != sourceCommitSha ||
        other.reviewStateHash != reviewStateHash ||
        other.themePreset != themePreset ||
        other.supersedes != supersedes) {
      return false;
    }
    return _mapEquals(other.screenSelections, screenSelections) &&
        _listEquals(other.unresolvedNonBlockingFeedbackIds,
            unresolvedNonBlockingFeedbackIds);
  }

  @override
  int get hashCode => Object.hash(
        version,
        clientId,
        reviewRound,
        reviewedBy,
        approvedBy,
        approvedAt.toUtc().microsecondsSinceEpoch,
        selectedDirection,
        sourceCommitSha,
        reviewStateHash,
        themePreset,
        supersedes,
        Object.hashAllUnordered(
          screenSelections.entries.map(
            (entry) => Object.hash(entry.key, entry.value),
          ),
        ),
        Object.hashAll(unresolvedNonBlockingFeedbackIds),
      );
}

ReviewActor _actorFromJson(Object? raw, ReviewRole role) {
  if (raw is! Map || raw.keys.any((key) => key is! String)) {
    throw const FormatException('Missing approval actor identity');
  }
  final id = raw['id'];
  final name = raw['name'];
  if (id is! String || name is! String) {
    throw const FormatException('Invalid approval actor identity');
  }
  return ReviewActor(id: id, name: name, role: role);
}

bool _mapEquals(
  Map<String, ReviewScreenDecision> a,
  Map<String, ReviewScreenDecision> b,
) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
