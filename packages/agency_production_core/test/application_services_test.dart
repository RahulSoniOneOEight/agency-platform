import 'package:agency_production_core/agency_production_core.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// In-memory doubles (provider-neutral, deterministic).
// ---------------------------------------------------------------------------

final class FakeCatalogRepository implements CatalogRepository {
  FakeCatalogRepository({
    List<Product> products = const [],
    Map<String, List<Variant>> variants = const {},
    this.error,
  })  : products = List.unmodifiable(products),
        variants = {
          for (final entry in variants.entries)
            entry.key: List.unmodifiable(entry.value),
        };

  final List<Product> products;
  final Map<String, List<Variant>> variants;
  final Object? error;
  final List<String?> requestedCategories = [];

  @override
  Future<List<Product>> listProducts({String? categoryId}) async {
    requestedCategories.add(categoryId);
    if (error != null) {
      throw error!;
    }
    if (categoryId == null) {
      return products;
    }
    return products.where((product) => product.categoryId == categoryId).toList();
  }

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
  Future<List<Variant>> listVariants(String productId) async {
    if (error != null) {
      throw error!;
    }
    return variants[productId] ?? const [];
  }
}

final class FakeInventoryRepository implements InventoryRepository {
  FakeInventoryRepository([Map<String, InventoryAvailability>? levels])
      : levels = levels ?? {};

  final Map<String, InventoryAvailability> levels;
  final List<String> requestedVariants = [];

  @override
  Future<InventoryAvailability?> getAvailability(String variantId) async =>
      levels[variantId];

  @override
  Future<List<InventoryAvailability>> listAvailability(
    Iterable<String> variantIds,
  ) async {
    final ids = variantIds.toList();
    requestedVariants.addAll(ids);
    return [
      for (final id in ids)
        if (levels[id] != null) levels[id]!,
    ];
  }
}

final class FakeCartRepository implements CartRepository {
  FakeCartRepository({Map<String, Cart>? carts, this.error})
      : carts = carts ?? {};

  final Map<String, Cart> carts;
  final Object? error;

  @override
  Future<Cart?> getCart(String cartId) async {
    if (error != null) {
      throw error!;
    }
    return carts[cartId];
  }

  @override
  Future<Cart> saveCart(Cart cart) async {
    carts[cart.id] = cart;
    return cart;
  }
}

final class FakeOrderRepository implements OrderRepository {
  FakeOrderRepository({this.error});

  final Object? error;
  final Map<String, Order> ordersByKey = {};
  int _sequence = 0;

  int get orderCount => ordersByKey.length;

  @override
  Future<Order> createOrder({
    required Cart cart,
    required IdempotencyKey idempotencyKey,
  }) async {
    if (error != null) {
      throw error!;
    }
    final existing = ordersByKey[idempotencyKey.value];
    if (existing != null) {
      return existing;
    }
    final order = Order.fromCart(cart, id: 'order-${++_sequence}');
    ordersByKey[idempotencyKey.value] = order;
    return order;
  }
}

final class FakeQuoteRepository implements QuoteRepository {
  FakeQuoteRepository({this.error});

  final Object? error;
  final Map<String, Rfq> rfqs = {};
  final Map<String, Quotation> quotations = {};
  final Map<String, String> _rfqByKey = {};
  final Map<String, String> _quotationByKey = {};
  int _sequence = 0;

  @override
  Future<Rfq> createRfq({
    required String accountId,
    required List<CartItem> items,
    required IdempotencyKey idempotencyKey,
    String? message,
  }) async {
    if (error != null) {
      throw error!;
    }
    final existing = _rfqByKey[idempotencyKey.value];
    if (existing != null) {
      return rfqs[existing]!;
    }
    final id = 'rfq-${++_sequence}';
    final rfq = Rfq(
      id: id,
      accountId: accountId,
      items: items,
      message: message,
    );
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
    if (error != null) {
      throw error!;
    }
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

final class FakeAccountRepository implements AccountRepository {
  FakeAccountRepository({
    List<BusinessAccount> accounts = const [],
    List<AccountMembership> memberships = const [],
    Map<String, CreditSnapshot> credits = const {},
    this.error,
  })  : accounts = List.unmodifiable(accounts),
        memberships = List.unmodifiable(memberships),
        credits = Map.unmodifiable(credits);

  final List<BusinessAccount> accounts;
  final List<AccountMembership> memberships;
  final Map<String, CreditSnapshot> credits;
  final Object? error;

  @override
  Future<List<BusinessAccount>> listAccountsForIdentity(
    String identityId,
  ) async {
    if (error != null) {
      throw error!;
    }
    final ids = memberships
        .where((membership) => membership.identityId == identityId)
        .map((membership) => membership.accountId)
        .toSet();
    return accounts.where((account) => ids.contains(account.id)).toList();
  }

  @override
  Future<AccountMembership?> getMembership({
    required String accountId,
    required String identityId,
  }) async {
    if (error != null) {
      throw error!;
    }
    for (final membership in memberships) {
      if (membership.accountId == accountId &&
          membership.identityId == identityId) {
        return membership;
      }
    }
    return null;
  }

  @override
  Future<CreditSnapshot?> getCreditSnapshot(String accountId) async {
    if (error != null) {
      throw error!;
    }
    return credits[accountId];
  }
}

// ---------------------------------------------------------------------------
// Fixtures.
// ---------------------------------------------------------------------------

const _identityId = 'user-1';
const _accountId = 'account-1';

CartItem _item({int quantity = 2, int unitPriceMinor = 1500}) => CartItem(
      productId: 'product-1',
      variantId: 'variant-1',
      quantity: quantity,
      unitPriceMinor: unitPriceMinor,
    );

Cart _cart({String id = 'cart-1'}) => Cart(id: id, items: [_item()]);

BusinessAccount _account() =>
    BusinessAccount(id: _accountId, name: 'Acme Retail');

AccountMembership _membership({UserRole role = UserRole.b2bBuyer}) =>
    AccountMembership(
      accountId: _accountId,
      identityId: _identityId,
      role: role,
    );

CreditSnapshot _credit({int availableCreditMinor = 120000}) => CreditSnapshot(
      accountId: _accountId,
      creditLimitMinor: 500000,
      availableCreditMinor: availableCreditMinor,
    );

FakeAccountRepository _accountRepository({
  UserRole role = UserRole.b2bBuyer,
  bool withMembership = true,
  int availableCreditMinor = 120000,
}) =>
    FakeAccountRepository(
      accounts: [_account()],
      memberships: withMembership ? [_membership(role: role)] : const [],
      credits: {_accountId: _credit(availableCreditMinor: availableCreditMinor)},
    );

Future<Quotation> _persistQuotation(
  FakeQuoteRepository quotes, {
  QuotationStatus status = QuotationStatus.sent,
  int totalMinor = 3000,
}) async {
  final rfq = await quotes.createRfq(
    accountId: _accountId,
    items: [_item()],
    idempotencyKey: IdempotencyKey('rfq-setup'),
  );
  return quotes.saveQuotation(
    quotation: Quotation(
      id: 'quotation-1',
      rfqId: rfq.id,
      totalMinor: totalMinor,
      status: status,
    ),
    idempotencyKey: IdempotencyKey('quotation-setup'),
  );
}

Future<DomainFailure> _captureFailure(Future<void> Function() action) async {
  try {
    await action();
  } on DomainFailure catch (failure) {
    return failure;
  }
  fail('Expected a DomainFailure to be thrown');
}

void main() {
  group('CommerceService.loadCatalog', () {
    late FakeCatalogRepository catalog;
    late FakeInventoryRepository inventory;
    late CommerceService service;

    setUp(() {
      catalog = FakeCatalogRepository(
        products: [
          Product(
            id: 'product-1',
            name: 'Hub',
            sku: 'SKU-1',
            priceMinor: 1000,
            categoryId: 'cat-1',
          ),
        ],
        variants: {
          'product-1': [
            Variant(
              id: 'variant-1',
              productId: 'product-1',
              name: 'Default',
              sku: 'SKU-1',
              priceMinor: 1000,
            ),
          ],
        },
      );
      inventory = FakeInventoryRepository({
        'variant-1': InventoryAvailability(variantId: 'variant-1', available: 7),
      });
      service = CommerceService(catalog: catalog, inventory: inventory);
    });

    test('composes products, variants, and availability', () async {
      final view = await service.loadCatalog();

      expect(view, hasLength(1));
      expect(view.single.product.id, 'product-1');
      expect(view.single.variants, hasLength(1));
      expect(view.single.variants.single.variant.id, 'variant-1');
      expect(view.single.variants.single.available, 7);
    });

    test('passes the category filter through to the catalog', () async {
      await service.loadCatalog(categoryId: 'cat-1');

      expect(catalog.requestedCategories, ['cat-1']);
    });

    test('reports a retryable timeout with the use-case operation', () async {
      final failing = CommerceService(
        catalog: FakeCatalogRepository(
          error: DomainFailure(
            code: DomainFailureCode.timeout,
            operation: 'list_products',
            retryable: true,
            message: 'Timed out',
          ),
        ),
        inventory: inventory,
      );

      final failure = await _captureFailure(failing.loadCatalog);

      expect(failure.code, DomainFailureCode.timeout);
      expect(failure.retryable, isTrue);
      expect(failure.operation, 'load_catalog');
    });
  });

  group('OrderService.placeOrder', () {
    late FakeCartRepository carts;
    late FakeOrderRepository orders;
    late OrderService service;

    setUp(() {
      carts = FakeCartRepository(carts: {'cart-1': _cart()});
      orders = FakeOrderRepository();
      service = OrderService(carts: carts, orders: orders);
    });

    test('creates exactly one order for a cart', () async {
      final order = await service.placeOrder(
        cartId: 'cart-1',
        idempotencyKey: IdempotencyKey('order-key-1'),
      );

      expect(order.totalMinor, 3000);
      expect(order.items, hasLength(1));
      expect(orders.orderCount, 1);
    });

    test('returns the same order identity for a duplicate submission', () async {
      final key = IdempotencyKey('order-key-1');

      final first = await service.placeOrder(
        cartId: 'cart-1',
        idempotencyKey: key,
      );
      final second = await service.placeOrder(
        cartId: 'cart-1',
        idempotencyKey: key,
      );

      expect(identical(first, second), isTrue);
      expect(second.id, first.id);
      expect(orders.orderCount, 1);
    });

    test('rejects a missing cart with a non-retryable validation failure',
        () async {
      final failure = await _captureFailure(
        () => service.placeOrder(
          cartId: 'missing',
          idempotencyKey: IdempotencyKey('order-key-2'),
        ),
      );

      expect(failure.code, DomainFailureCode.validation);
      expect(failure.retryable, isFalse);
      expect(failure.operation, 'place_order');
      expect(orders.orderCount, 0);
    });

    test('rejects an empty cart with a non-retryable validation failure',
        () async {
      final emptyService = OrderService(
        carts: FakeCartRepository(carts: {'cart-empty': Cart(id: 'cart-empty')}),
        orders: orders,
      );

      final failure = await _captureFailure(
        () => emptyService.placeOrder(
          cartId: 'cart-empty',
          idempotencyKey: IdempotencyKey('order-key-3'),
        ),
      );

      expect(failure.code, DomainFailureCode.validation);
      expect(failure.retryable, isFalse);
    });

    test('distinguishes retryable timeouts from non-retryable validation',
        () async {
      final timeoutService = OrderService(
        carts: FakeCartRepository(
          error: DomainFailure(
            code: DomainFailureCode.timeout,
            operation: 'get_cart',
            retryable: true,
            message: 'Timed out',
          ),
        ),
        orders: orders,
      );

      final timeoutFailure = await _captureFailure(
        () => timeoutService.placeOrder(
          cartId: 'cart-1',
          idempotencyKey: IdempotencyKey('order-key-4'),
        ),
      );
      final validationFailure = await _captureFailure(
        () => service.placeOrder(
          cartId: 'missing',
          idempotencyKey: IdempotencyKey('order-key-5'),
        ),
      );

      expect(timeoutFailure.retryable, isTrue);
      expect(validationFailure.retryable, isFalse);
    });

    test('does not catch non-DomainFailure exceptions from ports', () async {
      final leakingService = OrderService(
        carts: FakeCartRepository(error: StateError('provider leaked')),
        orders: orders,
      );

      await expectLater(
        leakingService.placeOrder(
          cartId: 'cart-1',
          idempotencyKey: IdempotencyKey('order-key-6'),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('QuoteService B2B account context', () {
    test('resolves membership and credit for a member identity', () async {
      final service = QuoteService(
        quotes: FakeQuoteRepository(),
        accounts: _accountRepository(),
        orders: FakeOrderRepository(),
      );

      final context = await service.loadAccountContext(
        accountId: _accountId,
        identityId: _identityId,
      );

      expect(context.account.name, 'Acme Retail');
      expect(context.membership.role, UserRole.b2bBuyer);
      expect(context.credit!.availableCreditMinor, 120000);
    });

    test('denies access without a matching membership', () async {
      final service = QuoteService(
        quotes: FakeQuoteRepository(),
        accounts: _accountRepository(withMembership: false),
        orders: FakeOrderRepository(),
      );

      final failure = await _captureFailure(
        () => service.loadAccountContext(
          accountId: _accountId,
          identityId: _identityId,
        ),
      );

      expect(failure.code, DomainFailureCode.forbidden);
      expect(failure.retryable, isFalse);
      expect(failure.operation, 'load_account_context');
    });
  });

  group('QuoteService.createRfq', () {
    test('creates exactly one RFQ for a member and dedupes by key', () async {
      final quotes = FakeQuoteRepository();
      final service = QuoteService(
        quotes: quotes,
        accounts: _accountRepository(),
        orders: FakeOrderRepository(),
      );
      final key = IdempotencyKey('rfq-key-1');

      final first = await service.createRfq(
        accountId: _accountId,
        identityId: _identityId,
        items: [_item()],
        idempotencyKey: key,
      );
      final second = await service.createRfq(
        accountId: _accountId,
        identityId: _identityId,
        items: [_item()],
        idempotencyKey: key,
      );

      expect(identical(first, second), isTrue);
      expect(quotes.rfqs, hasLength(1));
      expect(first.accountId, _accountId);
    });

    test('denies an identity without a membership', () async {
      final service = QuoteService(
        quotes: FakeQuoteRepository(),
        accounts: _accountRepository(withMembership: false),
        orders: FakeOrderRepository(),
      );

      final failure = await _captureFailure(
        () => service.createRfq(
          accountId: _accountId,
          identityId: _identityId,
          items: [_item()],
          idempotencyKey: IdempotencyKey('rfq-key-2'),
        ),
      );

      expect(failure.code, DomainFailureCode.forbidden);
      expect(failure.retryable, isFalse);
      expect(failure.operation, 'create_rfq');
    });

    test('rejects an RFQ without items as non-retryable validation', () async {
      final service = QuoteService(
        quotes: FakeQuoteRepository(),
        accounts: _accountRepository(),
        orders: FakeOrderRepository(),
      );

      final failure = await _captureFailure(
        () => service.createRfq(
          accountId: _accountId,
          identityId: _identityId,
          items: const [],
          idempotencyKey: IdempotencyKey('rfq-key-3'),
        ),
      );

      expect(failure.code, DomainFailureCode.validation);
      expect(failure.retryable, isFalse);
    });
  });

  group('QuoteService.convertQuotationToOrder', () {
    test('converts a sent quotation into an order', () async {
      final quotes = FakeQuoteRepository();
      await _persistQuotation(quotes);
      final orders = FakeOrderRepository();
      final service = QuoteService(
        quotes: quotes,
        accounts: _accountRepository(),
        orders: orders,
      );

      final order = await service.convertQuotationToOrder(
        quotationId: 'quotation-1',
        identityId: _identityId,
        idempotencyKey: IdempotencyKey('convert-key-1'),
      );

      expect(order.totalMinor, 3000);
      expect(order.items, hasLength(1));
      expect(orders.orderCount, 1);
    });

    test('dedupes a repeated conversion by idempotency key', () async {
      final quotes = FakeQuoteRepository();
      await _persistQuotation(quotes);
      final orders = FakeOrderRepository();
      final service = QuoteService(
        quotes: quotes,
        accounts: _accountRepository(),
        orders: orders,
      );
      final key = IdempotencyKey('convert-key-1');

      final first = await service.convertQuotationToOrder(
        quotationId: 'quotation-1',
        identityId: _identityId,
        idempotencyKey: key,
      );
      final second = await service.convertQuotationToOrder(
        quotationId: 'quotation-1',
        identityId: _identityId,
        idempotencyKey: key,
      );

      expect(identical(first, second), isTrue);
      expect(orders.orderCount, 1);
    });

    test('rejects conversion when available credit is insufficient', () async {
      final quotes = FakeQuoteRepository();
      await _persistQuotation(quotes, totalMinor: 3000);
      final orders = FakeOrderRepository();
      final service = QuoteService(
        quotes: quotes,
        accounts: _accountRepository(availableCreditMinor: 1000),
        orders: orders,
      );

      final failure = await _captureFailure(
        () => service.convertQuotationToOrder(
          quotationId: 'quotation-1',
          identityId: _identityId,
          idempotencyKey: IdempotencyKey('convert-key-2'),
        ),
      );

      expect(failure.code, DomainFailureCode.conflict);
      expect(failure.retryable, isFalse);
      expect(failure.operation, 'convert_quotation_to_order');
      expect(orders.orderCount, 0);
    });

    test('denies conversion for an identity without a membership', () async {
      final quotes = FakeQuoteRepository();
      await _persistQuotation(quotes);
      final orders = FakeOrderRepository();
      final service = QuoteService(
        quotes: quotes,
        accounts: _accountRepository(withMembership: false),
        orders: orders,
      );

      final failure = await _captureFailure(
        () => service.convertQuotationToOrder(
          quotationId: 'quotation-1',
          identityId: _identityId,
          idempotencyKey: IdempotencyKey('convert-key-3'),
        ),
      );

      expect(failure.code, DomainFailureCode.forbidden);
      expect(failure.retryable, isFalse);
      expect(orders.orderCount, 0);
    });

    test('rejects an unknown quotation as non-retryable validation', () async {
      final service = QuoteService(
        quotes: FakeQuoteRepository(),
        accounts: _accountRepository(),
        orders: FakeOrderRepository(),
      );

      final failure = await _captureFailure(
        () => service.convertQuotationToOrder(
          quotationId: 'missing',
          identityId: _identityId,
          idempotencyKey: IdempotencyKey('convert-key-4'),
        ),
      );

      expect(failure.code, DomainFailureCode.validation);
      expect(failure.retryable, isFalse);
    });

    test('rejects a non-convertible draft quotation', () async {
      final quotes = FakeQuoteRepository();
      await _persistQuotation(quotes, status: QuotationStatus.draft);
      final orders = FakeOrderRepository();
      final service = QuoteService(
        quotes: quotes,
        accounts: _accountRepository(),
        orders: orders,
      );

      final failure = await _captureFailure(
        () => service.convertQuotationToOrder(
          quotationId: 'quotation-1',
          identityId: _identityId,
          idempotencyKey: IdempotencyKey('convert-key-5'),
        ),
      );

      expect(failure.code, DomainFailureCode.validation);
      expect(failure.retryable, isFalse);
      expect(orders.orderCount, 0);
    });
  });
}
