import 'feedback_record.dart';
import 'feedback_repository.dart';

/// In-memory [FeedbackRepository] for deterministic tests and local review.
///
/// Records are keyed by client then id. [list] returns ids in ascending order so
/// reads are deterministic regardless of creation order. [create] is create-only
/// (a duplicate id throws a [StateError]) and [replace] rejects a stale
/// expected-current snapshot.
final class MemoryFeedbackRepository implements FeedbackRepository {
  final Map<String, Map<String, FeedbackRecord>> _records =
      <String, Map<String, FeedbackRecord>>{};

  @override
  Future<FeedbackRecord?> load(String clientId, String feedbackId) async =>
      _records[clientId]?[feedbackId];

  @override
  Future<List<FeedbackRecord>> list(String clientId) async {
    final store = _records[clientId];
    if (store == null) {
      return const <FeedbackRecord>[];
    }
    final ids = store.keys.toList()..sort();
    return <FeedbackRecord>[for (final id in ids) store[id]!];
  }

  @override
  Future<void> create(String clientId, FeedbackRecord record) async {
    final store = _records.putIfAbsent(clientId, () => <String, FeedbackRecord>{});
    if (store.containsKey(record.id)) {
      throw StateError('feedback record already exists: ${record.id}');
    }
    store[record.id] = record;
  }

  @override
  Future<void> replace(
    String clientId,
    FeedbackRecord expectedCurrent,
    FeedbackRecord next,
  ) async {
    if (next.id != expectedCurrent.id) {
      throw StateError(
        'replacement id ${next.id} does not match expected id ${expectedCurrent.id}',
      );
    }
    final store = _records[clientId];
    final current = store?[expectedCurrent.id];
    if (current == null) {
      throw StateError('feedback record does not exist: ${expectedCurrent.id}');
    }
    if (current != expectedCurrent) {
      throw StateError(
        'feedback record changed since it was read: ${expectedCurrent.id}',
      );
    }
    store![expectedCurrent.id] = next;
  }
}
