/// In-memory [QaRunRepository] for tests and the runtime prototype.
library;

import 'qa_run.dart';
import 'qa_run_repository.dart';

final class MemoryQaRunRepository implements QaRunRepository {
  final Map<String, Map<String, QaRun>> _runs = {};

  @override
  Future<void> save(String clientId, QaRun run) async {
    _runs.putIfAbsent(clientId, () => {})[run.id] = run;
  }

  @override
  Future<QaRun?> load(String clientId, String runId) async =>
      _runs[clientId]?[runId];

  @override
  Future<List<QaRun>> list(String clientId) async {
    final store = _runs[clientId];
    if (store == null) return const [];
    final runs = store.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return List<QaRun>.unmodifiable(runs);
  }
}
