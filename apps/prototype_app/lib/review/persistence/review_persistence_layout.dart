/// File layout and atomic-write helpers for file-backed review artifacts.
///
/// This is the only place in the review subsystem that performs file I/O (R1):
/// the domain models, typed errors, and repository interfaces stay I/O-free.
/// The layout mirrors the approved contract:
///
/// ```text
/// client-projects/<client>/review/
///   review-state.json
///   review-index.json
///   feedback/feedback-<id>.json
///   refinement-batches/batch-<id>.json
///   approvals/approval-v<version>.json
/// ```
library;

import 'dart:io';

final class ReviewPersistenceLayout {
  ReviewPersistenceLayout({required this.clientProjectsDirectory});

  /// Root directory that contains one sub-directory per client.
  final Directory clientProjectsDirectory;

  Directory clientReviewDirectory(String clientId) =>
      Directory('${clientProjectsDirectory.path}/$clientId/review');

  File reviewStateFile(String clientId) =>
      File('${clientReviewDirectory(clientId).path}/review-state.json');

  File reviewIndexFile(String clientId) =>
      File('${clientReviewDirectory(clientId).path}/review-index.json');

  Directory feedbackDirectory(String clientId) =>
      Directory('${clientReviewDirectory(clientId).path}/feedback');

  /// Stable feedback artifact named after the record id (`feedback-<n>.json`).
  File feedbackFile(String clientId, String feedbackId) =>
      File('${feedbackDirectory(clientId).path}/$feedbackId.json');

  Directory refinementBatchesDirectory(String clientId) =>
      Directory('${clientReviewDirectory(clientId).path}/refinement-batches');

  /// Stable batch artifact named after the batch id (`batch-<n>.json`).
  File refinementBatchFile(String clientId, String batchId) =>
      File('${refinementBatchesDirectory(clientId).path}/$batchId.json');

  Directory approvalsDirectory(String clientId) =>
      Directory('${clientReviewDirectory(clientId).path}/approvals');

  /// Immutable approval artifact. The spec's `.yaml` suffix is deferred to avoid
  /// a new dependency; content is deterministic JSON (see ledger deviation).
  File approvalFile(String clientId, int version) =>
      File('${approvalsDirectory(clientId).path}/approval-v$version.json');
}

/// Writes [contents] to [file] via a temp file + rename so a reader never sees a
/// partially written index/current-state file.
Future<void> writeFileAtomic(File file, String contents) async {
  final parent = file.parent;
  if (!parent.existsSync()) {
    await parent.create(recursive: true);
  }
  final temp = File('${file.path}.tmp');
  await temp.writeAsString(contents, flush: true);
  await temp.rename(file.path);
}

/// Reads [file] as a string, or returns `null` when it does not exist.
Future<String?> readFileOrNull(File file) async {
  if (!file.existsSync()) {
    return null;
  }
  return file.readAsString();
}

/// Deterministically ordered files in [directory] matching [prefix]/[suffix].
Future<List<File>> listRecordFiles(
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
