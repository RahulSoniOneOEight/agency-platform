import 'refinement_batch.dart';
import 'refinement_batch_repository.dart';

/// In-memory [RefinementBatchRepository] for deterministic tests and local use.
///
/// Batches are keyed by client then id. [list] returns ids in ascending order so
/// reads are deterministic regardless of creation order. [create] is create-only
/// (a duplicate id throws a [StateError]) and [replace] rejects a stale
/// expected-current snapshot.
final class MemoryRefinementBatchRepository
    implements RefinementBatchRepository {
  final Map<String, Map<String, RefinementBatch>> _batches =
      <String, Map<String, RefinementBatch>>{};

  @override
  Future<RefinementBatch?> load(String clientId, String batchId) async =>
      _batches[clientId]?[batchId];

  @override
  Future<List<RefinementBatch>> list(String clientId) async {
    final store = _batches[clientId];
    if (store == null) {
      return const <RefinementBatch>[];
    }
    final ids = store.keys.toList()..sort();
    return <RefinementBatch>[for (final id in ids) store[id]!];
  }

  @override
  Future<void> create(String clientId, RefinementBatch batch) async {
    final store =
        _batches.putIfAbsent(clientId, () => <String, RefinementBatch>{});
    if (store.containsKey(batch.id)) {
      throw StateError('refinement batch already exists: ${batch.id}');
    }
    store[batch.id] = batch;
  }

  @override
  Future<void> replace(
    String clientId,
    RefinementBatch expectedCurrent,
    RefinementBatch next,
  ) async {
    if (next.id != expectedCurrent.id) {
      throw StateError(
        'replacement id ${next.id} does not match expected id ${expectedCurrent.id}',
      );
    }
    final store = _batches[clientId];
    final current = store?[expectedCurrent.id];
    if (current == null) {
      throw StateError('refinement batch does not exist: ${expectedCurrent.id}');
    }
    if (current != expectedCurrent) {
      throw StateError(
        'refinement batch changed since it was read: ${expectedCurrent.id}',
      );
    }
    store![expectedCurrent.id] = next;
  }
}
