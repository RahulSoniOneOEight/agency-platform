/// File-backed [QaFindingRepository] matching the governed client QA layout.
///
/// This adapter is the only QA component that touches the file system; it writes
/// pretty-printed, trailing-newline JSON atomically and validates the complete
/// finding before persisting. It never writes runtime bundles or
/// `approved-experience` artifacts.
library;

import 'dart:convert';

import '../qa_domain_error.dart';
import '../qa_finding.dart';
import '../qa_finding_repository.dart';
import 'qa_persistence_layout.dart';

final class FileQaFindingRepository implements QaFindingRepository {
  FileQaFindingRepository({required this.layout});

  final QaPersistenceLayout layout;

  @override
  Future<QaFinding?> load(String clientId, String findingId) async {
    final file = layout.findingFile(clientId, findingId);
    final raw = await readQaFileOrNull(file);
    if (raw == null) {
      return null;
    }
    return _decode(raw);
  }

  @override
  Future<List<QaFinding>> list(String clientId) async {
    final files = await listQaRecordFiles(
      layout.findingsDirectory(clientId),
      'qa-',
      '.json',
    );
    final findings = <QaFinding>[];
    for (final file in files) {
      findings.add(_decode(await file.readAsString()));
    }
    findings.sort((a, b) => a.id.compareTo(b.id));
    return List<QaFinding>.unmodifiable(findings);
  }

  @override
  Future<void> create(String clientId, QaFinding finding) async {
    final file = layout.findingFile(clientId, finding.id);
    if (file.existsSync()) {
      throw DuplicateQaFindingId('QA finding already exists: ${finding.id}');
    }
    await writeQaFileAtomic(file, _encode(finding));
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
    final current = await load(clientId, expectedCurrent.id);
    if (current == null) {
      throw QaFindingNotFound('QA finding does not exist: ${expectedCurrent.id}');
    }
    if (current != expectedCurrent) {
      throw QaFindingChangedSinceRead(
        'QA finding changed since it was read: ${expectedCurrent.id}',
      );
    }
    await writeQaFileAtomic(layout.findingFile(clientId, next.id), _encode(next));
  }

  QaFinding _decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw InvalidQaFinding('invalid QA finding json: ${error.message}');
    }
    if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
      throw const InvalidQaFinding('invalid QA finding artifact');
    }
    return QaFinding.fromJson(decoded.cast<String, dynamic>());
  }

  String _encode(QaFinding finding) =>
      '${const JsonEncoder.withIndent('  ').convert(finding.toJson())}\n';
}
