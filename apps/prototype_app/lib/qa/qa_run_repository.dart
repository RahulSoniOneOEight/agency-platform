/// Persistence boundary for [QaRun] records.
library;

import 'qa_run.dart';

abstract interface class QaRunRepository {
  Future<void> save(String clientId, QaRun run);

  Future<QaRun?> load(String clientId, String runId);

  Future<List<QaRun>> list(String clientId);
}
