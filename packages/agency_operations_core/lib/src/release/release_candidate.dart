import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Canonical JSON encoding used for every deterministic release identity in
/// this package.
///
/// The algorithm is intentionally simple so it can be mirrored exactly by the
/// Python release tooling:
///
/// 1. object keys are sorted lexicographically (UTF-16 code unit order, which
///    equals code-point order for the ASCII keys used by these contracts);
/// 2. the encoding is compact: no insignificant whitespace is emitted;
/// 3. strings are escaped using JSON string escaping and emitted as UTF-8;
/// 4. arrays preserve their declared order.
///
/// Supported values are `null`, `bool`, `num`, `String`, `List` and
/// `Map<String, Object?>`. Numbers are encoded with `num.toString()`.
String canonicalizeJson(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is bool) {
    return value ? 'true' : 'false';
  }
  if (value is num) {
    return value.toString();
  }
  if (value is String) {
    return jsonEncode(value);
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
        ..write(jsonEncode(keys[index]))
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
  factory ReleaseCandidate.fromJson(Map<String, Object?> json) {
    return ReleaseCandidate(
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
  /// This is order-sensitive and distinct from [candidateIdentity], so it can
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
