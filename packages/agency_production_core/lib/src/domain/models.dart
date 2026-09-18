import 'identity.dart';

enum OrderStatus { pending, confirmed, fulfilled, cancelled }

enum RfqStatus { submitted, quoted, converted, rejected }

enum QuotationStatus { draft, sent, accepted, rejected, expired }

final class Product {
  Product({
    required this.id,
    required this.name,
    required this.sku,
    required this.priceMinor,
    this.categoryId,
    this.description,
  }) {
    _requireNonEmpty(id, 'id');
    _requireNonEmpty(name, 'name');
    _requireNonEmpty(sku, 'sku');
    _requirePositive(priceMinor, 'priceMinor');
  }

  final String id;
  final String name;
  final String sku;
  final int priceMinor;
  final String? categoryId;
  final String? description;
}

final class Variant {
  Variant({
    required this.id,
    required this.productId,
    required this.name,
    required this.sku,
    required this.priceMinor,
    Map<String, String> attributes = const {},
  }) : attributes = Map.unmodifiable(attributes) {
    _requireNonEmpty(id, 'id');
    _requireNonEmpty(productId, 'productId');
    _requireNonEmpty(name, 'name');
    _requireNonEmpty(sku, 'sku');
    _requirePositive(priceMinor, 'priceMinor');
  }

  final String id;
  final String productId;
  final String name;
  final String sku;
  final int priceMinor;
  final Map<String, String> attributes;
}

final class InventoryAvailability {
  InventoryAvailability({
    required this.variantId,
    required this.available,
    this.warehouseId,
  }) {
    _requireNonEmpty(variantId, 'variantId');
    _requireNonNegative(available, 'available');
  }

  final String variantId;
  final int available;
  final String? warehouseId;
}

final class CustomerProfile {
  CustomerProfile({
    required this.id,
    required this.identityId,
    required this.displayName,
    required this.email,
  }) {
    _requireNonEmpty(id, 'id');
    _requireNonEmpty(identityId, 'identityId');
  }

  final String id;
  final String identityId;
  final String displayName;
  final String email;
}

final class BusinessAccount {
  BusinessAccount({
    required this.id,
    required this.name,
    this.registrationNumber,
  }) {
    _requireNonEmpty(id, 'id');
    _requireNonEmpty(name, 'name');
  }

  final String id;
  final String name;
  final String? registrationNumber;
}

final class AccountMembership {
  AccountMembership({
    required this.accountId,
    required this.identityId,
    required this.role,
  }) {
    _requireNonEmpty(accountId, 'accountId');
    _requireNonEmpty(identityId, 'identityId');
  }

  final String accountId;
  final String identityId;
  final UserRole role;
}

final class CreditSnapshot {
  CreditSnapshot({
    required this.accountId,
    required this.creditLimitMinor,
    required this.availableCreditMinor,
  }) {
    _requireNonEmpty(accountId, 'accountId');
    _requireNonNegative(creditLimitMinor, 'creditLimitMinor');
    _requireNonNegative(availableCreditMinor, 'availableCreditMinor');
  }

  final String accountId;
  final int creditLimitMinor;
  final int availableCreditMinor;
}

final class CartItem {
  CartItem({
    required this.productId,
    required this.variantId,
    required this.quantity,
    required this.unitPriceMinor,
  }) {
    _requireNonEmpty(productId, 'productId');
    _requireNonEmpty(variantId, 'variantId');
    _requirePositive(quantity, 'quantity');
    _requirePositive(unitPriceMinor, 'unitPriceMinor');
  }

  final String productId;
  final String variantId;
  final int quantity;
  final int unitPriceMinor;

  int get lineTotalMinor => quantity * unitPriceMinor;
}

final class Cart {
  Cart({
    required this.id,
    List<CartItem> items = const [],
  }) : items = List.unmodifiable(items) {
    _requireNonEmpty(id, 'id');
  }

  final String id;
  final List<CartItem> items;

  int get itemCount => items.fold(0, (total, item) => total + item.quantity);

  int get subtotalMinor =>
      items.fold(0, (total, item) => total + item.lineTotalMinor);
}

final class OrderItem {
  OrderItem({
    required this.productId,
    required this.variantId,
    required this.quantity,
    required this.unitPriceMinor,
  }) {
    _requireNonEmpty(productId, 'productId');
    _requireNonEmpty(variantId, 'variantId');
    _requirePositive(quantity, 'quantity');
    _requirePositive(unitPriceMinor, 'unitPriceMinor');
  }

  final String productId;
  final String variantId;
  final int quantity;
  final int unitPriceMinor;

  int get lineTotalMinor => quantity * unitPriceMinor;
}

final class Order {
  Order({
    required this.id,
    List<OrderItem> items = const [],
    this.status = OrderStatus.pending,
    int? totalMinor,
  })  : items = List.unmodifiable(items),
        totalMinor = totalMinor ??
            items.fold(0, (total, item) => total + item.lineTotalMinor) {
    _requireNonEmpty(id, 'id');
    _requireNonNegative(this.totalMinor, 'totalMinor');
  }

  factory Order.fromCart(Cart cart, {required String id}) {
    return Order(
      id: id,
      items: cart.items
          .map(
            (item) => OrderItem(
              productId: item.productId,
              variantId: item.variantId,
              quantity: item.quantity,
              unitPriceMinor: item.unitPriceMinor,
            ),
          )
          .toList(),
      status: OrderStatus.pending,
      totalMinor: cart.subtotalMinor,
    );
  }

  final String id;
  final List<OrderItem> items;
  final OrderStatus status;
  final int totalMinor;
}

final class Rfq {
  Rfq({
    required this.id,
    required this.accountId,
    List<CartItem> items = const [],
    this.status = RfqStatus.submitted,
    this.message,
  }) : items = List.unmodifiable(items) {
    _requireNonEmpty(id, 'id');
    _requireNonEmpty(accountId, 'accountId');
  }

  final String id;
  final String accountId;
  final List<CartItem> items;
  final RfqStatus status;
  final String? message;
}

final class Quotation {
  Quotation({
    required this.id,
    required this.rfqId,
    required this.totalMinor,
    this.status = QuotationStatus.draft,
    this.validUntil,
  }) {
    _requireNonEmpty(id, 'id');
    _requireNonEmpty(rfqId, 'rfqId');
    _requireNonNegative(totalMinor, 'totalMinor');
  }

  final String id;
  final String rfqId;
  final int totalMinor;
  final QuotationStatus status;
  final DateTime? validUntil;
}

void _requireNonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}

void _requirePositive(int value, String name) {
  if (value <= 0) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
}

void _requireNonNegative(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, 'must not be negative');
  }
}
