/// Persistence boundary for [QaFinding] records.
///
/// Repositories expose domain operations only (never arbitrary map mutation).
/// [create] is create-only for a stable id and [replace] uses expected-current
/// semantics so a stale in-memory copy can never silently overwrite newer
/// persisted QA state.
library;

import 'qa_finding.dart';

abstract interface class QaFindingRepository {
  Future<QaFinding?> load(String clientId, String findingId);

  Future<List<QaFinding>> list(String clientId);

  Future<void> create(String clientId, QaFinding finding);

  Future<void> replace(
    String clientId,
    QaFinding expectedCurrent,
    QaFinding next,
  );
}
