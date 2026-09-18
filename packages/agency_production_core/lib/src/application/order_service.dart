import '../domain/domain_failure.dart';
import '../domain/models.dart';
import '../ports/repositories.dart';

/// Consumer (B2C) order placement use cases.
///
/// The cart is loaded through [CartRepository] and handed to
/// [OrderRepository.createOrder]. Idempotency is delegated to the repository
/// (same [IdempotencyKey] returns the same order), so a retried submission can
/// never create a duplicate order. There is deliberately no generic retry
/// middleware: retryability travels on [DomainFailure.retryable] and callers
/// decide.
final class OrderService {
  OrderService({
    required CartRepository carts,
    required OrderRepository orders,
  })  : _carts = carts,
        _orders = orders;

  final CartRepository _carts;
  final OrderRepository _orders;

  /// Places an order for [cartId].
  ///
  /// Re-submitting with the same [idempotencyKey] returns the same order
  /// identity rather than creating a duplicate.
  Future<Order> placeOrder({
    required String cartId,
    required IdempotencyKey idempotencyKey,
  }) async {
    try {
      final cart = await _carts.getCart(cartId);
      if (cart == null) {
        throw DomainFailure(
          code: DomainFailureCode.validation,
          operation: 'place_order',
          retryable: false,
          message: 'Cart $cartId was not found',
        );
      }
      if (cart.items.isEmpty) {
        throw DomainFailure(
          code: DomainFailureCode.validation,
          operation: 'place_order',
          retryable: false,
          message: 'Cart $cartId has no items',
        );
      }
      return await _orders.createOrder(
        cart: cart,
        idempotencyKey: idempotencyKey,
      );
    } on DomainFailure catch (failure) {
      throw _scope(failure);
    }
  }

  DomainFailure _scope(DomainFailure failure) => DomainFailure(
        code: failure.code,
        operation: 'place_order',
        retryable: failure.retryable,
        message: failure.message,
        correlationId: failure.correlationId,
      );
}
