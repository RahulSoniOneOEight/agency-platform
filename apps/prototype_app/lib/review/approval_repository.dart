import 'approval_snapshot.dart';

/// Persistence boundary for immutable [ApprovalSnapshot]s.
///
/// Approvals are append-only: [create] never overwrites an existing version and
/// rejects a duplicate with `ApprovalVersionConflict`. [list] returns snapshots
/// in deterministic ascending version order.
abstract interface class ApprovalRepository {
  Future<List<ApprovalSnapshot>> list(String clientId);

  Future<void> create(String clientId, ApprovalSnapshot snapshot);
}
