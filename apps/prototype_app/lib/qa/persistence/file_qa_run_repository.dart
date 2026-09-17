/// File-backed [QaRunRepository] matching the governed client QA layout.
///
/// Runs are written as pretty-printed, trailing-newline JSON under
/// `prototype/qa/runs/<run-id>.json`. This adapter is the only QA run component
/// that touches the file system and never writes runtime bundles.
library;

import 'dart:convert';

import '../qa_run.dart';
import '../qa_run_repository.dart';
import 'qa_persistence_layout.dart';

final class FileQaRunRepository implements QaRunRepository {
  FileQaRunRepository({required this.layout});

  final QaPersistenceLayout layout;

  @override
  Future<void> save(String clientId, QaRun run) async {
    await writeQaFileAtomic(layout.runFile(clientId, run.id), _encode(run));
  }

  @override
  Future<QaRun?> load(String clientId, String runId) async {
    final raw = await readQaFileOrNull(layout.runFile(clientId, runId));
    if (raw == null) {
      return null;
    }
    return _decode(raw);
  }

  @override
  Future<List<QaRun>> list(String clientId) async {
    final files = await listQaRecordFiles(
      layout.runsDirectory(clientId),
      'run-',
      '.json',
    );
    final runs = <QaRun>[];
    for (final file in files) {
      runs.add(_decode(await file.readAsString()));
    }
    runs.sort((a, b) => a.id.compareTo(b.id));
    return List<QaRun>.unmodifiable(runs);
  }

  QaRun _decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw FormatException('invalid QA run json: ${error.message}');
    }
    if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
      throw const FormatException('invalid QA run artifact');
    }
    return QaRun.fromJson(decoded.cast<String, dynamic>());
  }

  String _encode(QaRun run) =>
      '${const JsonEncoder.withIndent('  ').convert(run.toJson())}\n';
}
