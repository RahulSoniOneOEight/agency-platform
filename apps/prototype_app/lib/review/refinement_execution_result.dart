/// The exact result an OpenCode refinement execution returns to the coordinator.
///
/// OpenCode receives a frozen `ready` batch (see
/// `docs/review-refinement-opencode-contract.md`) and returns this payload. The
/// result is an input to `ReviewCoordinator.recordBatchValidation`; it never
/// mutates feedback status, review decisions, or approval history by itself.
library;

import 'refinement_batch.dart';

enum RefinementExecutionStatus { passed, failed }

String refinementExecutionStatusToWire(RefinementExecutionStatus value) =>
    switch (value) {
      RefinementExecutionStatus.passed => 'passed',
      RefinementExecutionStatus.failed => 'failed',
    };

RefinementExecutionStatus refinementExecutionStatusFromWire(String value) =>
    switch (value) {
      'passed' => RefinementExecutionStatus.passed,
      'failed' => RefinementExecutionStatus.failed,
      _ => throw FormatException('Unknown refinement execution status: $value'),
    };

/// Structured execution + validation result returned by OpenCode.
final class RefinementExecutionResult {
  RefinementExecutionResult({
    required this.status,
    required this.commitSha,
    List<String> filesChanged = const <String>[],
    List<ValidationCheck> checks = const <ValidationCheck>[],
    List<String> evidence = const <String>[],
    this.notes,
  })  : filesChanged = _normalized(filesChanged, 'changed file'),
        checks = List<ValidationCheck>.unmodifiable(checks),
        evidence = _normalized(evidence, 'evidence reference') {
    if (commitSha.trim().isEmpty) {
      throw const FormatException('Refinement execution commit SHA is required');
    }
    if (notes != null && notes!.trim().isEmpty) {
      throw const FormatException('Refinement execution notes must not be blank');
    }
  }

  final RefinementExecutionStatus status;
  final String commitSha;
  final List<String> filesChanged;
  final List<ValidationCheck> checks;
  final List<String> evidence;
  final String? notes;

  bool get passed => status == RefinementExecutionStatus.passed;

  /// The domain validation record implied by this result.
  BatchValidation get batchValidation => BatchValidation(
        status: passed ? BatchValidationStatus.passed : BatchValidationStatus.failed,
        checks: checks,
      );

  /// The execution metadata implied by this result.
  BatchExecution execution({String? agent, String? model}) => BatchExecution(
        agent: agent,
        model: model,
        commitSha: commitSha,
        filesChanged: filesChanged,
      );

  factory RefinementExecutionResult.fromJson(Map<String, dynamic> json) {
    final statusValue = json['status'];
    if (statusValue is! String) {
      throw const FormatException('Missing refinement execution status');
    }
    final commitSha = json['commit_sha'];
    if (commitSha is! String) {
      throw const FormatException('Missing refinement execution commit SHA');
    }
    final rawChecks = json['checks'];
    if (rawChecks is! List) {
      throw const FormatException('Missing refinement execution checks');
    }
    final checks = <ValidationCheck>[];
    for (final item in rawChecks) {
      if (item is! Map || item.keys.any((key) => key is! String)) {
        throw const FormatException('Invalid refinement execution check');
      }
      checks.add(ValidationCheck.fromJson(item.cast<String, dynamic>()));
    }
    final notes = json['notes'];
    if (notes != null && notes is! String) {
      throw const FormatException('Invalid refinement execution notes');
    }
    return RefinementExecutionResult(
      status: refinementExecutionStatusFromWire(statusValue),
      commitSha: commitSha,
      filesChanged: _stringList(json['files_changed'], 'changed files'),
      checks: checks,
      evidence: _stringList(json['evidence'], 'evidence'),
      notes: notes as String?,
    );
  }

  /// Deterministic canonical serialization; every key is always present.
  Map<String, dynamic> toJson() => {
        'status': refinementExecutionStatusToWire(status),
        'commit_sha': commitSha,
        'files_changed': [...filesChanged],
        'checks': [for (final check in checks) check.toJson()],
        'evidence': [...evidence],
        'notes': notes,
      };

  static List<String> _normalized(List<String> values, String label) {
    final seen = <String>{};
    for (final value in values) {
      if (value.trim().isEmpty) {
        throw FormatException('Refinement execution $label must not be blank');
      }
      if (!seen.add(value)) {
        throw FormatException('Duplicate refinement execution $label: $value');
      }
    }
    return List<String>.unmodifiable(values.toList()..sort());
  }

  static List<String> _stringList(Object? value, String field) {
    if (value == null) return const <String>[];
    if (value is! List) {
      throw FormatException('Invalid refinement execution $field');
    }
    final result = <String>[];
    for (final item in value) {
      if (item is! String) {
        throw FormatException('Invalid refinement execution $field');
      }
      result.add(item);
    }
    return result;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RefinementExecutionResult &&
        other.status == status &&
        other.commitSha == commitSha &&
        _listEquals(other.filesChanged, filesChanged) &&
        _checkListEquals(other.checks, checks) &&
        _listEquals(other.evidence, evidence) &&
        other.notes == notes;
  }

  @override
  int get hashCode => Object.hash(
        status,
        commitSha,
        Object.hashAll(filesChanged),
        Object.hashAll(checks),
        Object.hashAll(evidence),
        notes,
      );
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
