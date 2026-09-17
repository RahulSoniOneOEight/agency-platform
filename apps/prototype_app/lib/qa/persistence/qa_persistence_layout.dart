/// File-system layout for governed QA artifacts.
///
/// ```text
/// client-projects/<client>/prototype/qa/
///   screenshot-manifest.yaml
///   findings/<finding-id>.json
///   baselines/baseline-index.yaml
///   runs/<run-id>.json
/// ```
///
/// Only this `persistence/` layer performs file I/O; the QA domain models,
/// errors, repositories (interfaces), and coordinator stay I/O-free.
library;

import 'dart:io';

final class QaPersistenceLayout {
  QaPersistenceLayout({required this.clientProjectsDirectory});

  /// Root directory that contains one sub-directory per client.
  final Directory clientProjectsDirectory;

  Directory clientQaDirectory(String clientId) =>
      Directory('${clientProjectsDirectory.path}/$clientId/prototype/qa');

  Directory findingsDirectory(String clientId) =>
      Directory('${clientQaDirectory(clientId).path}/findings');

  /// Stable finding artifact named after the finding id (`qa-<n>.json`).
  File findingFile(String clientId, String findingId) =>
      File('${findingsDirectory(clientId).path}/$findingId.json');

  File screenshotManifestFile(String clientId) =>
      File('${clientQaDirectory(clientId).path}/screenshot-manifest.yaml');

  Directory baselinesDirectory(String clientId) =>
      Directory('${clientQaDirectory(clientId).path}/baselines');

  /// Governed baseline index (versioned, reviewer-controlled).
  File baselineIndexFile(String clientId) =>
      File('${baselinesDirectory(clientId).path}/baseline-index.yaml');

  Directory runsDirectory(String clientId) =>
      Directory('${clientQaDirectory(clientId).path}/runs');

  File runFile(String clientId, String runId) =>
      File('${runsDirectory(clientId).path}/$runId.json');
}

Future<void> writeQaFileAtomic(File file, String contents) async {
  final parent = file.parent;
  if (!parent.existsSync()) {
    await parent.create(recursive: true);
  }
  final temp = File('${file.path}.tmp');
  await temp.writeAsString(contents, flush: true);
  await temp.rename(file.path);
}

Future<String?> readQaFileOrNull(File file) async {
  if (!file.existsSync()) {
    return null;
  }
  return file.readAsString();
}

Future<List<File>> listQaRecordFiles(
  Directory directory,
  String prefix,
  String suffix,
) async {
  if (!directory.existsSync()) {
    return const <File>[];
  }
  final files = directory
      .listSync()
      .whereType<File>()
      .where((file) {
        final name = file.uri.pathSegments.last;
        return name.startsWith(prefix) && name.endsWith(suffix);
      })
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files;
}
