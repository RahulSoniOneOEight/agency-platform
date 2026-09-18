import 'package:flutter/foundation.dart';

import 'release_candidate.dart';
import 'release_outcome.dart';

final RegExp _sourceShaPattern = RegExp(r'^[0-9a-f]{40}$');
final RegExp _sha256Pattern = RegExp(r'^sha256:[0-9a-f]{64}$');

bool _isPresent(String? value) => value != null && value.isNotEmpty;

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

/// One immutable record per production release attempt (spec §18).
///
/// The record binds the exact candidate inputs, the H.2A hardening evidence,
/// the G [productionAuthorizationId], the deployment target, the production
/// smoke and telemetry-health evidence, and the resulting [releaseStatus].
///
/// The constructor encodes the release-outcome invariants so an invalid record
/// cannot exist in memory:
///
/// * [ReleaseOutcome.healthy] requires production deployment evidence
///   ([deploymentTarget]), [productionSmokeEvidence],
///   [telemetryHealthEvidence], and a non-empty [productionAuthorizationId];
/// * [ReleaseOutcome.degraded] requires at least one
///   [incidentOrAdvisoryRefs] entry;
/// * [ReleaseOutcome.failed] requires failure/recovery evidence: a non-empty
///   [rollbackOrRecoveryRef] or at least one [incidentOrAdvisoryRefs] entry.
final class ReleaseRecord {
  ReleaseRecord({
    required String releaseId,
    required String clientId,
    required String environment,
    required String sourceSha,
    required String artifactDigest,
    required String buildVersion,
    List<String> migrationSet = const [],
    required String releaseConfigIdentity,
    required String hardeningReportId,
    this.productionAuthorizationId,
    this.stagingEvidence,
    this.productionSmokeEvidence,
    this.telemetryHealthEvidence,
    this.deploymentTarget,
    required this.releaseStatus,
    List<String> incidentOrAdvisoryRefs = const [],
    this.rollbackOrRecoveryRef,
    this.previousKnownGoodReleaseId,
    required DateTime startedAt,
    required DateTime completedAt,
  })  : releaseId = releaseId,
        clientId = clientId,
        environment = environment,
        sourceSha = sourceSha,
        artifactDigest = artifactDigest,
        buildVersion = buildVersion,
        migrationSet = List.unmodifiable(migrationSet),
        releaseConfigIdentity = releaseConfigIdentity,
        hardeningReportId = hardeningReportId,
        incidentOrAdvisoryRefs = List.unmodifiable(incidentOrAdvisoryRefs),
        startedAt = startedAt.toUtc(),
        completedAt = completedAt.toUtc() {
    _requireNonEmpty(releaseId, 'releaseId');
    _requireNonEmpty(clientId, 'clientId');
    _requireNonEmpty(environment, 'environment');
    _requireMatch(sourceSha, _sourceShaPattern, 'sourceSha');
    _requireMatch(artifactDigest, _sha256Pattern, 'artifactDigest');
    _requireNonEmpty(buildVersion, 'buildVersion');
    _requireMatch(
      releaseConfigIdentity,
      _sha256Pattern,
      'releaseConfigIdentity',
    );
    _requireNonEmpty(hardeningReportId, 'hardeningReportId');
    if (completedAt.isBefore(startedAt)) {
      throw ArgumentError.value(
        completedAt,
        'completedAt',
        'must not be before startedAt',
      );
    }
    switch (releaseStatus) {
      case ReleaseOutcome.healthy:
        if (!_isPresent(deploymentTarget) ||
            !_isPresent(productionSmokeEvidence) ||
            !_isPresent(telemetryHealthEvidence) ||
            !_isPresent(productionAuthorizationId)) {
          throw ArgumentError(
            'A healthy release requires production deployment evidence, '
            'production smoke evidence, telemetry health evidence, and a '
            'production authorization id.',
          );
        }
      case ReleaseOutcome.degraded:
        if (incidentOrAdvisoryRefs.isEmpty) {
          throw ArgumentError(
            'A degraded release requires at least one incident/advisory '
            'reference.',
          );
        }
      case ReleaseOutcome.failed:
        if (!_isPresent(rollbackOrRecoveryRef) &&
            incidentOrAdvisoryRefs.isEmpty) {
          throw ArgumentError(
            'A failed release requires failure/recovery evidence: a '
            'rollback/recovery reference or at least one incident/advisory '
            'reference.',
          );
        }
    }
  }

  /// Rebuilds a record from [json], re-validating every field.
  factory ReleaseRecord.fromJson(Map<String, Object?> json) {
    return ReleaseRecord(
      releaseId: json['release_id']! as String,
      clientId: json['client_id']! as String,
      environment: json['environment']! as String,
      sourceSha: json['source_sha']! as String,
      artifactDigest: json['artifact_digest']! as String,
      buildVersion: json['build_version']! as String,
      migrationSet: (json['migration_set']! as List).cast<String>(),
      releaseConfigIdentity: json['release_config_identity']! as String,
      hardeningReportId: json['hardening_report_id']! as String,
      productionAuthorizationId:
          json['production_authorization_id'] as String?,
      stagingEvidence: json['staging_evidence'] as String?,
      productionSmokeEvidence: json['production_smoke_evidence'] as String?,
      telemetryHealthEvidence:
          json['telemetry_health_evidence'] as String?,
      deploymentTarget: json['deployment_target'] as String?,
      releaseStatus:
          ReleaseOutcome.values.byName(json['release_status']! as String),
      incidentOrAdvisoryRefs:
          (json['incident_or_advisory_refs']! as List).cast<String>(),
      rollbackOrRecoveryRef: json['rollback_or_recovery_ref'] as String?,
      previousKnownGoodReleaseId:
          json['previous_known_good_release_id'] as String?,
      startedAt: DateTime.parse(json['started_at']! as String),
      completedAt: DateTime.parse(json['completed_at']! as String),
    );
  }

  final String releaseId;
  final String clientId;
  final String environment;
  final String sourceSha;
  final String artifactDigest;
  final String buildVersion;
  final List<String> migrationSet;
  final String releaseConfigIdentity;
  final String hardeningReportId;
  final String? productionAuthorizationId;
  final String? stagingEvidence;
  final String? productionSmokeEvidence;
  final String? telemetryHealthEvidence;
  final String? deploymentTarget;
  final ReleaseOutcome releaseStatus;
  final List<String> incidentOrAdvisoryRefs;
  final String? rollbackOrRecoveryRef;
  final String? previousKnownGoodReleaseId;
  final DateTime startedAt;
  final DateTime completedAt;

  /// The canonical, identity-bearing fields of the record.
  ///
  /// [releaseIdentity] is intentionally excluded.
  Map<String, Object?> get canonicalFields => {
        'release_id': releaseId,
        'client_id': clientId,
        'environment': environment,
        'source_sha': sourceSha,
        'artifact_digest': artifactDigest,
        'build_version': buildVersion,
        'migration_set': migrationSet,
        'release_config_identity': releaseConfigIdentity,
        'hardening_report_id': hardeningReportId,
        'production_authorization_id': productionAuthorizationId,
        'staging_evidence': stagingEvidence,
        'production_smoke_evidence': productionSmokeEvidence,
        'telemetry_health_evidence': telemetryHealthEvidence,
        'deployment_target': deploymentTarget,
        'release_status': releaseStatus.name,
        'incident_or_advisory_refs': incidentOrAdvisoryRefs,
        'rollback_or_recovery_ref': rollbackOrRecoveryRef,
        'previous_known_good_release_id': previousKnownGoodReleaseId,
        'started_at': startedAt.toIso8601String(),
        'completed_at': completedAt.toIso8601String(),
      };

  /// Deterministic identity over all immutable canonical fields, excluding
  /// [releaseIdentity] itself.
  String get releaseIdentity => canonicalJsonHash(canonicalFields);

  Map<String, Object?> toJson() => {
        ...canonicalFields,
        'release_identity': releaseIdentity,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReleaseRecord &&
          other.releaseId == releaseId &&
          other.clientId == clientId &&
          other.environment == environment &&
          other.sourceSha == sourceSha &&
          other.artifactDigest == artifactDigest &&
          other.buildVersion == buildVersion &&
          listEquals(other.migrationSet, migrationSet) &&
          other.releaseConfigIdentity == releaseConfigIdentity &&
          other.hardeningReportId == hardeningReportId &&
          other.productionAuthorizationId == productionAuthorizationId &&
          other.stagingEvidence == stagingEvidence &&
          other.productionSmokeEvidence == productionSmokeEvidence &&
          other.telemetryHealthEvidence == telemetryHealthEvidence &&
          other.deploymentTarget == deploymentTarget &&
          other.releaseStatus == releaseStatus &&
          listEquals(other.incidentOrAdvisoryRefs, incidentOrAdvisoryRefs) &&
          other.rollbackOrRecoveryRef == rollbackOrRecoveryRef &&
          other.previousKnownGoodReleaseId == previousKnownGoodReleaseId &&
          other.startedAt == startedAt &&
          other.completedAt == completedAt;

  @override
  int get hashCode => Object.hash(
        releaseId,
        clientId,
        environment,
        sourceSha,
        artifactDigest,
        buildVersion,
        Object.hashAll(migrationSet),
        releaseConfigIdentity,
        hardeningReportId,
        productionAuthorizationId,
        stagingEvidence,
        productionSmokeEvidence,
        telemetryHealthEvidence,
        deploymentTarget,
        releaseStatus,
        Object.hashAll(incidentOrAdvisoryRefs),
        rollbackOrRecoveryRef,
        previousKnownGoodReleaseId,
        startedAt,
        completedAt,
      );

  @override
  String toString() => 'ReleaseRecord(releaseId: $releaseId, '
      'clientId: $clientId, environment: $environment, sourceSha: $sourceSha, '
      'artifactDigest: $artifactDigest, buildVersion: $buildVersion, '
      'migrationSet: $migrationSet, '
      'releaseConfigIdentity: $releaseConfigIdentity, '
      'hardeningReportId: $hardeningReportId, '
      'productionAuthorizationId: $productionAuthorizationId, '
      'deploymentTarget: $deploymentTarget, '
      'releaseStatus: ${releaseStatus.name}, '
      'incidentOrAdvisoryRefs: $incidentOrAdvisoryRefs, '
      'rollbackOrRecoveryRef: $rollbackOrRecoveryRef, '
      'previousKnownGoodReleaseId: $previousKnownGoodReleaseId, '
      'startedAt: ${startedAt.toIso8601String()}, '
      'completedAt: ${completedAt.toIso8601String()}, '
      'releaseIdentity: $releaseIdentity)';
}
