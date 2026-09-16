import 'dart:convert';

import 'review_persistence_layout.dart';

/// File-backed adapter skeleton for refinement batch artifacts.
///
/// Cycle 2 only needs stable batch-file identity so the operational index can
/// list batches; the typed `RefinementBatch` domain model and its repository
/// interface land in Cycle 3, at which point this adapter implements that
/// interface. Until then it stores/loads raw JSON payloads without inventing a
/// domain type.
final class FileRefinementBatchRepository {
  FileRefinementBatchRepository({required this.layout});

  final ReviewPersistenceLayout layout;

  Future<Map<String, Object?>?> load(String clientId, String batchId) async {
    final file = layout.refinementBatchFile(clientId, batchId);
    final raw = await readFileOrNull(file);
    if (raw == null) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
      throw FormatException('Invalid refinement batch at ${file.path}');
    }
    return decoded.cast<String, Object?>();
  }

  Future<List<String>> listIds(String clientId) async {
    final files = await listRecordFiles(
      layout.refinementBatchesDirectory(clientId),
      'batch-',
      '.json',
    );
    final ids = <String>[];
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      ids.add(name.substring(0, name.length - '.json'.length));
    }
    return ids;
  }

  /// Create-only for a stable batch id; never overwrites an existing artifact.
  Future<void> create(
    String clientId,
    String batchId,
    Map<String, Object?> payload,
  ) async {
    final file = layout.refinementBatchFile(clientId, batchId);
    if (file.existsSync()) {
      throw StateError('refinement batch already exists: $batchId');
    }
    await writeFileAtomic(
      file,
      '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
    );
  }
}
