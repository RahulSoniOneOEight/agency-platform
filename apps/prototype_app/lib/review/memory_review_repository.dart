import 'review_repository.dart';
import 'review_state.dart';

final class MemoryReviewRepository implements ReviewRepository {
  final Map<String, ReviewState> _states = <String, ReviewState>{};

  @override
  Future<ReviewState?> load(String clientId) async => _states[clientId];

  @override
  Future<void> save(ReviewState state) async {
    _states[state.clientId] = state;
  }
}
