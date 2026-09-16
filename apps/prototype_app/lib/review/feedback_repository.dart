import 'feedback_record.dart';

/// Persistence boundary for [FeedbackRecord]s.
///
/// Repositories expose domain operations only (never arbitrary map mutation).
/// [create] is create-only for a stable id and [replace] uses expected-current
/// semantics so a stale in-memory copy can never silently overwrite newer
/// persisted state.
abstract interface class FeedbackRepository {
  Future<FeedbackRecord?> load(String clientId, String feedbackId);

  Future<List<FeedbackRecord>> list(String clientId);

  Future<void> create(String clientId, FeedbackRecord record);

  Future<void> replace(
    String clientId,
    FeedbackRecord expectedCurrent,
    FeedbackRecord next,
  );
}
