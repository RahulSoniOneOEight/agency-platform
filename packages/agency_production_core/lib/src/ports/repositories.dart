import '../domain/models.dart';

/// A caller-supplied key that makes externally visible mutations idempotent.
///
/// Mutating operations that can create externally visible effects (orders,
/// RFQs, payments, shipments, ERP/CRM/WhatsApp side effects) accept an
/// [IdempotencyKey]. Re-submitting the same key must yield the same result
/// rather than creating a duplicate effect. Read operations never require one.
final class IdempotencyKey {
  IdempotencyKey(this.value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, 'value', 'must not be empty');
    }
  }

  final String value;

  @override
  bool operator ==(Object other) =>
      other is IdempotencyKey && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'IdempotencyKey($value)';
}

/// Read access to the product catalog.
abstract interface class CatalogRepository {
  Future<List<Product>> listProducts({String? categoryId});

  Future<Product?> getProduct(String productId);

  Future<List<Variant>> listVariants(String productId);
}

/// Read access to inventory availability.
abstract interface class InventoryRepository {
  Future<InventoryAvailability?> getAvailability(String variantId);

  Future<List<InventoryAvailability>> listAvailability(
    Iterable<String> variantIds,
  );
}

/// Persistence for consumer customer profiles.
abstract interface class CustomerRepository {
  Future<CustomerProfile?> getProfile(String identityId);

  Future<CustomerProfile> saveProfile(CustomerProfile profile);
}

/// B2B account access.
///
/// Business permissions are resolved per account from [AccountMembership];
/// there is no single global user role that grants account access.
abstract interface class AccountRepository {
  Future<List<BusinessAccount>> listAccountsForIdentity(String identityId);

  Future<AccountMembership?> getMembership({
    required String accountId,
    required String identityId,
  });

  Future<CreditSnapshot?> getCreditSnapshot(String accountId);
}

/// Persistence for shopping carts.
abstract interface class CartRepository {
  Future<Cart?> getCart(String cartId);

  /// Persists [cart]. When [accountId] is supplied the cart is attributed to
  /// that B2B account; otherwise it is a personal (consumer) cart attributed to
  /// the authenticated identity at the persistence boundary.
  Future<Cart> saveCart(Cart cart, {String? accountId});
}

/// Persistence for orders.
abstract interface class OrderRepository {
  /// Creates an order from [cart]. The same [idempotencyKey] must return the
  /// same order instead of creating a duplicate.
  ///
  /// When [totalMinor] is supplied it is the authoritative order total (for
  /// example a negotiated quotation total); otherwise the cart subtotal is
  /// used. This keeps the persisted total aligned with whatever amount was
  /// authorized (e.g. a credit check).
  ///
  /// When [accountId] is supplied the order is attributed to that B2B account
  /// (e.g. a quotation conversion); otherwise it is a personal (consumer)
  /// order attributed to the authenticated identity at the persistence
  /// boundary.
  Future<Order> createOrder({
    required Cart cart,
    required IdempotencyKey idempotencyKey,
    int? totalMinor,
    String? accountId,
  });
}

/// Persistence for RFQs and quotations.
abstract interface class QuoteRepository {
  /// Creates an RFQ for [accountId]. The same [idempotencyKey] must return the
  /// same RFQ instead of creating a duplicate.
  Future<Rfq> createRfq({
    required String accountId,
    required List<CartItem> items,
    required IdempotencyKey idempotencyKey,
    String? message,
  });

  Future<Rfq?> getRfq(String rfqId);

  /// Persists a quotation produced by the business/ERP side. The same
  /// [idempotencyKey] must return the same quotation.
  Future<Quotation> saveQuotation({
    required Quotation quotation,
    required IdempotencyKey idempotencyKey,
  });

  Future<Quotation?> getQuotation(String quotationId);
}
