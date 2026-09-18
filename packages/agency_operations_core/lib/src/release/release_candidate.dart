import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Canonical JSON encoding used for every deterministic release identity in
/// this package.
///
/// The byte output matches the repository's Python identity convention,
/// `json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)`
/// followed by a UTF-8 SHA-256 (see `tooling/production/report.py`), so a Dart
/// digest equals a Python digest for the same value:
///
/// 1. object keys are sorted lexicographically (UTF-16 code unit order, which
///    equals code-point order for the ASCII keys used by these contracts);
/// 2. the encoding is compact: no insignificant whitespace is emitted;
/// 3. strings are escaped exactly as Python does with `ensure_ascii=True`: `"`
///    and `\` are backslash-escaped, the short control escapes (`\b`, `\f`,
///    `\n`, `\r`, `\t`) are used where they apply, and every other code unit
///    below `0x20` or at/above `0x80` is emitted as a lowercase `\uXXXX`
///    escape (a non-BMP character becomes a surrogate pair of escapes);
/// 4. arrays preserve their declared order.
///
/// Supported values are `null`, `bool`, `String`, `List` and
/// `Map<String, Object?>`. Numeric values (`num`, `int`, `double`) are
/// **rejected** with an [ArgumentError]: no identity payload contains numbers,
/// which eliminates cross-language float-formatting drift.
String canonicalizeJson(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is bool) {
    return value ? 'true' : 'false';
  }
  if (value is num) {
    throw ArgumentError.value(
      value,
      'value',
      'Canonical identity payloads must not contain numbers; numeric values '
          'are excluded to eliminate cross-language float-formatting drift.',
    );
  }
  if (value is String) {
    return _canonicalString(value);
  }
  if (value is List) {
    return '[${value.map(canonicalizeJson).join(',')}]';
  }
  if (value is Map) {
    final keys = value.keys.map((key) => key as String).toList()..sort();
    final buffer = StringBuffer('{');
    for (var index = 0; index < keys.length; index++) {
      if (index > 0) {
        buffer.write(',');
      }
      buffer
        ..write(_canonicalString(keys[index]))
        ..write(':')
        ..write(canonicalizeJson(value[keys[index]]));
    }
    buffer.write('}');
    return buffer.toString();
  }
  throw ArgumentError.value(
    value,
    'value',
    'Unsupported canonical JSON value type ${value.runtimeType}.',
  );
}

/// Escapes [value] exactly like Python's
/// `json.dumps(..., ensure_ascii=True)` string encoding.
String _canonicalString(String value) {
  final buffer = StringBuffer('"');
  for (final codeUnit in value.codeUnits) {
    if (codeUnit == 0x22) {
      buffer.write(r'\"');
    } else if (codeUnit == 0x5c) {
      buffer.write(r'\\');
    } else if (codeUnit == 0x08) {
      buffer.write(r'\b');
    } else if (codeUnit == 0x0c) {
      buffer.write(r'\f');
    } else if (codeUnit == 0x0a) {
      buffer.write(r'\n');
    } else if (codeUnit == 0x0d) {
      buffer.write(r'\r');
    } else if (codeUnit == 0x09) {
      buffer.write(r'\t');
    } else if (codeUnit < 0x20 || codeUnit >= 0x80) {
      buffer.write('\\u${codeUnit.toRadixString(16).padLeft(4, '0')}');
    } else {
      buffer.writeCharCode(codeUnit);
    }
  }
  buffer.write('"');
  return buffer.toString();
}

/// Deterministic identity of [value]: `sha256:` followed by the lowercase hex
/// digest of the UTF-8 bytes of [canonicalizeJson].
String canonicalJsonHash(Object? value) =>
    'sha256:${sha256.convert(utf8.encode(canonicalizeJson(value)))}';

final RegExp _sourceShaPattern = RegExp(r'^[0-9a-f]{40}$');
final RegExp _sha256Pattern = RegExp(r'^sha256:[0-9a-f]{64}$');

void _requireNonEmpty(String value, String field) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, field, 'must not be empty');
  }
}

void _requireMatch(String value, RegExp pattern, String field) {
  if (!pattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      field,
      'must match ${pattern.pattern}',
    );
  }
}

/// An immutable, exactly-identified release candidate.
///
/// A candidate binds every release-relevant input: client, target
/// environment, source revision, built artifact digest, build version,
/// ordered migration set, release-configuration identity, the approved
/// experience reference, and the H.1 foundation report reference. Once
/// submitted for H.2A hardening a candidate is immutable; any change to a
/// bound field produces a different [candidateIdentity] and therefore a new
/// candidate that requires new authorization.
final class ReleaseCandidate {
  ReleaseCandidate({
    required this.clientId,
    required this.targetEnvironment,
    required this.sourceSha,
    required this.artifactDigest,
    required this.buildVersion,
    List<String> migrationSet = const [],
    required this.releaseConfigIdentity,
    required this.approvedExperienceRef,
    required this.h1FoundationReportRef,
  }) : migrationSet = List.unmodifiable(migrationSet) {
    _requireNonEmpty(clientId, 'clientId');
    _requireNonEmpty(targetEnvironment, 'targetEnvironment');
    _requireMatch(sourceSha, _sourceShaPattern, 'sourceSha');
    _requireMatch(artifactDigest, _sha256Pattern, 'artifactDigest');
    _requireNonEmpty(buildVersion, 'buildVersion');
    _requireMatch(
      releaseConfigIdentity,
      _sha256Pattern,
      'releaseConfigIdentity',
    );
    _requireNonEmpty(approvedExperienceRef, 'approvedExperienceRef');
    _requireNonEmpty(h1FoundationReportRef, 'h1FoundationReportRef');
  }

  /// Rebuilds a candidate from [json], re-validating every field.
  ///
  /// When [json] supplies `candidate_identity` or `migration_set_identity`,
  /// each is verified against the recomputed identity and an [ArgumentError]
  /// is thrown on mismatch rather than silently discarding the declared value.
  factory ReleaseCandidate.fromJson(Map<String, Object?> json) {
    final candidate = ReleaseCandidate(
      clientId: json['client_id']! as String,
      targetEnvironment: json['target_environment']! as String,
      sourceSha: json['source_sha']! as String,
      artifactDigest: json['artifact_digest']! as String,
      buildVersion: json['build_version']! as String,
      migrationSet: (json['migration_set']! as List).cast<String>(),
      releaseConfigIdentity: json['release_config_identity']! as String,
      approvedExperienceRef: json['approved_experience_ref']! as String,
      h1FoundationReportRef: json['h1_foundation_report_ref']! as String,
    );

    final declaredCandidateIdentity = json['candidate_identity'];
    if (declaredCandidateIdentity != null &&
        declaredCandidateIdentity != candidate.candidateIdentity) {
      throw ArgumentError.value(
        declaredCandidateIdentity,
        'candidate_identity',
        'does not match the recomputed candidate identity',
      );
    }

    final declaredMigrationSetIdentity = json['migration_set_identity'];
    if (declaredMigrationSetIdentity != null &&
        declaredMigrationSetIdentity != candidate.migrationSetIdentity) {
      throw ArgumentError.value(
        declaredMigrationSetIdentity,
        'migration_set_identity',
        'does not match the recomputed migration set identity',
      );
    }

    return candidate;
  }

  final String clientId;
  final String targetEnvironment;
  final String sourceSha;
  final String artifactDigest;
  final String buildVersion;
  final List<String> migrationSet;
  final String releaseConfigIdentity;
  final String approvedExperienceRef;
  final String h1FoundationReportRef;

  /// The canonical, identity-bearing fields of the candidate.
  Map<String, Object?> get canonicalFields => {
        'client_id': clientId,
        'target_environment': targetEnvironment,
        'source_sha': sourceSha,
        'artifact_digest': artifactDigest,
        'build_version': buildVersion,
        'migration_set': migrationSet,
        'release_config_identity': releaseConfigIdentity,
        'approved_experience_ref': approvedExperienceRef,
        'h1_foundation_report_ref': h1FoundationReportRef,
      };

  /// Deterministic identity of the ordered migration set.
  ///
  /// This is an **H.2-specific derived binding field**: it is not part of the
  /// base field list in spec §7, but `h2-release-candidate.schema.json`
  /// requires it, so it is emitted by [toJson] and verified by [fromJson].
  ///
  /// It is order-sensitive and distinct from [candidateIdentity], so it can
  /// bind the authorized migration set on its own (spec §9).
  String get migrationSetIdentity =>
      canonicalJsonHash({'migration_set': migrationSet});

  /// Deterministic identity over all canonical candidate fields.
  String get candidateIdentity => canonicalJsonHash(canonicalFields);

  Map<String, Object?> toJson() => {
        ...canonicalFields,
        'candidate_identity': candidateIdentity,
        'migration_set_identity': migrationSetIdentity,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseCandidate &&
          other.clientId == clientId &&
          other.targetEnvironment == targetEnvironment &&
          other.sourceSha == sourceSha &&
          other.artifactDigest == artifactDigest &&
          other.buildVersion == buildVersion &&
          listEquals(other.migrationSet, migrationSet) &&
          other.releaseConfigIdentity == releaseConfigIdentity &&
          other.approvedExperienceRef == approvedExperienceRef &&
          other.h1FoundationReportRef == h1FoundationReportRef;

  @override
  int get hashCode => Object.hash(
        clientId,
        targetEnvironment,
        sourceSha,
        artifactDigest,
        buildVersion,
        Object.hashAll(migrationSet),
        releaseConfigIdentity,
        approvedExperienceRef,
        h1FoundationReportRef,
      );

  @override
  String toString() => 'ReleaseCandidate(clientId: $clientId, '
      'targetEnvironment: $targetEnvironment, sourceSha: $sourceSha, '
      'artifactDigest: $artifactDigest, buildVersion: $buildVersion, '
      'migrationSet: $migrationSet, '
      'releaseConfigIdentity: $releaseConfigIdentity, '
      'approvedExperienceRef: $approvedExperienceRef, '
      'h1FoundationReportRef: $h1FoundationReportRef, '
      'candidateIdentity: $candidateIdentity)';
}
