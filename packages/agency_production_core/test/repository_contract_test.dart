import 'package:agency_production_core/agency_production_core.dart';
import 'package:flutter_test/flutter_test.dart';

final class MemoryOrderRepository implements OrderRepository {
  final orders = <String, Order>{};

  @override
  Future<Order> createOrder({
    required Cart cart,
    required IdempotencyKey idempotencyKey,
    int? totalMinor,
    String? accountId,
  }) async {
    return orders.putIfAbsent(
      idempotencyKey.value,
      () => Order.fromCart(cart, id: 'order-1', totalMinor: totalMinor),
    );
  }
}

final class MemoryCartRepository implements CartRepository {
  final carts = <String, Cart>{};

  @override
  Future<Cart?> getCart(String cartId) async => carts[cartId];

  @override
  Future<Cart> saveCart(Cart cart, {String? accountId}) async {
    carts[cart.id] = cart;
    return cart;
  }
}

final class MemoryCatalogRepository implements CatalogRepository {
  MemoryCatalogRepository({required this.products, required this.variants});

  final List<Product> products;
  final List<Variant> variants;

  @override
  Future<List<Product>> listProducts({String? categoryId}) async =>
      categoryId == null
          ? products
          : products.where((p) => p.categoryId == categoryId).toList();

  @override
  Future<Product?> getProduct(String productId) async {
    for (final product in products) {
      if (product.id == productId) {
        return product;
      }
    }
    return null;
  }

  @override
  Future<List<Variant>> listVariants(String productId) async =>
      variants.where((v) => v.productId == productId).toList();
}

final class MemoryInventoryRepository implements InventoryRepository {
  MemoryInventoryRepository(this.levels);

  final Map<String, InventoryAvailability> levels;

  @override
  Future<InventoryAvailability?> getAvailability(String variantId) async =>
      levels[variantId];

  @override
  Future<List<InventoryAvailability>> listAvailability(
    Iterable<String> variantIds,
  ) async =>
      [for (final id in variantIds) if (levels[id] != null) levels[id]!];
}

final class MemoryAccountRepository implements AccountRepository {
  MemoryAccountRepository({
    required this.accounts,
    required this.memberships,
    required this.credits,
  });

  final List<BusinessAccount> accounts;
  final List<AccountMembership> memberships;
  final Map<String, CreditSnapshot> credits;

  @override
  Future<List<BusinessAccount>> listAccountsForIdentity(
    String identityId,
  ) async {
    final accountIds = memberships
        .where((m) => m.identityId == identityId)
        .map((m) => m.accountId)
        .toSet();
    return accounts.where((a) => accountIds.contains(a.id)).toList();
  }

  @override
  Future<AccountMembership?> getMembership({
    required String accountId,
    required String identityId,
  }) async {
    for (final membership in memberships) {
      if (membership.accountId == accountId &&
          membership.identityId == identityId) {
        return membership;
      }
    }
    return null;
  }

  @override
  Future<CreditSnapshot?> getCreditSnapshot(String accountId) async =>
      credits[accountId];
}

final class MemoryQuoteRepository implements QuoteRepository {
  final rfqs = <String, Rfq>{};
  final quotations = <String, Quotation>{};
  final _rfqByKey = <String, String>{};
  final _quotationByKey = <String, String>{};
  int _sequence = 0;

  @override
  Future<Rfq> createRfq({
    required String accountId,
    required List<CartItem> items,
    required IdempotencyKey idempotencyKey,
    String? message,
  }) async {
    final existing = _rfqByKey[idempotencyKey.value];
    if (existing != null) {
      return rfqs[existing]!;
    }
    final id = 'rfq-${++_sequence}';
    final rfq = Rfq(id: id, accountId: accountId, items: items, message: message);
    rfqs[id] = rfq;
    _rfqByKey[idempotencyKey.value] = id;
    return rfq;
  }

  @override
  Future<Rfq?> getRfq(String rfqId) async => rfqs[rfqId];

  @override
  Future<Quotation> saveQuotation({
    required Quotation quotation,
    required IdempotencyKey idempotencyKey,
  }) async {
    final existing = _quotationByKey[idempotencyKey.value];
    if (existing != null) {
      return quotations[existing]!;
    }
    quotations[quotation.id] = quotation;
    _quotationByKey[idempotencyKey.value] = quotation.id;
    return quotation;
  }

  @override
  Future<Quotation?> getQuotation(String quotationId) async =>
      quotations[quotationId];
}

final class MemoryPaymentPort implements PaymentPort {
  final _authorizations = <String, PaymentResult>{};

  @override
  Future<PaymentResult> authorizePayment({
    required String orderId,
    required int amountMinor,
    required String currency,
    required IdempotencyKey idempotencyKey,
  }) async =>
      _authorizations.putIfAbsent(
        idempotencyKey.value,
        () => PaymentResult(
          paymentId: 'payment-1',
          status: PaymentStatus.authorized,
          amountMinor: amountMinor,
          currency: currency,
        ),
      );

  @override
  Future<PaymentResult> refundPayment({
    required String paymentId,
    required int amountMinor,
    required IdempotencyKey idempotencyKey,
  }) async => PaymentResult(
    paymentId: paymentId,
    status: PaymentStatus.refunded,
    amountMinor: amountMinor,
    currency: 'USD',
  );
}

final class MemoryShippingPort implements ShippingPort {
  final shipments = <String, Shipment>{};

  @override
  Future<Shipment> createShipment({
    required String orderId,
    required String destinationAddress,
    required IdempotencyKey idempotencyKey,
  }) async {
    final shipment = Shipment(
      shipmentId: 'shipment-1',
      orderId: orderId,
      carrier: 'fake-carrier',
      trackingNumber: 'track-1',
      status: ShipmentStatus.created,
    );
    shipments[shipment.shipmentId] = shipment;
    return shipment;
  }

  @override
  Future<Shipment?> trackShipment(String shipmentId) async =>
      shipments[shipmentId];
}

final class MemoryErpPort implements ErpPort {
  @override
  Future<List<InventoryAvailability>> fetchInventory(
    Iterable<String> variantIds,
  ) async => [
    for (final id in variantIds)
      InventoryAvailability(variantId: id, available: 10),
  ];

  @override
  Future<Quotation> requestQuotation({
    required Rfq rfq,
    required IdempotencyKey idempotencyKey,
  }) async => Quotation(id: 'quotation-1', rfqId: rfq.id, totalMinor: 1000);

  @override
  Future<ErpSyncReceipt> syncOrder({
    required Order order,
    required IdempotencyKey idempotencyKey,
  }) async => const ErpSyncReceipt(erpReference: 'erp-1', accepted: true);
}

final class MemoryCrmPort implements CrmPort {
  final _activities = <String, CrmActivityReceipt>{};

  @override
  Future<CrmActivityReceipt> recordActivity({
    required String identityId,
    required String activityType,
    required Map<String, String> attributes,
    required IdempotencyKey idempotencyKey,
  }) async =>
      _activities.putIfAbsent(
        idempotencyKey.value,
        () => const CrmActivityReceipt(activityId: 'crm-1', recorded: true),
      );
}

final class MemoryWhatsAppPort implements WhatsAppPort {
  final _messages = <String, WhatsAppMessageReceipt>{};

  @override
  Future<WhatsAppMessageReceipt> sendTemplateMessage({
    required String toPhoneNumber,
    required String templateName,
    required Map<String, String> parameters,
    required IdempotencyKey idempotencyKey,
  }) async =>
      _messages.putIfAbsent(
        idempotencyKey.value,
        () =>
            const WhatsAppMessageReceipt(messageId: 'wa-1', accepted: true),
      );
}

void main() {
  group('IdempotencyKey', () {
    test('requires a non-empty value', () {
      expect(() => IdempotencyKey('  '), throwsArgumentError);
    });

    test('compares by value', () {
      expect(IdempotencyKey('key-1'), IdempotencyKey('key-1'));
      expect(IdempotencyKey('key-1'), isNot(IdempotencyKey('key-2')));
      expect(IdempotencyKey('key-1').value, 'key-1');
    });
  });

  group('OrderRepository contract', () {
    test('the same idempotency key does not create two orders', () async {
      final repository = MemoryOrderRepository();
      final cart = Cart(
        id: 'cart-1',
        items: [
          CartItem(
            productId: 'product-1',
            variantId: 'variant-1',
            quantity: 2,
            unitPriceMinor: 1500,
          ),
        ],
      );
      final key = IdempotencyKey('order-key-1');

      final first = await repository.createOrder(
        cart: cart,
        idempotencyKey: key,
      );
      final second = await repository.createOrder(
        cart: cart,
        idempotencyKey: key,
      );

      expect(identical(first, second), isTrue);
      expect(repository.orders, hasLength(1));
      expect(first.id, 'order-1');
      expect(first.totalMinor, 3000);
    });

    test('a new idempotency key creates a separate order', () async {
      final repository = MemoryOrderRepository();
      final cart = Cart(id: 'cart-1');

      await repository.createOrder(
        cart: cart,
        idempotencyKey: IdempotencyKey('order-key-1'),
      );
      await repository.createOrder(
        cart: cart,
        idempotencyKey: IdempotencyKey('order-key-2'),
      );

      expect(repository.orders, hasLength(2));
    });
  });

  group('CartRepository contract', () {
    test('round-trips a cart by id', () async {
      final repository = MemoryCartRepository();
      final cart = Cart(
        id: 'cart-1',
        items: [
          CartItem(
            productId: 'product-1',
            variantId: 'variant-1',
            quantity: 1,
            unitPriceMinor: 1000,
          ),
        ],
      );

      expect(await repository.getCart('cart-1'), isNull);
      await repository.saveCart(cart);
      expect((await repository.getCart('cart-1'))!.subtotalMinor, 1000);
    });
  });

  group('catalog and inventory contracts', () {
    test('reads products, variants, and availability', () async {
      final catalog = MemoryCatalogRepository(
        products: [
          Product(
            id: 'product-1',
            name: 'Hub',
            sku: 'SKU-1',
            priceMinor: 1000,
            categoryId: 'cat-1',
          ),
        ],
        variants: [
          Variant(
            id: 'variant-1',
            productId: 'product-1',
            name: 'Default',
            sku: 'SKU-1',
            priceMinor: 1000,
          ),
        ],
      );
      final inventory = MemoryInventoryRepository({
        'variant-1': InventoryAvailability(variantId: 'variant-1', available: 7),
      });

      expect(await catalog.listProducts(), hasLength(1));
      expect(await catalog.listProducts(categoryId: 'cat-2'), isEmpty);
      expect((await catalog.getProduct('product-1'))!.name, 'Hub');
      expect(await catalog.getProduct('missing'), isNull);
      expect(await catalog.listVariants('product-1'), hasLength(1));
      expect((await inventory.getAvailability('variant-1'))!.available, 7);
      expect(await inventory.getAvailability('missing'), isNull);
      expect(
        await inventory.listAvailability(['variant-1', 'missing']),
        hasLength(1),
      );
    });
  });

  group('AccountRepository contract', () {
    late AppIdentity identity;
    late MemoryAccountRepository repository;

    setUp(() {
      identity = AppIdentity(
        id: 'user-1',
        email: 'buyer@example.test',
        displayName: 'Buyer',
        role: UserRole.consumer,
        memberships: [
          AccountMembership(
            accountId: 'account-1',
            identityId: 'user-1',
            role: UserRole.b2bBuyer,
          ),
          AccountMembership(
            accountId: 'account-2',
            identityId: 'user-1',
            role: UserRole.b2bManager,
          ),
        ],
      );
      repository = MemoryAccountRepository(
        accounts: [
          BusinessAccount(id: 'account-1', name: 'Acme Retail'),
          BusinessAccount(id: 'account-2', name: 'Globex Wholesale'),
        ],
        memberships: identity.memberships,
        credits: {
          'account-1': CreditSnapshot(
            accountId: 'account-1',
            creditLimitMinor: 500000,
            availableCreditMinor: 120000,
          ),
        },
      );
    });

    test(
      'resolves a different role per account instead of one global role',
      () async {
        expect(identity.role, UserRole.consumer);

        final first = await repository.getMembership(
          accountId: 'account-1',
          identityId: 'user-1',
        );
        final second = await repository.getMembership(
          accountId: 'account-2',
          identityId: 'user-1',
        );

        expect(first!.role, UserRole.b2bBuyer);
        expect(second!.role, UserRole.b2bManager);
        expect(first.role, isNot(identity.role));
        expect(second.role, isNot(identity.role));
      },
    );

    test('denies access to an account without a matching membership', () async {
      final membership = await repository.getMembership(
        accountId: 'account-3',
        identityId: 'user-1',
      );

      expect(membership, isNull);
    });

    test('lists only the accounts the identity belongs to', () async {
      final accounts = await repository.listAccountsForIdentity('user-1');

      expect(accounts.map((a) => a.id).toList(), ['account-1', 'account-2']);
      expect(await repository.listAccountsForIdentity('user-2'), isEmpty);
    });

    test('exposes credit per account', () async {
      final credit = await repository.getCreditSnapshot('account-1');

      expect(credit!.availableCreditMinor, 120000);
      expect(await repository.getCreditSnapshot('account-2'), isNull);
    });
  });

  group('QuoteRepository contract', () {
    test('the same idempotency key does not create two RFQs', () async {
      final repository = MemoryQuoteRepository();
      final key = IdempotencyKey('rfq-key-1');

      final first = await repository.createRfq(
        accountId: 'account-1',
        items: [
          CartItem(
            productId: 'product-1',
            variantId: 'variant-1',
            quantity: 3,
            unitPriceMinor: 2000,
          ),
        ],
        idempotencyKey: key,
      );
      final second = await repository.createRfq(
        accountId: 'account-1',
        items: const [],
        idempotencyKey: key,
      );

      expect(identical(first, second), isTrue);
      expect(repository.rfqs, hasLength(1));
      expect(first.id, 'rfq-1');
    });

    test('persists and reads quotations', () async {
      final repository = MemoryQuoteRepository();
      final quotation = Quotation(
        id: 'quotation-1',
        rfqId: 'rfq-1',
        totalMinor: 6000,
      );

      final saved = await repository.saveQuotation(
        quotation: quotation,
        idempotencyKey: IdempotencyKey('quotation-key-1'),
      );

      expect(identical(saved, quotation), isTrue);
      expect((await repository.getQuotation('quotation-1'))!.totalMinor, 6000);
    });
  });

  group('integration ports', () {
    test('payment authorization honors the idempotency key', () async {
      final port = MemoryPaymentPort();
      final key = IdempotencyKey('payment-key-1');

      final first = await port.authorizePayment(
        orderId: 'order-1',
        amountMinor: 3000,
        currency: 'USD',
        idempotencyKey: key,
      );
      final second = await port.authorizePayment(
        orderId: 'order-1',
        amountMinor: 3000,
        currency: 'USD',
        idempotencyKey: key,
      );

      expect(identical(first, second), isTrue);
      expect(first.status, PaymentStatus.authorized);
      expect(first.amountMinor, 3000);
    });

    test('shipping, erp, crm, and whatsapp ports are implementable', () async {
      final shipping = MemoryShippingPort();
      final shipment = await shipping.createShipment(
        orderId: 'order-1',
        destinationAddress: '1 Test Street',
        idempotencyKey: IdempotencyKey('ship-key-1'),
      );
      expect(shipment.status, ShipmentStatus.created);
      expect(await shipping.trackShipment('shipment-1'), same(shipment));
      expect(await shipping.trackShipment('missing'), isNull);

      final erp = MemoryErpPort();
      expect(await erp.fetchInventory(['variant-1']), hasLength(1));
      final quotation = await erp.requestQuotation(
        rfq: Rfq(id: 'rfq-1', accountId: 'account-1'),
        idempotencyKey: IdempotencyKey('erp-key-1'),
      );
      expect(quotation.rfqId, 'rfq-1');
      final receipt = await erp.syncOrder(
        order: Order(id: 'order-1'),
        idempotencyKey: IdempotencyKey('erp-key-2'),
      );
      expect(receipt.accepted, isTrue);

      final crm = MemoryCrmPort();
      final activity = await crm.recordActivity(
        identityId: 'user-1',
        activityType: 'order_placed',
        attributes: const {'orderId': 'order-1'},
        idempotencyKey: IdempotencyKey('crm-key-1'),
      );
      expect(activity.recorded, isTrue);

      final whatsApp = MemoryWhatsAppPort();
      final message = await whatsApp.sendTemplateMessage(
        toPhoneNumber: '+10000000000',
        templateName: 'order_confirmation',
        parameters: const {'orderId': 'order-1'},
        idempotencyKey: IdempotencyKey('wa-key-1'),
      );
      expect(message.accepted, isTrue);
    });
  });
}
