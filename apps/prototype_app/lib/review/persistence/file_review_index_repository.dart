import 'dart:convert';
import 'dart:io';

import 'review_index.dart';
import 'review_persistence_layout.dart';

/// File-backed [ReviewIndexRepository] with rebuild/recovery support.
///
/// Mutable index/current state is written atomically (temp file + rename). The
/// index is a cache over the immutable records: [rebuild] reconstructs it by
/// scanning the record directories, and [loadOrRebuild] repairs a missing or
/// stale index when an immutable record exists but the index update failed.
final class FileReviewIndexRepository implements ReviewIndexRepository {
  FileReviewIndexRepository({required this.layout});

  final ReviewPersistenceLayout layout;

  @override
  Future<ReviewIndex?> load(String clientId) async {
    final file = layout.reviewIndexFile(clientId);
    final raw = await readFileOrNull(file);
    if (raw == null) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
      throw FormatException('Invalid review index at ${file.path}');
    }
    return ReviewIndex.fromJson(decoded.cast<String, dynamic>());
  }

  @override
  Future<void> save(ReviewIndex index) async {
    await writeFileAtomic(
      layout.reviewIndexFile(index.clientId),
      '${const JsonEncoder.withIndent('  ').convert(index.toJson())}\n',
    );
  }

  /// Rebuilds the index from the immutable records on disk.
  Future<ReviewIndex> rebuild(String clientId) async {
    final feedbackIds = await _idsFrom(
      layout.feedbackDirectory(clientId),
      'feedback-',
      '.json',
    );
    final batchIds = await _idsFrom(
      layout.refinementBatchesDirectory(clientId),
      'batch-',
      '.json',
    );
    final approvalVersions = await _approvalVersions(clientId);
    return ReviewIndex(
      clientId: clientId,
      reviewRound: await _reviewRound(clientId),
      feedbackIds: feedbackIds,
      batchIds: batchIds,
      approvalVersions: approvalVersions,
    );
  }

  /// Loads the persisted index, rebuilding and re-saving it when stale.
  Future<ReviewIndex> loadOrRebuild(String clientId) async {
    final persisted = await load(clientId);
    final rebuilt = await rebuild(clientId);
    if (persisted == null || persisted != rebuilt) {
      await save(rebuilt);
      return rebuilt;
    }
    return persisted;
  }

  Future<List<String>> _idsFrom(
    Directory directory,
    String prefix,
    String suffix,
  ) async {
    final files = await listRecordFiles(directory, prefix, suffix);
    final ids = <String>[];
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      // The record id already carries its `feedback-`/`batch-` prefix.
      ids.add(name.substring(0, name.length - suffix.length));
    }
    return ids;
  }

  Future<List<int>> _approvalVersions(String clientId) async {
    final files = await listRecordFiles(
      layout.approvalsDirectory(clientId),
      'approval-v',
      '.json',
    );
    final versions = <int>[];
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final value = int.tryParse(
        name.substring('approval-v'.length, name.length - '.json'.length),
      );
      if (value != null) {
        versions.add(value);
      }
    }
    return versions;
  }

  Future<int?> _reviewRound(String clientId) async {
    final raw = await readFileOrNull(layout.reviewStateFile(clientId));
    if (raw == null) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }
    final round = decoded['review_round'];
    return round is int && round >= 1 ? round : null;
  }
}
