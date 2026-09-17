/// In-memory [QaFindingRepository] for tests and the runtime prototype.
library;

import 'qa_domain_error.dart';
import 'qa_finding.dart';
import 'qa_finding_repository.dart';

final class MemoryQaFindingRepository implements QaFindingRepository {
  final Map<String, Map<String, QaFinding>> _findings = {};

  @override
  Future<QaFinding?> load(String clientId, String findingId) async =>
      _findings[clientId]?[findingId];

  @override
  Future<List<QaFinding>> list(String clientId) async {
    final store = _findings[clientId];
    if (store == null) return const [];
    final findings = store.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return List<QaFinding>.unmodifiable(findings);
  }

  @override
  Future<void> create(String clientId, QaFinding finding) async {
    final store = _findings.putIfAbsent(clientId, () => {});
    if (store.containsKey(finding.id)) {
      throw DuplicateQaFindingId('QA finding already exists: ${finding.id}');
    }
    store[finding.id] = finding;
  }

  @override
  Future<void> replace(
    String clientId,
    QaFinding expectedCurrent,
    QaFinding next,
  ) async {
    if (next.id != expectedCurrent.id) {
      throw QaFindingChangedSinceRead(
        'replacement id ${next.id} does not match expected id '
        '${expectedCurrent.id}',
      );
    }
    final store = _findings[clientId];
    final current = store?[expectedCurrent.id];
    if (current == null) {
      throw QaFindingNotFound('QA finding does not exist: ${expectedCurrent.id}');
    }
    if (current != expectedCurrent) {
      throw QaFindingChangedSinceRead(
        'QA finding changed since it was read: ${expectedCurrent.id}',
      );
    }
    store![next.id] = next;
  }
}
