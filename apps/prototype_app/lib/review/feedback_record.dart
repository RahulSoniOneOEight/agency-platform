/// Unified C.4 feedback domain.
///
/// A [FeedbackRecord] is the sole identity and lifecycle authority for review
/// feedback. Records are immutable value objects: every lifecycle step produces
/// a new record whose [FeedbackRecord.history] appends one event and never
/// rewrites or deletes prior events. Targets are validated against the selected
/// [FeedbackScope] and malformed wire payloads fail with a [FormatException].
library;

import 'visual_attachment.dart';

enum FeedbackStatus { open, addressed, resolved }

enum FeedbackScope { general, screen, section, decision, visualAnnotation }

enum FeedbackEventType { created, addressed, reopened, resolved, blockingChanged }

String feedbackStatusToWire(FeedbackStatus value) => switch (value) {
      FeedbackStatus.open => 'open',
      FeedbackStatus.addressed => 'addressed',
      FeedbackStatus.resolved => 'resolved',
    };

FeedbackStatus feedbackStatusFromWire(String value) => switch (value) {
      'open' => FeedbackStatus.open,
      'addressed' => FeedbackStatus.addressed,
      'resolved' => FeedbackStatus.resolved,
      _ => throw FormatException('Unknown feedback status: $value'),
    };

String feedbackScopeToWire(FeedbackScope value) => switch (value) {
      FeedbackScope.general => 'general',
      FeedbackScope.screen => 'screen',
      FeedbackScope.section => 'section',
      FeedbackScope.decision => 'decision',
      FeedbackScope.visualAnnotation => 'visual_annotation',
    };

FeedbackScope feedbackScopeFromWire(String value) => switch (value) {
      'general' => FeedbackScope.general,
      'screen' => FeedbackScope.screen,
      'section' => FeedbackScope.section,
      'decision' => FeedbackScope.decision,
      'visual_annotation' => FeedbackScope.visualAnnotation,
      _ => throw FormatException('Unknown feedback scope: $value'),
    };

String feedbackEventTypeToWire(FeedbackEventType value) => switch (value) {
      FeedbackEventType.created => 'created',
      FeedbackEventType.addressed => 'addressed',
      FeedbackEventType.reopened => 'reopened',
      FeedbackEventType.resolved => 'resolved',
      FeedbackEventType.blockingChanged => 'blocking_changed',
    };

FeedbackEventType feedbackEventTypeFromWire(String value) => switch (value) {
      'created' => FeedbackEventType.created,
      'addressed' => FeedbackEventType.addressed,
      'reopened' => FeedbackEventType.reopened,
      'resolved' => FeedbackEventType.resolved,
      'blocking_changed' => FeedbackEventType.blockingChanged,
      _ => throw FormatException('Unknown feedback event type: $value'),
    };

/// Derives the lifecycle status implied by an append-only event history.
///
/// `created`/`reopened` open the item, `addressed` marks it ready for reviewer
/// re-check, `resolved` accepts it, and `blockingChanged` never changes status.
FeedbackStatus feedbackStatusForHistory(List<FeedbackEvent> history) {
  var status = FeedbackStatus.open;
  for (final event in history) {
    switch (event.type) {
      case FeedbackEventType.created:
      case FeedbackEventType.reopened:
        status = FeedbackStatus.open;
      case FeedbackEventType.addressed:
        status = FeedbackStatus.addressed;
      case FeedbackEventType.resolved:
        status = FeedbackStatus.resolved;
      case FeedbackEventType.blockingChanged:
        break;
    }
  }
  return status;
}

/// Validates that an append-only history is a legal lifecycle walk.
///
/// `created` opens the item; `addressed` is only legal from `open`; `resolved`
/// only from `addressed`; `reopened` only from `addressed`/`resolved`; and
/// `blockingChanged` may occur at any point. Illegal sequences (for example
/// `created -> resolved -> addressed`) throw a [FormatException].
void _validateHistoryTransitions(List<FeedbackEvent> history) {
  var current = FeedbackStatus.open;
  for (var index = 1; index < history.length; index++) {
    switch (history[index].type) {
      case FeedbackEventType.created:
        throw const FormatException(
          'Feedback history must not repeat the created event',
        );
      case FeedbackEventType.addressed:
        if (current != FeedbackStatus.open) {
          throw FormatException(
            'Illegal feedback history: addressed from ${current.name}',
          );
        }
        current = FeedbackStatus.addressed;
      case FeedbackEventType.resolved:
        if (current != FeedbackStatus.addressed) {
          throw FormatException(
            'Illegal feedback history: resolved from ${current.name}',
          );
        }
        current = FeedbackStatus.resolved;
      case FeedbackEventType.reopened:
        if (current == FeedbackStatus.open) {
          throw const FormatException(
            'Illegal feedback history: reopened from open',
          );
        }
        current = FeedbackStatus.open;
      case FeedbackEventType.blockingChanged:
        break;
    }
  }
}

/// What a feedback item points at. Which fields are legal depends on scope.
final class FeedbackTarget {
  const FeedbackTarget({this.screen, this.section, this.direction});

  final String? screen;
  final String? section;
  final String? direction;

  /// Whether this target is well-formed for [scope].
  ///
  /// - `general` must carry no target fields;
  /// - `screen` must name a screen (no section);
  /// - `section` must name a governed screen and section;
  /// - `decision` must name a direction;
  /// - `visualAnnotation` may target a free-form region, but a section still
  ///   requires its screen.
  bool isValidForScope(FeedbackScope scope) {
    if (!_isAbsentOrNonBlank(screen) ||
        !_isAbsentOrNonBlank(section) ||
        !_isAbsentOrNonBlank(direction)) {
      return false;
    }
    final hasScreen = screen != null;
    final hasSection = section != null;
    final hasDirection = direction != null;
    if (hasSection && !hasScreen) return false;
    return switch (scope) {
      FeedbackScope.general => !hasScreen && !hasSection && !hasDirection,
      FeedbackScope.screen => hasScreen && !hasSection,
      FeedbackScope.section => hasScreen && hasSection,
      FeedbackScope.decision => hasDirection,
      FeedbackScope.visualAnnotation => true,
    };
  }

  static bool _isAbsentOrNonBlank(String? value) =>
      value == null || value.trim().isNotEmpty;

  factory FeedbackTarget.fromJson(Map<String, dynamic> json) {
    final screen = json['screen'];
    final section = json['section'];
    final direction = json['direction'];
    for (final value in [screen, section, direction]) {
      if (value != null && (value is! String || value.trim().isEmpty)) {
        throw const FormatException('Invalid feedback target');
      }
    }
    return FeedbackTarget(
      screen: screen as String?,
      section: section as String?,
      direction: direction as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (screen != null) 'screen': screen,
      if (section != null) 'section': section,
      if (direction != null) 'direction': direction,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FeedbackTarget &&
        other.screen == screen &&
        other.section == section &&
        other.direction == direction;
  }

  @override
  int get hashCode => Object.hash(screen, section, direction);

  @override
  String toString() =>
      'FeedbackTarget(screen: $screen, section: $section, direction: $direction)';
}

/// One append-only lifecycle event on a [FeedbackRecord].
final class FeedbackEvent {
  const FeedbackEvent({
    required this.type,
    required this.actorId,
    required this.at,
    this.round,
    this.batchId,
    this.cause,
    this.evidence,
  });

  final FeedbackEventType type;
  final String actorId;
  final DateTime at;
  final int? round;
  final String? batchId;

  /// Regression cause recorded by a system-failure reopen (C.7).
  ///
  /// Only present on a `reopened` event produced by
  /// `ReviewCoordinator.reopenAddressedForRegression`.
  final String? cause;

  /// Evidence reference that identified the regression (C.7).
  final String? evidence;

  factory FeedbackEvent.fromJson(Map<String, dynamic> json) {
    final typeValue = json['type'];
    if (typeValue is! String) {
      throw const FormatException('Missing feedback event type');
    }
    final actorId = json['actor_id'];
    if (actorId is! String || actorId.trim().isEmpty) {
      throw const FormatException('Missing feedback event actor');
    }
    final atValue = json['at'];
    if (atValue is! String) {
      throw const FormatException('Missing feedback event timestamp');
    }
    final DateTime at;
    try {
      at = DateTime.parse(atValue);
    } on FormatException {
      throw const FormatException('Invalid feedback event timestamp');
    }
    final round = json['round'];
    if (round != null && (round is! int || round < 1)) {
      throw const FormatException('Invalid feedback event round');
    }
    final batchId = json['batch_id'];
    if (batchId != null && (batchId is! String || batchId.trim().isEmpty)) {
      throw const FormatException('Invalid feedback event batch id');
    }
    final cause = json['cause'];
    if (cause != null && (cause is! String || cause.trim().isEmpty)) {
      throw const FormatException('Invalid feedback event cause');
    }
    final evidence = json['evidence'];
    if (evidence != null && (evidence is! String || evidence.trim().isEmpty)) {
      throw const FormatException('Invalid feedback event evidence');
    }
    return FeedbackEvent(
      type: feedbackEventTypeFromWire(typeValue),
      actorId: actorId,
      at: at,
      round: round as int?,
      batchId: batchId as String?,
      cause: cause as String?,
      evidence: evidence as String?,
    );
  }

  /// Deterministic serialization; optional keys only when present.
  Map<String, dynamic> toJson() {
    return {
      'type': feedbackEventTypeToWire(type),
      'actor_id': actorId,
      'at': at.toUtc().toIso8601String(),
      if (round != null) 'round': round,
      if (batchId != null) 'batch_id': batchId,
      if (cause != null) 'cause': cause,
      if (evidence != null) 'evidence': evidence,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FeedbackEvent &&
        other.type == type &&
        other.actorId == actorId &&
        other.at.toUtc() == at.toUtc() &&
        other.round == round &&
        other.batchId == batchId &&
        other.cause == cause &&
        other.evidence == evidence;
  }

  @override
  int get hashCode => Object.hash(
        type,
        actorId,
        at.toUtc().microsecondsSinceEpoch,
        round,
        batchId,
        cause,
        evidence,
      );
}

const Object _unset = Object();

/// Immutable, append-only feedback record.
///
/// Construction validates scope/target compatibility, a positive creation
/// round, and history consistency (starts with `created`, never repeats it, and
/// derives the declared [status]). [resolvedRound] is present exactly when the
/// record is currently resolved. Malformed wire payloads throw a
/// [FormatException].
final class FeedbackRecord {
  FeedbackRecord({
    required this.id,
    required this.scope,
    required this.text,
    required this.status,
    required this.blocking,
    required this.createdRound,
    required this.target,
    required List<FeedbackEvent> history,
    this.resolvedRound,
    this.visualAttachment,
    this.originQaFindingId,
  }) : history = List<FeedbackEvent>.unmodifiable(history) {
    if (id.trim().isEmpty) {
      throw const FormatException('Feedback id is required');
    }
    if (text.trim().isEmpty) {
      throw const FormatException('Feedback text is required');
    }
    final origin = originQaFindingId;
    if (origin != null && origin.trim().isEmpty) {
      throw const FormatException('Feedback origin QA finding id must not be blank');
    }
    if (createdRound < 1) {
      throw const FormatException('Feedback created round must be positive');
    }
    if (!target.isValidForScope(scope)) {
      throw const FormatException('Feedback target is not valid for scope');
    }
    if (this.history.isEmpty) {
      throw const FormatException('Feedback history is required');
    }
    if (this.history.first.type != FeedbackEventType.created) {
      throw const FormatException('Feedback history must start with a created event');
    }
    _validateHistoryTransitions(this.history);
    if (feedbackStatusForHistory(this.history) != status) {
      throw const FormatException('Feedback status does not match its history');
    }
    final resolved = resolvedRound;
    if (resolved != null && resolved < 1) {
      throw const FormatException('Feedback resolved round must be positive');
    }
    if (resolved != null && resolved < createdRound) {
      throw const FormatException('Feedback resolved round must not precede creation');
    }
    if (status == FeedbackStatus.resolved && resolved == null) {
      throw const FormatException('Resolved feedback requires a resolved round');
    }
    if (status != FeedbackStatus.resolved && resolved != null) {
      throw const FormatException('Unresolved feedback must not carry a resolved round');
    }
    if (visualAttachment != null && scope != FeedbackScope.visualAnnotation) {
      throw const FormatException(
        'Visual evidence is only valid for visual_annotation feedback',
      );
    }
  }

  final String id;
  final FeedbackScope scope;
  final String text;
  final FeedbackStatus status;
  final bool blocking;
  final int createdRound;
  final FeedbackTarget target;
  final List<FeedbackEvent> history;
  final int? resolvedRound;

  /// Provider-neutral visual evidence; only present for
  /// [FeedbackScope.visualAnnotation] records.
  final VisualAttachment? visualAttachment;

  /// Immutable provenance linking this record back to the automated
  /// `QAFinding` a reviewer promoted.
  ///
  /// This is provenance only: it never affects the C.4 lifecycle, blocking
  /// classification, or approval semantics. `null` for feedback the reviewer
  /// created directly.
  final String? originQaFindingId;

  factory FeedbackRecord.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String) {
      throw const FormatException('Missing feedback id');
    }
    final scopeValue = json['scope'];
    if (scopeValue is! String) {
      throw const FormatException('Missing feedback scope');
    }
    final text = json['text'];
    if (text is! String) {
      throw const FormatException('Missing feedback text');
    }
    final statusValue = json['status'];
    if (statusValue is! String) {
      throw const FormatException('Missing feedback status');
    }
    final blocking = json['blocking'];
    if (blocking is! bool) {
      throw const FormatException('Missing feedback blocking');
    }
    final createdRound = json['created_round'];
    if (createdRound is! int) {
      throw const FormatException('Missing feedback created_round');
    }
    final resolvedRound = json['resolved_round'];
    if (resolvedRound != null && resolvedRound is! int) {
      throw const FormatException('Invalid feedback resolved_round');
    }
    final rawTarget = json['target'];
    if (rawTarget is! Map || rawTarget.keys.any((key) => key is! String)) {
      throw const FormatException('Missing feedback target');
    }
    final rawHistory = json['history'];
    if (rawHistory is! List) {
      throw const FormatException('Missing feedback history');
    }
    final history = <FeedbackEvent>[];
    for (final item in rawHistory) {
      if (item is! Map || item.keys.any((key) => key is! String)) {
        throw const FormatException('Invalid feedback history event');
      }
      history.add(FeedbackEvent.fromJson(item.cast<String, dynamic>()));
    }
    final rawAttachment = json['visual_attachment'];
    VisualAttachment? visualAttachment;
    if (rawAttachment != null) {
      if (rawAttachment is! Map ||
          rawAttachment.keys.any((key) => key is! String)) {
        throw const FormatException('Invalid feedback visual attachment');
      }
      visualAttachment =
          VisualAttachment.fromJson(rawAttachment.cast<String, dynamic>());
    }
    final originQaFindingId = json['origin_qa_finding_id'];
    if (originQaFindingId != null &&
        (originQaFindingId is! String || originQaFindingId.trim().isEmpty)) {
      throw const FormatException('Invalid feedback origin QA finding id');
    }
    return FeedbackRecord(
      id: id,
      scope: feedbackScopeFromWire(scopeValue),
      text: text,
      status: feedbackStatusFromWire(statusValue),
      blocking: blocking,
      createdRound: createdRound,
      target: FeedbackTarget.fromJson(rawTarget.cast<String, dynamic>()),
      history: history,
      resolvedRound: resolvedRound as int?,
      visualAttachment: visualAttachment,
      originQaFindingId: originQaFindingId as String?,
    );
  }

  /// Deterministic canonical serialization (all eleven keys always present).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'scope': feedbackScopeToWire(scope),
      'text': text,
      'status': feedbackStatusToWire(status),
      'blocking': blocking,
      'created_round': createdRound,
      'resolved_round': resolvedRound,
      'target': target.toJson(),
      'history': [for (final event in history) event.toJson()],
      'visual_attachment': visualAttachment?.toJson(),
      'origin_qa_finding_id': originQaFindingId,
    };
  }

  /// Produces the next immutable record; pass `resolvedRound: null` to clear it.
  FeedbackRecord copyWith({
    String? id,
    FeedbackScope? scope,
    String? text,
    FeedbackStatus? status,
    bool? blocking,
    int? createdRound,
    FeedbackTarget? target,
    List<FeedbackEvent>? history,
    Object? resolvedRound = _unset,
    Object? visualAttachment = _unset,
    Object? originQaFindingId = _unset,
  }) {
    return FeedbackRecord(
      id: id ?? this.id,
      scope: scope ?? this.scope,
      text: text ?? this.text,
      status: status ?? this.status,
      blocking: blocking ?? this.blocking,
      createdRound: createdRound ?? this.createdRound,
      target: target ?? this.target,
      history: history ?? this.history,
      resolvedRound: identical(resolvedRound, _unset)
          ? this.resolvedRound
          : resolvedRound as int?,
      visualAttachment: identical(visualAttachment, _unset)
          ? this.visualAttachment
          : visualAttachment as VisualAttachment?,
      originQaFindingId: identical(originQaFindingId, _unset)
          ? this.originQaFindingId
          : originQaFindingId as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FeedbackRecord) return false;
    if (other.id != id ||
        other.scope != scope ||
        other.text != text ||
        other.status != status ||
        other.blocking != blocking ||
        other.createdRound != createdRound ||
        other.resolvedRound != resolvedRound ||
        other.target != target ||
        other.visualAttachment != visualAttachment ||
        other.originQaFindingId != originQaFindingId) {
      return false;
    }
    return _historyEquals(other.history, history);
  }

  @override
  int get hashCode => Object.hash(
        id,
        scope,
        text,
        status,
        blocking,
        createdRound,
        resolvedRound,
        target,
        Object.hashAll(history),
        visualAttachment,
        originQaFindingId,
      );
}

bool _historyEquals(List<FeedbackEvent> a, List<FeedbackEvent> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
