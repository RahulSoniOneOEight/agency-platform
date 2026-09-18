import 'package:flutter/foundation.dart';

/// Severity of a hardening finding.
enum HardeningSeverity { info, low, medium, high, critical }

/// Whether a finding blocks progression to production authorization.
enum GateDisposition { advisory, blocking }

/// Hardening area a finding belongs to.
enum HardeningArea {
  security,
  performance,
  accessibility,
  analytics,
  observability,
  migrations,
  stagingSmoke,
  productionHealth,
}

/// Lifecycle status of a finding.
enum FindingStatus { open, closed, waived }

/// A single hardening finding.
///
/// Blocking behavior is explicit policy data carried by [disposition] and
/// [status]; it is never inferred from a provider. A finding blocks the release
/// only while it is [FindingStatus.open] and [GateDisposition.blocking].
final class HardeningFinding {
  const HardeningFinding({
    required this.id,
    required this.area,
    required this.severity,
    required this.disposition,
    required this.summary,
    this.status = FindingStatus.open,
    this.evidenceRefs = const [],
  });

  final String id;
  final HardeningArea area;
  final HardeningSeverity severity;
  final GateDisposition disposition;
  final String summary;
  final FindingStatus status;
  final List<String> evidenceRefs;

  bool get blocksRelease =>
      disposition == GateDisposition.blocking && status == FindingStatus.open;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HardeningFinding &&
          other.id == id &&
          other.area == area &&
          other.severity == severity &&
          other.disposition == disposition &&
          other.summary == summary &&
          other.status == status &&
          listEquals(other.evidenceRefs, evidenceRefs);

  @override
  int get hashCode => Object.hash(
        id,
        area,
        severity,
        disposition,
        summary,
        status,
        Object.hashAll(evidenceRefs),
      );

  @override
  String toString() => 'HardeningFinding(id: $id, area: ${area.name}, '
      'severity: ${severity.name}, disposition: ${disposition.name}, '
      'status: ${status.name}, summary: $summary, '
      'evidenceRefs: $evidenceRefs)';
}
