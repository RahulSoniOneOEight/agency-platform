import 'approval_repository.dart';
import 'approval_snapshot.dart';
import 'review_domain_error.dart';

/// In-memory, append-only [ApprovalRepository] for tests and local review.
///
/// Versions are monotonic: [create] rejects a duplicate (or out-of-order)
/// version with [ApprovalVersionConflict] and never overwrites a stored
/// snapshot. [list] returns versions in ascending order.
final class MemoryApprovalRepository implements ApprovalRepository {
  final Map<String, List<ApprovalSnapshot>> _snapshots =
      <String, List<ApprovalSnapshot>>{};

  @override
  Future<List<ApprovalSnapshot>> list(String clientId) async {
    final store = _snapshots[clientId];
    if (store == null) {
      return const <ApprovalSnapshot>[];
    }
    final sorted = List<ApprovalSnapshot>.of(store)
      ..sort((a, b) => a.version.compareTo(b.version));
    return List<ApprovalSnapshot>.unmodifiable(sorted);
  }

  @override
  Future<void> create(String clientId, ApprovalSnapshot snapshot) async {
    final store =
        _snapshots.putIfAbsent(clientId, () => <ApprovalSnapshot>[]);
    if (store.any((existing) => existing.version == snapshot.version)) {
      throw ApprovalVersionConflict(
        'approval version ${snapshot.version} already exists for $clientId',
      );
    }
    if (store.any((existing) => existing.version > snapshot.version)) {
      throw ApprovalVersionConflict(
        'approval version ${snapshot.version} is not monotonic for $clientId',
      );
    }
    store.add(snapshot);
  }
}
