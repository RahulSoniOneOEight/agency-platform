/// QA run records and targeted re-check planning.
///
/// A [QaRun] is the durable, reproducible record of one QA execution: exactly
/// which captures, baselines, checks, and findings it covered, at which source
/// commit. [affectedCaptureJobs] narrows a re-check to the surfaces a refinement
/// actually touched instead of re-capturing every permutation.
library;

/// Which governed capture surface a job belongs to.
enum QaSurfaceRef { prototype, widgetbook }

String qaSurfaceRefToWire(QaSurfaceRef value) => switch (value) {
      QaSurfaceRef.prototype => 'prototype',
      QaSurfaceRef.widgetbook => 'widgetbook',
    };

QaSurfaceRef qaSurfaceRefFromWire(String value) => switch (value) {
      'prototype' => QaSurfaceRef.prototype,
      'widgetbook' => QaSurfaceRef.widgetbook,
      _ => throw FormatException('Unknown QA surface: $value'),
    };

/// The kind of check a [QaCheckResult] records.
enum QaCheckKind { capture, golden, visualAi }

String qaCheckKindToWire(QaCheckKind value) => switch (value) {
      QaCheckKind.capture => 'capture',
      QaCheckKind.golden => 'golden',
      QaCheckKind.visualAi => 'visual_ai',
    };

QaCheckKind qaCheckKindFromWire(String value) => switch (value) {
      'capture' => QaCheckKind.capture,
      'golden' => QaCheckKind.golden,
      'visual_ai' => QaCheckKind.visualAi,
      _ => throw FormatException('Unknown QA check kind: $value'),
    };

/// One deterministic or provider-backed check performed in a QA run.
final class QaCheckResult {
  const QaCheckResult({
    required this.name,
    required this.kind,
    required this.passed,
    this.detail,
  });

  final String name;
  final QaCheckKind kind;
  final bool passed;
  final String? detail;

  factory QaCheckResult.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final kind = json['kind'];
    final passed = json['passed'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('QA check requires a name');
    }
    if (kind is! String) {
      throw const FormatException('QA check requires a kind');
    }
    if (passed is! bool) {
      throw const FormatException('QA check requires a passed flag');
    }
    final detail = json['detail'];
    if (detail != null && (detail is! String || detail.trim().isEmpty)) {
      throw const FormatException('QA check detail must be a string');
    }
    return QaCheckResult(
      name: name,
      kind: qaCheckKindFromWire(kind),
      passed: passed,
      detail: detail as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': qaCheckKindToWire(kind),
        'passed': passed,
        if (detail != null) 'detail': detail,
      };

  @override
  bool operator ==(Object other) =>
      other is QaCheckResult &&
      other.name == name &&
      other.kind == kind &&
      other.passed == passed &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(name, kind, passed, detail);
}

/// A normalized governed capture job, as planned for a QA run.
final class QaCaptureJob {
  const QaCaptureJob({
    required this.captureId,
    required this.clientId,
    required this.surface,
    required this.state,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.fixtureVersion,
    this.screen,
    this.story,
    this.direction,
    this.mixRef,
  });

  final String captureId;
  final String clientId;
  final QaSurfaceRef surface;
  final String state;
  final int viewportWidth;
  final int viewportHeight;
  final String fixtureVersion;
  final String? screen;
  final String? story;
  final String? direction;
  final String? mixRef;

  /// The governed identity a change is expressed against (screen or story).
  String? get governedTarget => screen ?? story;
}

/// Returns the capture jobs affected by a change to [changedScreens].
///
/// A job is affected when its governed screen (or Widgetbook story) is named.
/// An empty [changedScreens] means nothing was identified as changed, so nothing
/// is re-captured — a targeted re-check never falls back to every permutation.
List<QaCaptureJob> affectedCaptureJobs({
  required List<QaCaptureJob> jobs,
  required Set<String> changedScreens,
}) {
  if (changedScreens.isEmpty) {
    return const <QaCaptureJob>[];
  }
  return <QaCaptureJob>[
    for (final job in jobs)
      if (job.governedTarget != null && changedScreens.contains(job.governedTarget))
        job,
  ];
}

/// Immutable record of one QA execution.
final class QaRun {
  QaRun({
    required this.id,
    required this.clientId,
    required this.sourceCommitSha,
    required this.actorId,
    required this.startedAt,
    List<String> captureIds = const [],
    List<String> baselineIds = const [],
    List<QaCheckResult> checks = const [],
    List<String> findingIds = const [],
    this.completedAt,
    this.refinementBatchId,
  })  : captureIds = List<String>.unmodifiable(captureIds),
        baselineIds = List<String>.unmodifiable(baselineIds),
        checks = List<QaCheckResult>.unmodifiable(checks),
        findingIds = List<String>.unmodifiable(findingIds) {
    if (id.trim().isEmpty) {
      throw const FormatException('QA run id is required');
    }
    if (clientId.trim().isEmpty) {
      throw const FormatException('QA run client id is required');
    }
    if (sourceCommitSha.trim().isEmpty) {
      throw const FormatException('QA run source commit is required');
    }
    if (actorId.trim().isEmpty) {
      throw const FormatException('QA run actor is required');
    }
    final batchId = refinementBatchId;
    if (batchId != null && batchId.trim().isEmpty) {
      throw const FormatException('QA run refinement batch id must not be blank');
    }
  }

  final String id;
  final String clientId;
  final String sourceCommitSha;
  final String actorId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String? refinementBatchId;
  final List<String> captureIds;
  final List<String> baselineIds;
  final List<QaCheckResult> checks;
  final List<String> findingIds;

  /// Whether every recorded check passed. A run with no checks is not passing.
  bool get passed => checks.isNotEmpty && checks.every((check) => check.passed);

  factory QaRun.fromJson(Map<String, dynamic> json) {
    String require(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('QA run requires $key');
      }
      return value;
    }

    List<String> stringList(String key) {
      final value = json[key] ?? const [];
      if (value is! List || value.any((item) => item is! String)) {
        throw FormatException('QA run $key must be a list of strings');
      }
      return value.cast<String>();
    }

    DateTime parseTime(String key) {
      final value = json[key];
      if (value is! String) {
        throw FormatException('QA run requires $key');
      }
      final parsed = DateTime.tryParse(value);
      if (parsed == null) {
        throw FormatException('QA run $key is not a timestamp');
      }
      return parsed;
    }

    final rawChecks = json['checks'];
    if (rawChecks is! List) {
      throw const FormatException('QA run requires checks');
    }
    final checks = <QaCheckResult>[];
    for (final item in rawChecks) {
      if (item is! Map || item.keys.any((key) => key is! String)) {
        throw const FormatException('QA run check must be an object');
      }
      checks.add(QaCheckResult.fromJson(item.cast<String, dynamic>()));
    }

    final completedAt = json['completed_at'];
    if (completedAt != null && completedAt is! String) {
      throw const FormatException('QA run completed_at must be a timestamp');
    }
    final refinementBatchId = json['refinement_batch_id'];
    if (refinementBatchId != null &&
        (refinementBatchId is! String || refinementBatchId.trim().isEmpty)) {
      throw const FormatException('QA run refinement batch id is invalid');
    }

    return QaRun(
      id: require('id'),
      clientId: require('client_id'),
      sourceCommitSha: require('source_commit_sha'),
      actorId: require('actor_id'),
      startedAt: parseTime('started_at'),
      completedAt: completedAt == null ? null : DateTime.parse(completedAt as String),
      refinementBatchId: refinementBatchId as String?,
      captureIds: stringList('capture_ids'),
      baselineIds: stringList('baseline_ids'),
      checks: checks,
      findingIds: stringList('finding_ids'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'client_id': clientId,
        'source_commit_sha': sourceCommitSha,
        'actor_id': actorId,
        'started_at': startedAt.toUtc().toIso8601String(),
        'completed_at': completedAt?.toUtc().toIso8601String(),
        'refinement_batch_id': refinementBatchId,
        'capture_ids': captureIds,
        'baseline_ids': baselineIds,
        'checks': [for (final check in checks) check.toJson()],
        'finding_ids': findingIds,
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! QaRun) return false;
    if (other.id != id ||
        other.clientId != clientId ||
        other.sourceCommitSha != sourceCommitSha ||
        other.actorId != actorId ||
        other.startedAt.toUtc() != startedAt.toUtc() ||
        other.completedAt?.toUtc() != completedAt?.toUtc() ||
        other.refinementBatchId != refinementBatchId) {
      return false;
    }
    return _listEquals(other.captureIds, captureIds) &&
        _listEquals(other.baselineIds, baselineIds) &&
        _listEquals(other.findingIds, findingIds) &&
        _listEquals(other.checks, checks);
  }

  @override
  int get hashCode => Object.hash(
        id,
        clientId,
        sourceCommitSha,
        actorId,
        startedAt.toUtc(),
        completedAt?.toUtc(),
        refinementBatchId,
        Object.hashAll(captureIds),
        Object.hashAll(baselineIds),
        Object.hashAll(checks),
        Object.hashAll(findingIds),
      );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
