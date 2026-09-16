import 'dart:convert';

import '../refinement_batch.dart';
import '../refinement_batch_repository.dart';
import 'review_persistence_layout.dart';

/// File-backed [RefinementBatchRepository].
///
/// Each batch is stored at `refinement-batches/batch-<id>.json`, so batch
/// identity is stable across rounds. [create] is create-only for an id and
/// [replace] keeps the expected-current semantics of the in-memory adapter.
/// Completed batches are effectively frozen at the domain layer; the adapter
/// never rewrites a record except through an explicit [replace] with the exact
/// expected-current value.
final class FileRefinementBatchRepository implements RefinementBatchRepository {
  FileRefinementBatchRepository({required this.layout});

  final ReviewPersistenceLayout layout;

  @override
  Future<RefinementBatch?> load(String clientId, String batchId) async {
    final file = layout.refinementBatchFile(clientId, batchId);
    final raw = await readFileOrNull(file);
    if (raw == null) {
      return null;
    }
    return _decode(raw, file.path);
  }

  @override
  Future<List<RefinementBatch>> list(String clientId) async {
    final files = await listRecordFiles(
      layout.refinementBatchesDirectory(clientId),
      'batch-',
      '.json',
    );
    final batches = <RefinementBatch>[];
    for (final file in files) {
      batches.add(_decode(await file.readAsString(), file.path));
    }
    batches.sort((a, b) => a.id.compareTo(b.id));
    return List<RefinementBatch>.unmodifiable(batches);
  }

  @override
  Future<void> create(String clientId, RefinementBatch batch) async {
    final file = layout.refinementBatchFile(clientId, batch.id);
    if (file.existsSync()) {
      throw StateError('refinement batch already exists: ${batch.id}');
    }
    await writeFileAtomic(file, _encode(batch));
  }

  @override
  Future<void> replace(
    String clientId,
    RefinementBatch expectedCurrent,
    RefinementBatch next,
  ) async {
    if (next.id != expectedCurrent.id) {
      throw StateError(
        'replacement id ${next.id} does not match expected id ${expectedCurrent.id}',
      );
    }
    final current = await load(clientId, expectedCurrent.id);
    if (current == null) {
      throw StateError('refinement batch does not exist: ${expectedCurrent.id}');
    }
    if (current != expectedCurrent) {
      throw StateError(
        'refinement batch changed since it was read: ${expectedCurrent.id}',
      );
    }
    await writeFileAtomic(layout.refinementBatchFile(clientId, next.id), _encode(next));
  }

  RefinementBatch _decode(String raw, String path) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
      throw FormatException('Invalid refinement batch at $path');
    }
    return RefinementBatch.fromJson(decoded.cast<String, dynamic>());
  }

  String _encode(RefinementBatch batch) =>
      '${const JsonEncoder.withIndent('  ').convert(batch.toJson())}\n';
}
