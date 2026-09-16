import 'dart:convert';

import '../feedback_record.dart';
import '../feedback_repository.dart';
import 'review_persistence_layout.dart';

/// File-backed [FeedbackRepository].
///
/// Each record is stored at `feedback/feedback-<id>.json`, so feedback identity
/// is stable across rounds. [create] is create-only for an id; [replace] keeps
/// the expected-current semantics of the in-memory adapter.
final class FileFeedbackRepository implements FeedbackRepository {
  FileFeedbackRepository({required this.layout});

  final ReviewPersistenceLayout layout;

  @override
  Future<FeedbackRecord?> load(String clientId, String feedbackId) async {
    final file = layout.feedbackFile(clientId, feedbackId);
    final raw = await readFileOrNull(file);
    if (raw == null) {
      return null;
    }
    return _decode(raw, file.path);
  }

  @override
  Future<List<FeedbackRecord>> list(String clientId) async {
    final files = await listRecordFiles(
      layout.feedbackDirectory(clientId),
      'feedback-',
      '.json',
    );
    final records = <FeedbackRecord>[];
    for (final file in files) {
      records.add(_decode(await file.readAsString(), file.path));
    }
    records.sort((a, b) => a.id.compareTo(b.id));
    return List<FeedbackRecord>.unmodifiable(records);
  }

  @override
  Future<void> create(String clientId, FeedbackRecord record) async {
    final file = layout.feedbackFile(clientId, record.id);
    if (file.existsSync()) {
      throw StateError('feedback record already exists: ${record.id}');
    }
    await writeFileAtomic(file, _encode(record));
  }

  @override
  Future<void> replace(
    String clientId,
    FeedbackRecord expectedCurrent,
    FeedbackRecord next,
  ) async {
    if (next.id != expectedCurrent.id) {
      throw StateError(
        'replacement id ${next.id} does not match expected id ${expectedCurrent.id}',
      );
    }
    final current = await load(clientId, expectedCurrent.id);
    if (current == null) {
      throw StateError('feedback record does not exist: ${expectedCurrent.id}');
    }
    if (current != expectedCurrent) {
      throw StateError(
        'feedback record changed since it was read: ${expectedCurrent.id}',
      );
    }
    await writeFileAtomic(layout.feedbackFile(clientId, next.id), _encode(next));
  }

  FeedbackRecord _decode(String raw, String path) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
      throw FormatException('Invalid feedback record at $path');
    }
    return FeedbackRecord.fromJson(decoded.cast<String, dynamic>());
  }

  String _encode(FeedbackRecord record) =>
      '${const JsonEncoder.withIndent('  ').convert(record.toJson())}\n';
}
