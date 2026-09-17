/// Automated visual-QA finding domain.
///
/// A [QaFinding] is the **sole** automated-QA finding authority. It is produced
/// by deterministic checks (golden comparison) or by a provider-neutral Visual
/// AI review, and it may only become authoritative human-review state through an
/// explicit reviewer promotion in `QaCoordinator` — never directly.
///
/// Invariants enforced here:
/// - findings are immutable value objects with an **append-only** history;
/// - every finding carries concrete provenance (`screenshotRef`,
///   `sourceCommitSha`, `ruleSource`, `ruleRef`) and a stable `dedupeKey`;
/// - [QaSeverity] is QA impact only and never implies C.4 blocking;
/// - the comparison authority hierarchy is explicit and cannot be inverted.
library;

import 'qa_domain_error.dart';

/// Lifecycle state of an automated QA finding.
enum QaFindingStatus { detected, triaged, promoted, dismissed, acceptedRisk }

/// QA impact of a finding. Never a C.4 blocking classification.
enum QaSeverity { info, minor, major, blocker }

/// Which review surface produced the capture behind a finding.
enum QaSurface { prototype, widgetbook }

/// Where a finding's rule came from, in descending authority.
///
/// The declaration order **is** the authority hierarchy: an approved experience
/// decision outranks the design contract, which outranks an accepted baseline,
/// which outranks an explicitly linked reference, which outranks general
/// visual-quality heuristics. A lower layer may never override a higher one.
enum QaRuleSource {
  approvedExperience,
  designContract,
  acceptedBaseline,
  linkedReference,
  visualHeuristic;

  /// Ordered highest-authority first.
  static const List<QaRuleSource> byAuthority = [
    QaRuleSource.approvedExperience,
    QaRuleSource.designContract,
    QaRuleSource.acceptedBaseline,
    QaRuleSource.linkedReference,
    QaRuleSource.visualHeuristic,
  ];

  /// 0 = highest authority.
  int get authorityRank => byAuthority.indexOf(this);

  /// Whether this source carries strictly more authority than [other].
  bool outranks(QaRuleSource other) => authorityRank < other.authorityRank;
}

/// Append-only lifecycle/evidence events recorded on a finding.
enum QaFindingEventType {
  detected,
  triaged,
  promoted,
  dismissed,
  acceptedRisk,
  recurrence,
  evidenceLinked,
  noLongerReproducible,
}

String qaFindingStatusToWire(QaFindingStatus value) => switch (value) {
      QaFindingStatus.detected => 'detected',
      QaFindingStatus.triaged => 'triaged',
      QaFindingStatus.promoted => 'promoted',
      QaFindingStatus.dismissed => 'dismissed',
      QaFindingStatus.acceptedRisk => 'accepted_risk',
    };

QaFindingStatus qaFindingStatusFromWire(String value) => switch (value) {
      'detected' => QaFindingStatus.detected,
      'triaged' => QaFindingStatus.triaged,
      'promoted' => QaFindingStatus.promoted,
      'dismissed' => QaFindingStatus.dismissed,
      'accepted_risk' => QaFindingStatus.acceptedRisk,
      _ => throw InvalidQaFinding('unknown QA finding status: $value'),
    };

String qaSeverityToWire(QaSeverity value) => switch (value) {
      QaSeverity.info => 'info',
      QaSeverity.minor => 'minor',
      QaSeverity.major => 'major',
      QaSeverity.blocker => 'blocker',
    };

QaSeverity qaSeverityFromWire(String value) => switch (value) {
      'info' => QaSeverity.info,
      'minor' => QaSeverity.minor,
      'major' => QaSeverity.major,
      'blocker' => QaSeverity.blocker,
      _ => throw InvalidQaFinding('unknown QA severity: $value'),
    };

String qaSurfaceToWire(QaSurface value) => switch (value) {
      QaSurface.prototype => 'prototype',
      QaSurface.widgetbook => 'widgetbook',
    };

QaSurface qaSurfaceFromWire(String value) => switch (value) {
      'prototype' => QaSurface.prototype,
      'widgetbook' => QaSurface.widgetbook,
      _ => throw InvalidQaFinding('unknown QA surface: $value'),
    };

String qaRuleSourceToWire(QaRuleSource value) => switch (value) {
      QaRuleSource.approvedExperience => 'approved_experience',
      QaRuleSource.designContract => 'design_contract',
      QaRuleSource.acceptedBaseline => 'accepted_baseline',
      QaRuleSource.linkedReference => 'linked_reference',
      QaRuleSource.visualHeuristic => 'visual_heuristic',
    };

QaRuleSource qaRuleSourceFromWire(String value) => switch (value) {
      'approved_experience' => QaRuleSource.approvedExperience,
      'design_contract' => QaRuleSource.designContract,
      'accepted_baseline' => QaRuleSource.acceptedBaseline,
      'linked_reference' => QaRuleSource.linkedReference,
      'visual_heuristic' => QaRuleSource.visualHeuristic,
      _ => throw InvalidQaFinding('unknown QA rule source: $value'),
    };

String qaFindingEventTypeToWire(QaFindingEventType value) => switch (value) {
      QaFindingEventType.detected => 'detected',
      QaFindingEventType.triaged => 'triaged',
      QaFindingEventType.promoted => 'promoted',
      QaFindingEventType.dismissed => 'dismissed',
      QaFindingEventType.acceptedRisk => 'accepted_risk',
      QaFindingEventType.recurrence => 'recurrence',
      QaFindingEventType.evidenceLinked => 'evidence_linked',
      QaFindingEventType.noLongerReproducible => 'no_longer_reproducible',
    };

QaFindingEventType qaFindingEventTypeFromWire(String value) => switch (value) {
      'detected' => QaFindingEventType.detected,
      'triaged' => QaFindingEventType.triaged,
      'promoted' => QaFindingEventType.promoted,
      'dismissed' => QaFindingEventType.dismissed,
      'accepted_risk' => QaFindingEventType.acceptedRisk,
      'recurrence' => QaFindingEventType.recurrence,
      'evidence_linked' => QaFindingEventType.evidenceLinked,
      'no_longer_reproducible' => QaFindingEventType.noLongerReproducible,
      _ => throw InvalidQaFinding('unknown QA finding event: $value'),
    };

/// A normalized evidence region inside a screenshot.
///
/// Coordinates are fractions of the capture (0..1) so a region stays meaningful
/// across viewports; `x + width <= 1` and `y + height <= 1` are enforced.
final class QaRegion {
  QaRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  }) {
    final values = [x, y, width, height];
    if (values.any((value) => value.isNaN || value.isInfinite)) {
      throw const InvalidQaRegion('region coordinates must be finite');
    }
    if (width <= 0 || height <= 0) {
      throw const InvalidQaRegion('region width and height must be positive');
    }
    if (x < 0 || y < 0 || x + width > 1.0000001 || y + height > 1.0000001) {
      throw const InvalidQaRegion('region must lie inside the unit square');
    }
  }

  final double x;
  final double y;
  final double width;
  final double height;

  bool get isNormalized =>
      x >= 0 &&
      y >= 0 &&
      width > 0 &&
      height > 0 &&
      x + width <= 1.0000001 &&
      y + height <= 1.0000001;

  /// Fixed-precision canonical form used by the dedupe key.
  String get canonical =>
      '${x.toStringAsFixed(4)},${y.toStringAsFixed(4)},'
      '${width.toStringAsFixed(4)},${height.toStringAsFixed(4)}';

  factory QaRegion.fromJson(Map<String, dynamic> json) {
    double read(String key) {
      final value = json[key];
      if (value is num) return value.toDouble();
      throw InvalidQaRegion('region $key must be numeric');
    }

    return QaRegion(
      x: read('x'),
      y: read('y'),
      width: read('width'),
      height: read('height'),
    );
  }

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  @override
  bool operator ==(Object other) =>
      other is QaRegion &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'QaRegion($canonical)';
}

/// One piece of evidence supporting a finding.
///
/// At least one of [region], [ref], or [note] must be present; an evidence entry
/// with no content is rejected by [QaFinding].
final class QaEvidence {
  QaEvidence({this.region, this.ref, this.note}) {
    if (!hasContent) {
      throw const InvalidQaEvidence(
        'evidence requires a region, reference, or note',
      );
    }
  }

  final QaRegion? region;
  final String? ref;
  final String? note;

  bool get hasContent =>
      region != null ||
      (ref != null && ref!.trim().isNotEmpty) ||
      (note != null && note!.trim().isNotEmpty);

  factory QaEvidence.fromJson(Map<String, dynamic> json) {
    final rawRegion = json['region'];
    QaRegion? region;
    if (rawRegion != null) {
      if (rawRegion is! Map || rawRegion.keys.any((key) => key is! String)) {
        throw const InvalidQaEvidence('evidence region must be an object');
      }
      region = QaRegion.fromJson(rawRegion.cast<String, dynamic>());
    }
    String? readOptional(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String || value.trim().isEmpty) {
        throw InvalidQaEvidence('evidence $key must be a non-empty string');
      }
      return value;
    }

    return QaEvidence(
      region: region,
      ref: readOptional('ref'),
      note: readOptional('note'),
    );
  }

  Map<String, dynamic> toJson() => {
        if (region != null) 'region': region!.toJson(),
        if (ref != null) 'ref': ref,
        if (note != null) 'note': note,
      };

  @override
  bool operator ==(Object other) =>
      other is QaEvidence &&
      other.region == region &&
      other.ref == ref &&
      other.note == note;

  @override
  int get hashCode => Object.hash(region, ref, note);
}

/// One append-only event on a [QaFinding].
final class QaFindingEvent {
  const QaFindingEvent({
    required this.event,
    required this.actorId,
    required this.at,
    this.reason,
    this.feedbackId,
    this.runId,
    this.evidenceRef,
  });

  final QaFindingEventType event;
  final String actorId;
  final DateTime at;
  final String? reason;
  final String? feedbackId;
  final String? runId;
  final String? evidenceRef;

  factory QaFindingEvent.fromJson(Map<String, dynamic> json) {
    final event = json['event'];
    if (event is! String) {
      throw const InvalidQaFinding('missing QA finding event type');
    }
    final actorId = json['actor_id'];
    if (actorId is! String || actorId.trim().isEmpty) {
      throw const InvalidQaFinding('missing QA finding event actor');
    }
    final at = json['at'];
    if (at is! String) {
      throw const InvalidQaFinding('missing QA finding event timestamp');
    }
    final DateTime parsed;
    try {
      parsed = DateTime.parse(at);
    } on FormatException {
      throw const InvalidQaFinding('invalid QA finding event timestamp');
    }
    String? optional(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String || value.trim().isEmpty) {
        throw InvalidQaFinding('QA finding event $key must be a string');
      }
      return value;
    }

    return QaFindingEvent(
      event: qaFindingEventTypeFromWire(event),
      actorId: actorId,
      at: parsed,
      reason: optional('reason'),
      feedbackId: optional('feedback_id'),
      runId: optional('run_id'),
      evidenceRef: optional('evidence_ref'),
    );
  }

  Map<String, dynamic> toJson() => {
        'event': qaFindingEventTypeToWire(event),
        'actor_id': actorId,
        'at': at.toUtc().toIso8601String(),
        if (reason != null) 'reason': reason,
        if (feedbackId != null) 'feedback_id': feedbackId,
        if (runId != null) 'run_id': runId,
        if (evidenceRef != null) 'evidence_ref': evidenceRef,
      };

  @override
  bool operator ==(Object other) =>
      other is QaFindingEvent &&
      other.event == event &&
      other.actorId == actorId &&
      other.at.toUtc() == at.toUtc() &&
      other.reason == reason &&
      other.feedbackId == feedbackId &&
      other.runId == runId &&
      other.evidenceRef == evidenceRef;

  @override
  int get hashCode => Object.hash(
        event,
        actorId,
        at.toUtc().microsecondsSinceEpoch,
        reason,
        feedbackId,
        runId,
        evidenceRef,
      );
}

/// The lifecycle status implied by an append-only event history.
QaFindingStatus qaStatusForHistory(List<QaFindingEvent> history) {
  var status = QaFindingStatus.detected;
  for (final event in history) {
    switch (event.event) {
      case QaFindingEventType.detected:
        status = QaFindingStatus.detected;
      case QaFindingEventType.triaged:
        status = QaFindingStatus.triaged;
      case QaFindingEventType.promoted:
        status = QaFindingStatus.promoted;
      case QaFindingEventType.dismissed:
        status = QaFindingStatus.dismissed;
      case QaFindingEventType.acceptedRisk:
        status = QaFindingStatus.acceptedRisk;
      case QaFindingEventType.recurrence:
      case QaFindingEventType.evidenceLinked:
      case QaFindingEventType.noLongerReproducible:
        break;
    }
  }
  return status;
}

/// Validates that an append-only history is a legal lifecycle walk.
void _validateHistory(List<QaFindingEvent> history) {
  if (history.isEmpty) {
    throw const InvalidQaFinding('QA finding history is required');
  }
  if (history.first.event != QaFindingEventType.detected) {
    throw const InvalidQaFinding('QA finding history must start with detected');
  }
  var current = QaFindingStatus.detected;
  for (var index = 0; index < history.length; index++) {
    final event = history[index];
    switch (event.event) {
      case QaFindingEventType.detected:
        if (index != 0) {
          throw const InvalidQaFinding(
            'QA finding history must not repeat the detected event',
          );
        }
      case QaFindingEventType.triaged:
        if (current != QaFindingStatus.detected) {
          throw InvalidQaFinding('illegal QA history: triaged from ${current.name}');
        }
        current = QaFindingStatus.triaged;
      case QaFindingEventType.promoted:
        if (current != QaFindingStatus.triaged) {
          throw InvalidQaFinding('illegal QA history: promoted from ${current.name}');
        }
        current = QaFindingStatus.promoted;
      case QaFindingEventType.dismissed:
        if (current != QaFindingStatus.detected &&
            current != QaFindingStatus.triaged) {
          throw InvalidQaFinding('illegal QA history: dismissed from ${current.name}');
        }
        current = QaFindingStatus.dismissed;
      case QaFindingEventType.acceptedRisk:
        if (current != QaFindingStatus.detected &&
            current != QaFindingStatus.triaged) {
          throw InvalidQaFinding(
            'illegal QA history: accepted_risk from ${current.name}',
          );
        }
        current = QaFindingStatus.acceptedRisk;
      case QaFindingEventType.recurrence:
      case QaFindingEventType.evidenceLinked:
      case QaFindingEventType.noLongerReproducible:
        break;
    }
  }
}

/// Computes the stable deduplication identity of a finding.
///
/// Derived only from the fields that identify *the same issue* — client,
/// surface, screen/story, rule source/ref, category, governed section or
/// normalized region, and active baseline/reference. Severity, confidence,
/// summary, evidence, and source commit are deliberately excluded so a
/// rediscovered issue links to the existing finding instead of duplicating it.
String computeQaDedupeKey({
  required String clientId,
  required QaSurface surface,
  String? screen,
  String? story,
  required QaRuleSource ruleSource,
  required String ruleRef,
  required String category,
  String? section,
  QaRegion? region,
  String? baselineRef,
}) {
  final scope = screen ?? story ?? '';
  return [
    'qa-dedupe:v1',
    clientId,
    qaSurfaceToWire(surface),
    scope,
    qaRuleSourceToWire(ruleSource),
    ruleRef,
    category,
    section ?? '',
    region?.canonical ?? '',
    baselineRef ?? '',
  ].join('|');
}

/// Immutable automated-QA finding with an append-only lifecycle.
final class QaFinding {
  QaFinding({
    required this.id,
    required this.clientId,
    required this.status,
    required this.severity,
    required this.category,
    required this.surface,
    this.screen,
    this.story,
    required this.state,
    this.direction,
    this.mixRef,
    this.section,
    this.region,
    required this.screenshotRef,
    required this.sourceCommitSha,
    required this.ruleSource,
    required this.ruleRef,
    this.baselineRef,
    required this.summary,
    required List<QaEvidence> evidence,
    this.confidence,
    required this.dedupeKey,
    this.feedbackId,
    required List<QaFindingEvent> history,
    required this.noLongerReproducible,
    required this.recurrences,
  })  : evidence = List<QaEvidence>.unmodifiable(evidence),
        history = List<QaFindingEvent>.unmodifiable(history) {
    void require(String label, String? value) {
      if (value == null || value.trim().isEmpty) {
        throw InvalidQaFinding('QA finding requires $label');
      }
    }

    require('id', id);
    require('client_id', clientId);
    require('category', category);
    require('state', state);
    require('screenshot_ref', screenshotRef);
    require('source_commit_sha', sourceCommitSha);
    require('rule_ref', ruleRef);
    require('summary', summary);
    require('dedupe_key', dedupeKey);
    if (surface == QaSurface.prototype) {
      require('screen', screen);
    } else {
      require('story', story);
      if (screen != null) {
        throw const InvalidQaFinding('widgetbook findings must not carry a screen');
      }
    }
    final confidenceValue = confidence;
    if (confidenceValue != null &&
        (confidenceValue.isNaN ||
            confidenceValue.isInfinite ||
            confidenceValue < 0 ||
            confidenceValue > 1)) {
      throw const InvalidQaFinding('QA finding confidence must be within [0, 1]');
    }
    for (final item in this.evidence) {
      if (!item.hasContent) {
        throw const InvalidQaEvidence(
          'evidence requires a region, reference, or note',
        );
      }
    }
    _validateHistory(this.history);
    if (qaStatusForHistory(this.history) != status) {
      throw const InvalidQaFinding('QA finding status does not match its history');
    }
    final derivedFeedbackId = this
        .history
        .where((event) => event.event == QaFindingEventType.promoted)
        .map((event) => event.feedbackId)
        .lastOrNull;
    if (status == QaFindingStatus.promoted) {
      require('feedback_id', feedbackId);
      if (derivedFeedbackId != feedbackId) {
        throw const InvalidQaFinding(
          'promoted QA finding must match its promoted event',
        );
      }
    } else if (feedbackId != null) {
      throw const InvalidQaFinding(
        'only promoted QA findings may reference a feedback record',
      );
    }
    final expectedKey = computeQaDedupeKey(
      clientId: clientId,
      surface: surface,
      screen: screen,
      story: story,
      ruleSource: ruleSource,
      ruleRef: ruleRef,
      category: category,
      section: section,
      region: region,
      baselineRef: baselineRef,
    );
    if (dedupeKey != expectedKey) {
      throw const InvalidQaFinding('QA finding dedupe key is not reproducible');
    }
    final derivedNoLonger = _deriveNoLongerReproducible(this.history);
    if (derivedNoLonger != noLongerReproducible) {
      throw const InvalidQaFinding(
        'QA finding no-longer-reproducible flag does not match its history',
      );
    }
    final derivedRecurrences = this
        .history
        .where((event) => event.event == QaFindingEventType.recurrence)
        .length;
    if (derivedRecurrences != recurrences) {
      throw const InvalidQaFinding(
        'QA finding recurrence count does not match its history',
      );
    }
  }

  final String id;
  final String clientId;
  final QaFindingStatus status;
  final QaSeverity severity;
  final String category;
  final QaSurface surface;
  final String? screen;
  final String? story;
  final String state;
  final String? direction;
  final String? mixRef;
  final String? section;
  final QaRegion? region;
  final String screenshotRef;
  final String sourceCommitSha;
  final QaRuleSource ruleSource;
  final String ruleRef;
  final String? baselineRef;
  final String summary;
  final List<QaEvidence> evidence;
  final double? confidence;

  /// Stable deduplication identity; see [computeQaDedupeKey].
  final String dedupeKey;

  /// The `FeedbackRecord` id produced by reviewer promotion, if any.
  final String? feedbackId;
  final List<QaFindingEvent> history;

  /// Whether a later QA run could no longer reproduce this finding.
  final bool noLongerReproducible;

  /// How many times the issue was rediscovered after a successful recheck.
  final int recurrences;

  /// Always `null`: QA severity never carries a C.4 blocking classification.
  ///
  /// Blocking is owned by the reviewer and lives on the promoted
  /// `FeedbackRecord`; exposing this as a nullable no-op makes it impossible for
  /// callers to treat automated severity as review blocking.
  bool? get blocking => null;

  bool get isPromoted => status == QaFindingStatus.promoted;

  bool get isTerminal =>
      status == QaFindingStatus.promoted ||
      status == QaFindingStatus.dismissed ||
      status == QaFindingStatus.acceptedRisk;

  bool get canPromote =>
      status == QaFindingStatus.triaged && feedbackId == null;

  bool get isNoLongerReproducible => noLongerReproducible;

  /// Creates the initial `detected` finding produced by a QA check.
  factory QaFinding.detected({
    required String id,
    required String clientId,
    required QaSeverity severity,
    required String category,
    required QaSurface surface,
    String? screen,
    String? story,
    required String state,
    String? direction,
    String? mixRef,
    String? section,
    QaRegion? region,
    required String screenshotRef,
    required String sourceCommitSha,
    required QaRuleSource ruleSource,
    required String ruleRef,
    String? baselineRef,
    required String summary,
    List<QaEvidence> evidence = const [],
    double? confidence,
    required String actorId,
    required DateTime at,
  }) {
    final dedupeKey = computeQaDedupeKey(
      clientId: clientId,
      surface: surface,
      screen: screen,
      story: story,
      ruleSource: ruleSource,
      ruleRef: ruleRef,
      category: category,
      section: section,
      region: region,
      baselineRef: baselineRef,
    );
    return QaFinding(
      id: id,
      clientId: clientId,
      status: QaFindingStatus.detected,
      severity: severity,
      category: category,
      surface: surface,
      screen: screen,
      story: story,
      state: state,
      direction: direction,
      mixRef: mixRef,
      section: section,
      region: region,
      screenshotRef: screenshotRef,
      sourceCommitSha: sourceCommitSha,
      ruleSource: ruleSource,
      ruleRef: ruleRef,
      baselineRef: baselineRef,
      summary: summary,
      evidence: evidence,
      confidence: confidence,
      dedupeKey: dedupeKey,
      history: [
        QaFindingEvent(
          event: QaFindingEventType.detected,
          actorId: actorId,
          at: at,
        ),
      ],
      noLongerReproducible: false,
      recurrences: 0,
    );
  }

  factory QaFinding.fromJson(Map<String, dynamic> json) {
    String require(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw InvalidQaFinding('missing QA finding $key');
      }
      return value;
    }

    String? optional(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String || value.trim().isEmpty) {
        throw InvalidQaFinding('QA finding $key must be a string');
      }
      return value;
    }

    final rawRegion = json['region'];
    QaRegion? region;
    if (rawRegion != null) {
      if (rawRegion is! Map || rawRegion.keys.any((key) => key is! String)) {
        throw const InvalidQaFinding('QA finding region must be an object');
      }
      region = QaRegion.fromJson(rawRegion.cast<String, dynamic>());
    }

    final rawEvidence = json['evidence'];
    if (rawEvidence is! List) {
      throw const InvalidQaFinding('missing QA finding evidence');
    }
    final evidence = <QaEvidence>[];
    for (final item in rawEvidence) {
      if (item is! Map || item.keys.any((key) => key is! String)) {
        throw const InvalidQaFinding('invalid QA finding evidence entry');
      }
      evidence.add(QaEvidence.fromJson(item.cast<String, dynamic>()));
    }

    final rawHistory = json['history'];
    if (rawHistory is! List) {
      throw const InvalidQaFinding('missing QA finding history');
    }
    final history = <QaFindingEvent>[];
    for (final item in rawHistory) {
      if (item is! Map || item.keys.any((key) => key is! String)) {
        throw const InvalidQaFinding('invalid QA finding history event');
      }
      history.add(QaFindingEvent.fromJson(item.cast<String, dynamic>()));
    }

    final confidence = json['confidence'];
    if (confidence != null && confidence is! num) {
      throw const InvalidQaFinding('QA finding confidence must be numeric');
    }
    final noLonger = json['no_longer_reproducible'];
    if (noLonger is! bool) {
      throw const InvalidQaFinding('missing QA finding no_longer_reproducible');
    }
    final recurrences = json['recurrences'];
    if (recurrences is! int || recurrences < 0) {
      throw const InvalidQaFinding('missing QA finding recurrences');
    }

    return QaFinding(
      id: require('id'),
      clientId: require('client_id'),
      status: qaFindingStatusFromWire(require('status')),
      severity: qaSeverityFromWire(require('severity')),
      category: require('category'),
      surface: qaSurfaceFromWire(require('surface')),
      screen: optional('screen'),
      story: optional('story'),
      state: require('state'),
      direction: optional('direction'),
      mixRef: optional('mix_ref'),
      section: optional('section'),
      region: region,
      screenshotRef: require('screenshot_ref'),
      sourceCommitSha: require('source_commit_sha'),
      ruleSource: qaRuleSourceFromWire(require('rule_source')),
      ruleRef: require('rule_ref'),
      baselineRef: optional('baseline_ref'),
      summary: require('summary'),
      evidence: evidence,
      confidence: confidence == null ? null : (confidence as num).toDouble(),
      dedupeKey: require('dedupe_key'),
      feedbackId: optional('feedback_id'),
      history: history,
      noLongerReproducible: noLonger,
      recurrences: recurrences,
    );
  }

  /// Deterministic canonical serialization; every key is always present.
  Map<String, dynamic> toJson() => {
        'id': id,
        'client_id': clientId,
        'status': qaFindingStatusToWire(status),
        'severity': qaSeverityToWire(severity),
        'category': category,
        'surface': qaSurfaceToWire(surface),
        'screen': screen,
        'story': story,
        'state': state,
        'direction': direction,
        'mix_ref': mixRef,
        'section': section,
        'region': region?.toJson(),
        'screenshot_ref': screenshotRef,
        'source_commit_sha': sourceCommitSha,
        'rule_source': qaRuleSourceToWire(ruleSource),
        'rule_ref': ruleRef,
        'baseline_ref': baselineRef,
        'summary': summary,
        'evidence': [for (final item in evidence) item.toJson()],
        'confidence': confidence,
        'dedupe_key': dedupeKey,
        'feedback_id': feedbackId,
        'no_longer_reproducible': noLongerReproducible,
        'recurrences': recurrences,
        'history': [for (final event in history) event.toJson()],
      };

  /// Records reviewer triage. Identity and provenance are never altered.
  QaFinding triage({required String actorId, required DateTime at}) {
    if (status != QaFindingStatus.detected) {
      throw InvalidQaTransition('cannot triage ${status.name} QA finding');
    }
    return _derive([
      ...history,
      QaFindingEvent(
        event: QaFindingEventType.triaged,
        actorId: actorId,
        at: at,
      ),
    ]);
  }

  /// Promotes the finding into human review, linking the created feedback id.
  QaFinding promote({
    required String actorId,
    required DateTime at,
    required String feedbackId,
  }) {
    if (status != QaFindingStatus.triaged) {
      throw InvalidQaTransition('cannot promote ${status.name} QA finding');
    }
    final link = feedbackId.trim();
    if (link.isEmpty) {
      throw const QaEvidenceMissing(
        'promotion requires the created feedback record id',
      );
    }
    return _derive([
      ...history,
      QaFindingEvent(
        event: QaFindingEventType.promoted,
        actorId: actorId,
        at: at,
        feedbackId: link,
      ),
    ]);
  }

  /// Dismisses the finding as not actionable.
  QaFinding dismiss({
    required String actorId,
    required DateTime at,
    required String reason,
  }) {
    if (status != QaFindingStatus.detected &&
        status != QaFindingStatus.triaged) {
      throw InvalidQaTransition('cannot dismiss ${status.name} QA finding');
    }
    final text = reason.trim();
    if (text.isEmpty) {
      throw const QaEvidenceMissing('dismissal requires a reason');
    }
    return _derive([
      ...history,
      QaFindingEvent(
        event: QaFindingEventType.dismissed,
        actorId: actorId,
        at: at,
        reason: text,
      ),
    ]);
  }

  /// Accepts the finding as a known, intentional risk.
  QaFinding acceptRisk({
    required String actorId,
    required DateTime at,
    required String reason,
  }) {
    if (status != QaFindingStatus.detected &&
        status != QaFindingStatus.triaged) {
      throw InvalidQaTransition('cannot accept risk on ${status.name} QA finding');
    }
    final text = reason.trim();
    if (text.isEmpty) {
      throw const QaEvidenceMissing('accepting risk requires a reason');
    }
    return _derive([
      ...history,
      QaFindingEvent(
        event: QaFindingEventType.acceptedRisk,
        actorId: actorId,
        at: at,
        reason: text,
      ),
    ]);
  }

  /// Links additional QA evidence without changing the finding's status.
  QaFinding linkEvidence({
    required String actorId,
    required DateTime at,
    required List<QaEvidence> evidence,
    String? runId,
  }) {
    if (evidence.isEmpty) {
      throw const QaEvidenceMissing('linking evidence requires at least one entry');
    }
    return _derive(
      [
        ...history,
        QaFindingEvent(
          event: QaFindingEventType.evidenceLinked,
          actorId: actorId,
          at: at,
          runId: runId,
          evidenceRef: evidence.first.ref,
        ),
      ],
      evidence: [...this.evidence, ...evidence],
    );
  }

  /// Records a successful recheck that could not reproduce the finding.
  QaFinding markNoLongerReproducible({
    required String actorId,
    required DateTime at,
    String? runId,
  }) {
    return _derive([
      ...history,
      QaFindingEvent(
        event: QaFindingEventType.noLongerReproducible,
        actorId: actorId,
        at: at,
        runId: runId,
      ),
    ]);
  }

  /// Records that the issue was rediscovered after a successful recheck.
  QaFinding recordRecurrence({
    required String actorId,
    required DateTime at,
    String? runId,
    QaEvidence? evidence,
  }) {
    return _derive(
      [
        ...history,
        QaFindingEvent(
          event: QaFindingEventType.recurrence,
          actorId: actorId,
          at: at,
          runId: runId,
          evidenceRef: evidence?.ref,
        ),
      ],
      evidence: evidence == null ? this.evidence : [...this.evidence, evidence],
    );
  }

  /// Rebuilds a finding from an append-only history so derived fields can never
  /// drift from the recorded events.
  QaFinding _derive(
    List<QaFindingEvent> history, {
    List<QaEvidence>? evidence,
  }) {
    return QaFinding(
      id: id,
      clientId: clientId,
      status: qaStatusForHistory(history),
      severity: severity,
      category: category,
      surface: surface,
      screen: screen,
      story: story,
      state: state,
      direction: direction,
      mixRef: mixRef,
      section: section,
      region: region,
      screenshotRef: screenshotRef,
      sourceCommitSha: sourceCommitSha,
      ruleSource: ruleSource,
      ruleRef: ruleRef,
      baselineRef: baselineRef,
      summary: summary,
      evidence: evidence ?? this.evidence,
      confidence: confidence,
      dedupeKey: dedupeKey,
      feedbackId: history
          .where((event) => event.event == QaFindingEventType.promoted)
          .map((event) => event.feedbackId)
          .lastOrNull,
      history: history,
      noLongerReproducible: _deriveNoLongerReproducible(history),
      recurrences: history
          .where((event) => event.event == QaFindingEventType.recurrence)
          .length,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! QaFinding) return false;
    if (other.id != id ||
        other.clientId != clientId ||
        other.status != status ||
        other.severity != severity ||
        other.category != category ||
        other.surface != surface ||
        other.screen != screen ||
        other.story != story ||
        other.state != state ||
        other.direction != direction ||
        other.mixRef != mixRef ||
        other.section != section ||
        other.region != region ||
        other.screenshotRef != screenshotRef ||
        other.sourceCommitSha != sourceCommitSha ||
        other.ruleSource != ruleSource ||
        other.ruleRef != ruleRef ||
        other.baselineRef != baselineRef ||
        other.summary != summary ||
        other.confidence != confidence ||
        other.dedupeKey != dedupeKey ||
        other.feedbackId != feedbackId ||
        other.noLongerReproducible != noLongerReproducible ||
        other.recurrences != recurrences) {
      return false;
    }
    if (other.evidence.length != evidence.length ||
        other.history.length != history.length) {
      return false;
    }
    for (var index = 0; index < evidence.length; index++) {
      if (other.evidence[index] != evidence[index]) return false;
    }
    for (var index = 0; index < history.length; index++) {
      if (other.history[index] != history[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        clientId,
        status,
        severity,
        category,
        surface,
        screen,
        story,
        state,
        direction,
        mixRef,
        section,
        region,
        screenshotRef,
        sourceCommitSha,
        ruleSource,
        ruleRef,
        baselineRef,
        summary,
        confidence,
        dedupeKey,
        feedbackId,
        noLongerReproducible,
        recurrences,
        Object.hashAll(evidence),
        Object.hashAll(history),
      ]);
}

bool _deriveNoLongerReproducible(List<QaFindingEvent> history) {
  var flag = false;
  for (final event in history) {
    switch (event.event) {
      case QaFindingEventType.noLongerReproducible:
        flag = true;
      case QaFindingEventType.recurrence:
        flag = false;
      case QaFindingEventType.detected:
      case QaFindingEventType.triaged:
      case QaFindingEventType.promoted:
      case QaFindingEventType.dismissed:
      case QaFindingEventType.acceptedRisk:
      case QaFindingEventType.evidenceLinked:
        break;
    }
  }
  return flag;
}

extension _LastOrNull<T> on Iterable<T> {
  T? get lastOrNull {
    if (isEmpty) return null;
    return last;
  }
}
