import 'review_state.dart';

abstract interface class ReviewRepository {
  Future<ReviewState?> load(String clientId);

  Future<void> save(ReviewState state);
}
