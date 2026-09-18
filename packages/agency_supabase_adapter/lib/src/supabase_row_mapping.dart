import 'dart:math';

import 'package:agency_production_core/agency_production_core.dart';

/// Generates a UUID v4 suitable for Supabase `text` primary keys.
String generateSupabaseId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

Product productFromRow(Map<String, dynamic> row) => Product(
  id: stringValue(row, 'id'),
  name: stringValue(row, 'name'),
  sku: stringValue(row, 'sku'),
  priceMinor: intValue(row, 'retail_price_minor'),
  categoryId: nullableString(row, 'category_id'),
  description: nullableString(row, 'description'),
);

Variant variantFromRow(Map<String, dynamic> row) => Variant(
  id: stringValue(row, 'id'),
  productId: stringValue(row, 'product_id'),
  name: stringValue(row, 'name'),
  sku: stringValue(row, 'sku'),
  priceMinor: intValue(row, 'price_minor'),
  attributes: stringMapValue(row['attributes']),
);

InventoryAvailability inventoryFromRow(Map<String, dynamic> row) =>
    InventoryAvailability(
      variantId: stringValue(row, 'variant_id'),
      available: intValue(row, 'available'),
      warehouseId: nullableString(row, 'warehouse_id'),
    );

CustomerProfile customerProfileFromRow(Map<String, dynamic> row) =>
    CustomerProfile(
      id: stringValue(row, 'id'),
      identityId: stringValue(row, 'identity_id'),
      displayName: stringValue(row, 'display_name'),
      email: stringValue(row, 'email'),
    );

Map<String, Object?> customerProfileToRow(CustomerProfile profile) => {
  'id': profile.id,
  'identity_id': profile.identityId,
  'display_name': profile.displayName,
  'email': profile.email,
};

BusinessAccount businessAccountFromRow(Map<String, dynamic> row) =>
    BusinessAccount(
      id: stringValue(row, 'id'),
      name: stringValue(row, 'name'),
      registrationNumber: nullableString(row, 'registration_number'),
    );

AccountMembership accountMembershipFromRow(Map<String, dynamic> row) =>
    AccountMembership(
      accountId: stringValue(row, 'account_id'),
      identityId: stringValue(row, 'identity_id'),
      role: parseUserRole(nullableString(row, 'role')),
    );

CreditSnapshot creditSnapshotFromRow(Map<String, dynamic> row) =>
    CreditSnapshot(
      accountId: stringValue(row, 'account_id'),
      creditLimitMinor: intValue(row, 'credit_limit_minor'),
      availableCreditMinor: intValue(row, 'available_credit_minor'),
    );

CartItem cartItemFromRow(Map<String, dynamic> row) => CartItem(
  productId: stringValue(row, 'product_id'),
  variantId: stringValue(row, 'variant_id'),
  quantity: intValue(row, 'quantity'),
  unitPriceMinor: intValue(row, 'unit_price_minor'),
);

Map<String, Object?> cartItemToRow(String cartId, CartItem item) => {
  'cart_id': cartId,
  'product_id': item.productId,
  'variant_id': item.variantId,
  'quantity': item.quantity,
  'unit_price_minor': item.unitPriceMinor,
};

Cart cartFromRow(
  Map<String, dynamic> row,
  List<Map<String, dynamic>> itemRows,
) => Cart(
  id: stringValue(row, 'id'),
  items: itemRows.map(cartItemFromRow).toList(),
);

OrderItem orderItemFromRow(Map<String, dynamic> row) => OrderItem(
  productId: stringValue(row, 'product_id'),
  variantId: stringValue(row, 'variant_id'),
  quantity: intValue(row, 'quantity'),
  unitPriceMinor: intValue(row, 'unit_price_minor'),
);

Order orderFromRow(
  Map<String, dynamic> row,
  List<Map<String, dynamic>> itemRows,
) => Order(
  id: stringValue(row, 'id'),
  items: itemRows.map(orderItemFromRow).toList(),
  status: parseOrderStatus(nullableString(row, 'status')),
  totalMinor: intValue(row, 'total_minor'),
);

Rfq rfqFromRow(
  Map<String, dynamic> row,
  List<Map<String, dynamic>> itemRows,
) => Rfq(
  id: stringValue(row, 'id'),
  accountId: stringValue(row, 'account_id'),
  items: itemRows.map(cartItemFromRow).toList(),
  status: parseRfqStatus(nullableString(row, 'status')),
  message: nullableString(row, 'message'),
);

Quotation quotationFromRow(Map<String, dynamic> row) => Quotation(
  id: stringValue(row, 'id'),
  rfqId: stringValue(row, 'rfq_id'),
  totalMinor: intValue(row, 'total_minor'),
  status: parseQuotationStatus(nullableString(row, 'status')),
  validUntil: dateTimeValue(row['valid_until']),
);

UserRole parseUserRole(String? wire) => switch (wire) {
  'b2b_buyer' || 'b2bBuyer' => UserRole.b2bBuyer,
  'b2b_manager' || 'b2bManager' => UserRole.b2bManager,
  'admin' => UserRole.admin,
  _ => UserRole.consumer,
};

OrderStatus parseOrderStatus(String? wire) => OrderStatus.values.firstWhere(
  (status) => status.name == wire,
  orElse: () => OrderStatus.pending,
);

RfqStatus parseRfqStatus(String? wire) => switch (wire) {
  'quoted' => RfqStatus.quoted,
  'converted' => RfqStatus.converted,
  'rejected' => RfqStatus.rejected,
  _ => RfqStatus.submitted,
};

QuotationStatus parseQuotationStatus(String? wire) =>
    QuotationStatus.values.firstWhere(
      (status) => status.name == wire,
      orElse: () => QuotationStatus.draft,
    );

String stringValue(Map<String, dynamic> row, String key) =>
    row[key]?.toString() ?? '';

String? nullableString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value == null) {
    return null;
  }
  return value.toString();
}

int intValue(Map<String, dynamic> row, String key) {
  final value = row[key];
  return switch (value) {
    int() => value,
    num() => value.toInt(),
    String() => int.tryParse(value) ?? 0,
    _ => 0,
  };
}

DateTime? dateTimeValue(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  return DateTime.tryParse(value.toString());
}

Map<String, String> stringMapValue(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): entry.value?.toString() ?? '',
    };
  }
  return const {};
}
