import 'refinement_batch.dart';

/// Persistence boundary for [RefinementBatch]es.
///
/// Repositories expose domain operations only (never arbitrary map mutation).
/// [create] is create-only for a stable batch id and [replace] uses
/// expected-current semantics so a stale in-memory copy can never silently
/// overwrite newer persisted state.
abstract interface class RefinementBatchRepository {
  Future<RefinementBatch?> load(String clientId, String batchId);

  Future<List<RefinementBatch>> list(String clientId);

  Future<void> create(String clientId, RefinementBatch batch);

  Future<void> replace(
    String clientId,
    RefinementBatch expectedCurrent,
    RefinementBatch next,
  );
}
