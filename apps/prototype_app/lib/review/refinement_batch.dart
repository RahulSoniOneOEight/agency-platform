/// C.7 refinement batch domain.
///
/// A [RefinementBatch] is the execution/audit authority for OpenCode changes
/// requested through review feedback. It is reviewer-created, freezes its scope
/// and confirmed change classification at `ready`, and may only move linked
/// feedback to `addressed` after required validation passes. Batches are
/// immutable value objects: every lifecycle step produces a new batch whose
/// [RefinementBatch.history] appends one event and never rewrites prior events.
///
/// The model is provider- and tool-agnostic: it records execution metadata but
/// never depends on OpenCode internals.
library;

import 'review_domain_error.dart';

enum RefinementBatchStatus {
  draft,
  ready,
  inProgress,
  validationFailed,
  readyForReview,
  completed,
}

enum ChangeClassification { implementationOnly, contractImpacting }

enum BatchValidationStatus { pending, passed, failed }

enum RefinementBatchEventType {
  created,
  edited,
  classificationConfirmed,
  markedReady,
  started,
  validationPassed,
  validationFailed,
  completed,
}

String refinementBatchStatusToWire(RefinementBatchStatus value) =>
    switch (value) {
      RefinementBatchStatus.draft => 'draft',
      RefinementBatchStatus.ready => 'ready',
      RefinementBatchStatus.inProgress => 'in_progress',
      RefinementBatchStatus.validationFailed => 'validation_failed',
      RefinementBatchStatus.readyForReview => 'ready_for_review',
      RefinementBatchStatus.completed => 'completed',
    };

RefinementBatchStatus refinementBatchStatusFromWire(String value) =>
    switch (value) {
      'draft' => RefinementBatchStatus.draft,
      'ready' => RefinementBatchStatus.ready,
      'in_progress' => RefinementBatchStatus.inProgress,
      'validation_failed' => RefinementBatchStatus.validationFailed,
      'ready_for_review' => RefinementBatchStatus.readyForReview,
      'completed' => RefinementBatchStatus.completed,
      _ => throw FormatException('Unknown refinement batch status: $value'),
    };

String changeClassificationToWire(ChangeClassification value) =>
    switch (value) {
      ChangeClassification.implementationOnly => 'implementation_only',
      ChangeClassification.contractImpacting => 'contract_impacting',
    };

ChangeClassification changeClassificationFromWire(String value) =>
    switch (value) {
      'implementation_only' => ChangeClassification.implementationOnly,
      'contract_impacting' => ChangeClassification.contractImpacting,
      _ => throw FormatException('Unknown change classification: $value'),
    };

String batchValidationStatusToWire(BatchValidationStatus value) =>
    switch (value) {
      BatchValidationStatus.pending => 'pending',
      BatchValidationStatus.passed => 'passed',
      BatchValidationStatus.failed => 'failed',
    };

BatchValidationStatus batchValidationStatusFromWire(String value) =>
    switch (value) {
      'pending' => BatchValidationStatus.pending,
      'passed' => BatchValidationStatus.passed,
      'failed' => BatchValidationStatus.failed,
      _ => throw FormatException('Unknown batch validation status: $value'),
    };

String refinementBatchEventTypeToWire(RefinementBatchEventType value) =>
    switch (value) {
      RefinementBatchEventType.created => 'created',
      RefinementBatchEventType.edited => 'edited',
      RefinementBatchEventType.classificationConfirmed =>
        'classification_confirmed',
      RefinementBatchEventType.markedReady => 'marked_ready',
      RefinementBatchEventType.started => 'started',
      RefinementBatchEventType.validationPassed => 'validation_passed',
      RefinementBatchEventType.validationFailed => 'validation_failed',
      RefinementBatchEventType.completed => 'completed',
    };

RefinementBatchEventType refinementBatchEventTypeFromWire(String value) =>
    switch (value) {
      'created' => RefinementBatchEventType.created,
      'edited' => RefinementBatchEventType.edited,
      'classification_confirmed' =>
        RefinementBatchEventType.classificationConfirmed,
      'marked_ready' => RefinementBatchEventType.markedReady,
      'started' => RefinementBatchEventType.started,
      'validation_passed' => RefinementBatchEventType.validationPassed,
      'validation_failed' => RefinementBatchEventType.validationFailed,
      'completed' => RefinementBatchEventType.completed,
      _ => throw FormatException('Unknown refinement batch event type: $value'),
    };

List<String> _normalizedStrings(List<String> values, String label) {
  final seen = <String>{};
  for (final value in values) {
    if (value.trim().isEmpty) {
      throw FormatException('Refinement batch $label must not be blank');
    }
    if (!seen.add(value)) {
      throw FormatException('Duplicate refinement batch $label: $value');
    }
  }
  return List<String>.unmodifiable(values.toList()..sort());
}

/// One required validation check recorded by an execution result.
final class ValidationCheck {
  const ValidationCheck({
    required this.name,
    required this.passed,
    required this.details,
  });

  final String name;
  final bool passed;
  final String details;

  factory ValidationCheck.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('Missing validation check name');
    }
    final passed = json['passed'];
    if (passed is! bool) {
      throw const FormatException('Missing validation check outcome');
    }
    final details = json['details'];
    if (details is! String) {
      throw const FormatException('Missing validation check details');
    }
    return ValidationCheck(name: name, passed: passed, details: details);
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'passed': passed,
        'details': details,
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ValidationCheck &&
        other.name == name &&
        other.passed == passed &&
        other.details == details;
  }

  @override
  int get hashCode => Object.hash(name, passed, details);
}

/// The frozen implementation scope of a batch (governed screens/sections).
final class IntendedScope {
  IntendedScope({
    List<String> screens = const <String>[],
    List<String> sections = const <String>[],
  })  : screens = _normalizedStrings(screens, 'scope screen'),
        sections = _normalizedStrings(sections, 'scope section') {
    if (this.screens.isEmpty && this.sections.isEmpty) {
      throw const FormatException(
        'Refinement batch scope requires at least one screen or section',
      );
    }
  }

  final List<String> screens;
  final List<String> sections;

  bool get isEmpty => screens.isEmpty && sections.isEmpty;

  factory IntendedScope.fromJson(Map<String, dynamic> json) {
    return IntendedScope(
      screens: _stringList(json['screens'], 'scope screens'),
      sections: _stringList(json['sections'], 'scope sections'),
    );
  }

  Map<String, dynamic> toJson() => {
        'screens': [...screens],
        'sections': [...sections],
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IntendedScope &&
        _listEquals(other.screens, screens) &&
        _listEquals(other.sections, sections);
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(screens), Object.hashAll(sections));
}

/// Proposed (OpenCode) and reviewer-confirmed change classification.
final class ChangeClassificationRecord {
  const ChangeClassificationRecord({
    required this.proposedBy,
    required this.proposed,
    this.confirmedBy,
    this.confirmed,
  });

  final String proposedBy;
  final ChangeClassification proposed;
  final String? confirmedBy;
  final ChangeClassification? confirmed;

  bool get isConfirmed => confirmed != null && confirmedBy != null;

  factory ChangeClassificationRecord.fromJson(Map<String, dynamic> json) {
    final proposedBy = json['proposed_by'];
    if (proposedBy is! String || proposedBy.trim().isEmpty) {
      throw const FormatException('Missing change classification proposer');
    }
    final proposedValue = json['proposed'];
    if (proposedValue is! String) {
      throw const FormatException('Missing proposed change classification');
    }
    final confirmedBy = json['confirmed_by'];
    if (confirmedBy != null &&
        (confirmedBy is! String || confirmedBy.trim().isEmpty)) {
      throw const FormatException('Invalid change classification confirmer');
    }
    final confirmedValue = json['confirmed'];
    if (confirmedValue != null && confirmedValue is! String) {
      throw const FormatException('Invalid confirmed change classification');
    }
    return ChangeClassificationRecord(
      proposedBy: proposedBy,
      proposed: changeClassificationFromWire(proposedValue),
      confirmedBy: confirmedBy as String?,
      confirmed: confirmedValue == null
          ? null
          : changeClassificationFromWire(confirmedValue),
    );
  }

  Map<String, dynamic> toJson() => {
        'proposed_by': proposedBy,
        'proposed': changeClassificationToWire(proposed),
        'confirmed_by': confirmedBy,
        'confirmed': confirmed == null ? null : changeClassificationToWire(confirmed!),
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChangeClassificationRecord &&
        other.proposedBy == proposedBy &&
        other.proposed == proposed &&
        other.confirmedBy == confirmedBy &&
        other.confirmed == confirmed;
  }

  @override
  int get hashCode => Object.hash(proposedBy, proposed, confirmedBy, confirmed);
}

/// Execution metadata recorded by OpenCode for a batch.
final class BatchExecution {
  BatchExecution({
    this.agent,
    this.model,
    this.commitSha,
    List<String> filesChanged = const <String>[],
  }) : filesChanged = _normalizedStrings(filesChanged, 'changed file') {
    _requireOptional(agent, 'execution agent');
    _requireOptional(model, 'execution model');
    _requireOptional(commitSha, 'execution commit sha');
  }

  final String? agent;
  final String? model;
  final String? commitSha;
  final List<String> filesChanged;

  static void _requireOptional(String? value, String label) {
    if (value != null && value.trim().isEmpty) {
      throw FormatException('Refinement batch $label must not be blank');
    }
  }

  factory BatchExecution.fromJson(Map<String, dynamic> json) {
    return BatchExecution(
      agent: _optionalString(json['agent'], 'execution agent'),
      model: _optionalString(json['model'], 'execution model'),
      commitSha: _optionalString(json['commit_sha'], 'execution commit sha'),
      filesChanged: _stringList(json['files_changed'], 'changed files'),
    );
  }

  Map<String, dynamic> toJson() => {
        'agent': agent,
        'model': model,
        'commit_sha': commitSha,
        'files_changed': [...filesChanged],
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BatchExecution &&
        other.agent == agent &&
        other.model == model &&
        other.commitSha == commitSha &&
        _listEquals(other.filesChanged, filesChanged);
  }

  @override
  int get hashCode =>
      Object.hash(agent, model, commitSha, Object.hashAll(filesChanged));
}

/// The recorded validation outcome of a batch.
final class BatchValidation {
  BatchValidation({
    required this.status,
    List<ValidationCheck> checks = const <ValidationCheck>[],
  }) : checks = List<ValidationCheck>.unmodifiable(checks);

  final BatchValidationStatus status;
  final List<ValidationCheck> checks;

  bool get hasPassedCheck => checks.any((check) => check.passed);

  bool get allPassed => checks.isNotEmpty && checks.every((check) => check.passed);

  factory BatchValidation.fromJson(Map<String, dynamic> json) {
    final statusValue = json['status'];
    if (statusValue is! String) {
      throw const FormatException('Missing batch validation status');
    }
    final rawChecks = json['checks'];
    if (rawChecks is! List) {
      throw const FormatException('Missing batch validation checks');
    }
    final checks = <ValidationCheck>[];
    for (final item in rawChecks) {
      if (item is! Map || item.keys.any((key) => key is! String)) {
        throw const FormatException('Invalid batch validation check');
      }
      checks.add(ValidationCheck.fromJson(item.cast<String, dynamic>()));
    }
    return BatchValidation(
      status: batchValidationStatusFromWire(statusValue),
      checks: checks,
    );
  }

  Map<String, dynamic> toJson() => {
        'status': batchValidationStatusToWire(status),
        'checks': [for (final check in checks) check.toJson()],
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BatchValidation &&
        other.status == status &&
        _checkListEquals(other.checks, checks);
  }

  @override
  int get hashCode => Object.hash(status, Object.hashAll(checks));
}

/// One append-only lifecycle event on a [RefinementBatch].
final class RefinementBatchEvent {
  const RefinementBatchEvent({
    required this.type,
    required this.actorId,
    required this.at,
    this.note,
  });

  final RefinementBatchEventType type;
  final String actorId;
  final DateTime at;
  final String? note;

  factory RefinementBatchEvent.fromJson(Map<String, dynamic> json) {
    final typeValue = json['type'];
    if (typeValue is! String) {
      throw const FormatException('Missing refinement batch event type');
    }
    final actorId = json['actor_id'];
    if (actorId is! String || actorId.trim().isEmpty) {
      throw const FormatException('Missing refinement batch event actor');
    }
    final atValue = json['at'];
    if (atValue is! String) {
      throw const FormatException('Missing refinement batch event timestamp');
    }
    final DateTime at;
    try {
      at = DateTime.parse(atValue);
    } on FormatException {
      throw const FormatException('Invalid refinement batch event timestamp');
    }
    final note = json['note'];
    if (note != null && note is! String) {
      throw const FormatException('Invalid refinement batch event note');
    }
    return RefinementBatchEvent(
      type: refinementBatchEventTypeFromWire(typeValue),
      actorId: actorId,
      at: at,
      note: note as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': refinementBatchEventTypeToWire(type),
        'actor_id': actorId,
        'at': at.toUtc().toIso8601String(),
        if (note != null) 'note': note,
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RefinementBatchEvent &&
        other.type == type &&
        other.actorId == actorId &&
        other.at.toUtc() == at.toUtc() &&
        other.note == note;
  }

  @override
  int get hashCode =>
      Object.hash(type, actorId, at.toUtc().microsecondsSinceEpoch, note);
}

/// Immutable refinement batch with an append-only lifecycle history.
///
/// Construction validates the batch invariants and malformed payloads throw a
/// [FormatException]. Lifecycle operations return a new batch and throw typed
/// [ReviewDomainError]s for illegal transitions, frozen scope, or missing
/// confirmation/validation evidence.
final class RefinementBatch {
  RefinementBatch({
    required this.id,
    required this.clientId,
    required this.reviewRound,
    required this.status,
    required List<String> feedbackIds,
    required this.intendedScope,
    required this.changeClassification,
    required this.execution,
    required this.validation,
    List<String> evidence = const <String>[],
    required this.createdAt,
    required this.updatedAt,
    List<RefinementBatchEvent> history = const <RefinementBatchEvent>[],
  })  : feedbackIds = _normalizedStrings(feedbackIds, 'feedback id'),
        evidence = _normalizedStrings(evidence, 'evidence reference'),
        history = List<RefinementBatchEvent>.unmodifiable(history) {
    if (id.trim().isEmpty) {
      throw const FormatException('Refinement batch id is required');
    }
    if (clientId.trim().isEmpty) {
      throw const FormatException('Refinement batch client id is required');
    }
    if (reviewRound < 1) {
      throw const FormatException('Refinement batch review round must be positive');
    }
    if (this.feedbackIds.isEmpty) {
      throw const FormatException(
        'Refinement batch requires at least one linked feedback id',
      );
    }
    if (this.history.isEmpty) {
      throw const FormatException('Refinement batch history is required');
    }
    if (this.history.first.type != RefinementBatchEventType.created) {
      throw const FormatException(
        'Refinement batch history must start with a created event',
      );
    }
    if (updatedAt.toUtc().isBefore(createdAt.toUtc())) {
      throw const FormatException(
        'Refinement batch updated_at must not precede created_at',
      );
    }
    if (changeClassification.proposedBy.trim().isEmpty) {
      throw const FormatException(
        'Refinement batch change classification proposer is required',
      );
    }
    if (status != RefinementBatchStatus.draft && !changeClassification.isConfirmed) {
      throw const FormatException(
        'Refinement batch requires a confirmed change classification before ready',
      );
    }
    if (status == RefinementBatchStatus.inProgress &&
        validation.status != BatchValidationStatus.pending) {
      throw const FormatException(
        'In-progress refinement batch validation must be pending',
      );
    }
    if (status == RefinementBatchStatus.readyForReview &&
        (validation.status != BatchValidationStatus.passed ||
            !validation.hasPassedCheck)) {
      throw const FormatException(
        'ready_for_review requires a successful validation record',
      );
    }
    if (status == RefinementBatchStatus.validationFailed &&
        validation.status != BatchValidationStatus.failed) {
      throw const FormatException(
        'validation_failed requires a failed validation record',
      );
    }
  }

  final String id;
  final String clientId;
  final int reviewRound;
  final RefinementBatchStatus status;
  final List<String> feedbackIds;
  final IntendedScope intendedScope;
  final ChangeClassificationRecord changeClassification;
  final BatchExecution execution;
  final BatchValidation validation;
  final List<String> evidence;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<RefinementBatchEvent> history;

  /// Whether a batch is frozen and no longer mutable in place.
  bool get isFrozen =>
      status == RefinementBatchStatus.ready ||
      status == RefinementBatchStatus.inProgress ||
      status == RefinementBatchStatus.validationFailed ||
      status == RefinementBatchStatus.readyForReview ||
      status == RefinementBatchStatus.completed;

  bool get isCompleted => status == RefinementBatchStatus.completed;

  /// Creates a new `draft` batch with an initial `created` history event.
  factory RefinementBatch.draft({
    required String id,
    required String clientId,
    required int reviewRound,
    required List<String> feedbackIds,
    required IntendedScope intendedScope,
    required String proposedBy,
    required ChangeClassification proposed,
    required String createdBy,
    required DateTime createdAt,
  }) {
    return RefinementBatch(
      id: id,
      clientId: clientId,
      reviewRound: reviewRound,
      status: RefinementBatchStatus.draft,
      feedbackIds: feedbackIds,
      intendedScope: intendedScope,
      changeClassification: ChangeClassificationRecord(
        proposedBy: proposedBy,
        proposed: proposed,
      ),
      execution: BatchExecution(),
      validation: BatchValidation(status: BatchValidationStatus.pending),
      createdAt: createdAt,
      updatedAt: createdAt,
      history: <RefinementBatchEvent>[
        RefinementBatchEvent(
          type: RefinementBatchEventType.created,
          actorId: createdBy,
          at: createdAt,
        ),
      ],
    );
  }

  /// Legal lifecycle transitions. `completed` is terminal.
  static bool canTransition(
    RefinementBatchStatus from,
    RefinementBatchStatus to,
  ) {
    return switch ((from, to)) {
      (RefinementBatchStatus.draft, RefinementBatchStatus.ready) => true,
      (RefinementBatchStatus.ready, RefinementBatchStatus.inProgress) => true,
      (RefinementBatchStatus.inProgress, RefinementBatchStatus.validationFailed) =>
        true,
      (RefinementBatchStatus.inProgress, RefinementBatchStatus.readyForReview) =>
        true,
      (RefinementBatchStatus.validationFailed, RefinementBatchStatus.inProgress) =>
        true,
      (RefinementBatchStatus.validationFailed, RefinementBatchStatus.completed) =>
        true,
      (RefinementBatchStatus.readyForReview, RefinementBatchStatus.completed) =>
        true,
      _ => false,
    };
  }

  factory RefinementBatch.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String) {
      throw const FormatException('Missing refinement batch id');
    }
    final clientId = json['client_id'];
    if (clientId is! String) {
      throw const FormatException('Missing refinement batch client id');
    }
    final reviewRound = json['review_round'];
    if (reviewRound is! int) {
      throw const FormatException('Missing refinement batch review round');
    }
    final statusValue = json['status'];
    if (statusValue is! String) {
      throw const FormatException('Missing refinement batch status');
    }
    final rawScope = _requireMap(json['intended_scope'], 'intended scope');
    final rawClassification = _requireMap(
      json['change_classification'],
      'change classification',
    );
    final rawExecution = _requireMap(json['execution'], 'execution');
    final rawValidation = _requireMap(json['validation'], 'validation');
    final createdAt = _requireDateTime(json['created_at'], 'created_at');
    final updatedAt = _requireDateTime(json['updated_at'], 'updated_at');
    final rawHistory = json['history'];
    if (rawHistory is! List) {
      throw const FormatException('Missing refinement batch history');
    }
    final history = <RefinementBatchEvent>[];
    for (final item in rawHistory) {
      if (item is! Map || item.keys.any((key) => key is! String)) {
        throw const FormatException('Invalid refinement batch history event');
      }
      history.add(RefinementBatchEvent.fromJson(item.cast<String, dynamic>()));
    }
    return RefinementBatch(
      id: id,
      clientId: clientId,
      reviewRound: reviewRound,
      status: refinementBatchStatusFromWire(statusValue),
      feedbackIds: _stringList(json['feedback_ids'], 'feedback ids'),
      intendedScope: IntendedScope.fromJson(rawScope),
      changeClassification:
          ChangeClassificationRecord.fromJson(rawClassification),
      execution: BatchExecution.fromJson(rawExecution),
      validation: BatchValidation.fromJson(rawValidation),
      evidence: _stringList(json['evidence'], 'evidence'),
      createdAt: createdAt,
      updatedAt: updatedAt,
      history: history,
    );
  }

  /// Deterministic canonical serialization; every key is always present.
  Map<String, dynamic> toJson() => {
        'id': id,
        'client_id': clientId,
        'review_round': reviewRound,
        'status': refinementBatchStatusToWire(status),
        'feedback_ids': [...feedbackIds],
        'intended_scope': intendedScope.toJson(),
        'change_classification': changeClassification.toJson(),
        'execution': execution.toJson(),
        'validation': validation.toJson(),
        'evidence': [...evidence],
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'history': [for (final event in history) event.toJson()],
      };

  RefinementBatch copyWith({
    RefinementBatchStatus? status,
    List<String>? feedbackIds,
    IntendedScope? intendedScope,
    ChangeClassificationRecord? changeClassification,
    BatchExecution? execution,
    BatchValidation? validation,
    List<String>? evidence,
    DateTime? updatedAt,
    List<RefinementBatchEvent>? history,
  }) {
    return RefinementBatch(
      id: id,
      clientId: clientId,
      reviewRound: reviewRound,
      status: status ?? this.status,
      feedbackIds: feedbackIds ?? this.feedbackIds,
      intendedScope: intendedScope ?? this.intendedScope,
      changeClassification: changeClassification ?? this.changeClassification,
      execution: execution ?? this.execution,
      validation: validation ?? this.validation,
      evidence: evidence ?? this.evidence,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      history: history ?? this.history,
    );
  }

  /// Edits linked feedback/scope; only legal while the batch is `draft`.
  RefinementBatch editDraft({
    required String actorId,
    required DateTime at,
    List<String>? feedbackIds,
    IntendedScope? intendedScope,
  }) {
    _assertNotCompleted();
    if (status != RefinementBatchStatus.draft) {
      throw BatchScopeFrozen(
        'refinement batch $id scope is frozen after ready',
      );
    }
    return copyWith(
      feedbackIds: feedbackIds,
      intendedScope: intendedScope,
      updatedAt: at,
      history: [
        ...history,
        RefinementBatchEvent(
          type: RefinementBatchEventType.edited,
          actorId: actorId,
          at: at,
        ),
      ],
    );
  }

  /// Records the reviewer-confirmed classification; only legal in `draft`.
  RefinementBatch confirmClassification({
    required String actorId,
    required DateTime at,
    required ChangeClassification confirmed,
  }) {
    _assertNotCompleted();
    if (status != RefinementBatchStatus.draft) {
      throw BatchScopeFrozen(
        'refinement batch $id change classification is frozen after ready',
      );
    }
    return copyWith(
      changeClassification: ChangeClassificationRecord(
        proposedBy: changeClassification.proposedBy,
        proposed: changeClassification.proposed,
        confirmedBy: actorId,
        confirmed: confirmed,
      ),
      updatedAt: at,
      history: [
        ...history,
        RefinementBatchEvent(
          type: RefinementBatchEventType.classificationConfirmed,
          actorId: actorId,
          at: at,
          note: changeClassificationToWire(confirmed),
        ),
      ],
    );
  }

  /// Freezes scope and classification and moves `draft -> ready`.
  RefinementBatch markReady({
    required String actorId,
    required DateTime at,
  }) {
    _assertNotCompleted();
    if (!changeClassification.isConfirmed) {
      throw ContractClassificationUnconfirmed(
        'refinement batch $id requires a confirmed change classification',
      );
    }
    _assertTransition(RefinementBatchStatus.ready);
    return copyWith(
      status: RefinementBatchStatus.ready,
      updatedAt: at,
      history: [
        ...history,
        RefinementBatchEvent(
          type: RefinementBatchEventType.markedReady,
          actorId: actorId,
          at: at,
        ),
      ],
    );
  }

  /// Begins execution (`ready -> inProgress`, or retry from `validationFailed`).
  RefinementBatch start({
    required String actorId,
    required DateTime at,
    String? agent,
    String? model,
  }) {
    _assertNotCompleted();
    if (status != RefinementBatchStatus.ready &&
        status != RefinementBatchStatus.validationFailed) {
      throw BatchNotReady(
        'refinement batch $id must be ready before execution '
        '(currently ${refinementBatchStatusToWire(status)})',
      );
    }
    _assertTransition(RefinementBatchStatus.inProgress);
    final nextExecution = BatchExecution(
      agent: agent ?? execution.agent,
      model: model ?? execution.model,
      commitSha: execution.commitSha,
      filesChanged: execution.filesChanged,
    );
    return copyWith(
      status: RefinementBatchStatus.inProgress,
      execution: nextExecution,
      validation: BatchValidation(
        status: BatchValidationStatus.pending,
        checks: validation.checks,
      ),
      updatedAt: at,
      history: [
        ...history,
        RefinementBatchEvent(
          type: RefinementBatchEventType.started,
          actorId: actorId,
          at: at,
        ),
      ],
    );
  }

  /// Records a validation result (`inProgress -> readyForReview | validationFailed`).
  RefinementBatch recordValidation({
    required String actorId,
    required DateTime at,
    required BatchValidation validation,
    required BatchExecution execution,
    List<String> evidence = const <String>[],
  }) {
    _assertNotCompleted();
    if (status != RefinementBatchStatus.inProgress) {
      throw BatchNotReady(
        'refinement batch $id is not in progress '
        '(currently ${refinementBatchStatusToWire(status)})',
      );
    }
    if (validation.status == BatchValidationStatus.pending) {
      throw InvalidBatchTransition(
        'refinement batch $id validation result must be passed or failed',
      );
    }
    if (validation.status == BatchValidationStatus.passed &&
        !validation.hasPassedCheck) {
      throw BatchValidationRequired(
        'refinement batch $id requires at least one passed validation check',
      );
    }
    final target = validation.status == BatchValidationStatus.passed
        ? RefinementBatchStatus.readyForReview
        : RefinementBatchStatus.validationFailed;
    _assertTransition(target);
    return copyWith(
      status: target,
      validation: validation,
      execution: execution,
      evidence: <String>[...this.evidence, ...evidence],
      updatedAt: at,
      history: [
        ...history,
        RefinementBatchEvent(
          type: target == RefinementBatchStatus.readyForReview
              ? RefinementBatchEventType.validationPassed
              : RefinementBatchEventType.validationFailed,
          actorId: actorId,
          at: at,
        ),
      ],
    );
  }

  /// Completes a batch after review; `completed` batches are frozen.
  RefinementBatch complete({
    required String actorId,
    required DateTime at,
  }) {
    _assertNotCompleted();
    _assertTransition(RefinementBatchStatus.completed);
    return copyWith(
      status: RefinementBatchStatus.completed,
      updatedAt: at,
      history: [
        ...history,
        RefinementBatchEvent(
          type: RefinementBatchEventType.completed,
          actorId: actorId,
          at: at,
        ),
      ],
    );
  }

  void _assertNotCompleted() {
    if (status == RefinementBatchStatus.completed) {
      throw BatchAlreadyCompleted('refinement batch $id is completed and frozen');
    }
  }

  void _assertTransition(RefinementBatchStatus target) {
    if (!canTransition(status, target)) {
      throw InvalidBatchTransition(
        'illegal refinement batch transition '
        '${refinementBatchStatusToWire(status)} -> '
        '${refinementBatchStatusToWire(target)}',
      );
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RefinementBatch) return false;
    if (other.id != id ||
        other.clientId != clientId ||
        other.reviewRound != reviewRound ||
        other.status != status ||
        other.intendedScope != intendedScope ||
        other.changeClassification != changeClassification ||
        other.execution != execution ||
        other.validation != validation ||
        other.createdAt.toUtc() != createdAt.toUtc() ||
        other.updatedAt.toUtc() != updatedAt.toUtc()) {
      return false;
    }
    return _listEquals(other.feedbackIds, feedbackIds) &&
        _listEquals(other.evidence, evidence) &&
        _eventListEquals(other.history, history);
  }

  @override
  int get hashCode => Object.hash(
        id,
        clientId,
        reviewRound,
        status,
        Object.hashAll(feedbackIds),
        intendedScope,
        changeClassification,
        execution,
        validation,
        Object.hashAll(evidence),
        createdAt.toUtc().microsecondsSinceEpoch,
        updatedAt.toUtc().microsecondsSinceEpoch,
        Object.hashAll(history),
      );
}

Map<String, dynamic> _requireMap(Object? value, String field) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('Missing refinement batch $field');
  }
  return value.cast<String, dynamic>();
}

DateTime _requireDateTime(Object? value, String field) {
  if (value is! String) {
    throw FormatException('Missing refinement batch $field');
  }
  try {
    return DateTime.parse(value);
  } on FormatException {
    throw FormatException('Invalid refinement batch $field');
  }
}

String? _optionalString(Object? value, String field) {
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid refinement batch $field');
  }
  return value;
}

List<String> _stringList(Object? value, String field) {
  if (value == null) return const <String>[];
  if (value is! List) {
    throw FormatException('Invalid refinement batch $field');
  }
  final result = <String>[];
  for (final item in value) {
    if (item is! String) {
      throw FormatException('Invalid refinement batch $field');
    }
    result.add(item);
  }
  return result;
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

bool _checkListEquals(List<ValidationCheck> a, List<ValidationCheck> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

bool _eventListEquals(List<RefinementBatchEvent> a, List<RefinementBatchEvent> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
