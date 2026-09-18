import 'package:agency_production_core/agency_production_core.dart';

/// Deterministic, fully synthetic seed for the reference-commerce dev/test
/// runtime.
///
/// Every value is a pure function of the code below: no clock, no randomness,
/// no network, and no client data. Task 8's production-path harness reuses this
/// seed so its assertions are reproducible.
final class ReferenceCommerceSeed {
  const ReferenceCommerceSeed({
    required this.products,
    required this.variants,
    required this.inventory,
    required this.customers,
    required this.accounts,
    required this.memberships,
    required this.credits,
    required this.carts,
    required this.identities,
  });

  final List<Product> products;
  final List<Variant> variants;
  final List<InventoryAvailability> inventory;
  final List<CustomerProfile> customers;
  final List<BusinessAccount> accounts;
  final List<AccountMembership> memberships;
  final List<CreditSnapshot> credits;
  final List<Cart> carts;
  final List<AppIdentity> identities;

  Map<String, AppIdentity> get identitiesByEmail => {
        for (final identity in identities) identity.email.toLowerCase(): identity,
      };
}

/// The canonical reference-commerce seed. Synthetic data only.
ReferenceCommerceSeed defaultReferenceCommerceSeed() {
  const productOne = 'product-espresso-machine';
  const productTwo = 'product-grinder';
  const variantOne = 'variant-espresso-machine-230v';
  const variantTwo = 'variant-grinder-steel';

  final consumer = AppIdentity(
    id: 'identity-consumer',
    email: 'consumer@reference-commerce.example',
    displayName: 'Reference Consumer',
    role: UserRole.consumer,
  );
  final buyer = AppIdentity(
    id: 'identity-buyer',
    email: 'buyer@reference-commerce.example',
    displayName: 'Reference Buyer',
    role: UserRole.b2bBuyer,
    memberships: [
      AccountMembership(
        accountId: 'account-trade',
        identityId: 'identity-buyer',
        role: UserRole.b2bBuyer,
      ),
    ],
  );
  final manager = AppIdentity(
    id: 'identity-manager',
    email: 'manager@reference-commerce.example',
    displayName: 'Reference Manager',
    role: UserRole.b2bManager,
    memberships: [
      AccountMembership(
        accountId: 'account-trade',
        identityId: 'identity-manager',
        role: UserRole.b2bManager,
      ),
    ],
  );

  return ReferenceCommerceSeed(
    products: [
      Product(
        id: productOne,
        name: 'Reference Espresso Machine',
        sku: 'REF-ESP-001',
        priceMinor: 129900,
        categoryId: 'category-machines',
      ),
      Product(
        id: productTwo,
        name: 'Reference Burr Grinder',
        sku: 'REF-GRD-002',
        priceMinor: 45900,
        categoryId: 'category-grinders',
      ),
    ],
    variants: [
      Variant(
        id: variantOne,
        productId: productOne,
        name: '230V',
        sku: 'REF-ESP-001-230V',
        priceMinor: 129900,
      ),
      Variant(
        id: variantTwo,
        productId: productTwo,
        name: 'Steel',
        sku: 'REF-GRD-002-STEEL',
        priceMinor: 45900,
      ),
    ],
    inventory: [
      InventoryAvailability(
        variantId: variantOne,
        available: 24,
        warehouseId: 'warehouse-reference',
      ),
      InventoryAvailability(
        variantId: variantTwo,
        available: 60,
        warehouseId: 'warehouse-reference',
      ),
    ],
    customers: [
      CustomerProfile(
        id: 'customer-consumer',
        identityId: consumer.id,
        displayName: consumer.displayName,
        email: consumer.email,
      ),
    ],
    accounts: [
      BusinessAccount(
        id: 'account-trade',
        name: 'Reference Trade Account',
        registrationNumber: 'REF-TRADE-001',
      ),
    ],
    memberships: [
      AccountMembership(
        accountId: 'account-trade',
        identityId: buyer.id,
        role: UserRole.b2bBuyer,
      ),
      AccountMembership(
        accountId: 'account-trade',
        identityId: manager.id,
        role: UserRole.b2bManager,
      ),
    ],
    credits: [
      CreditSnapshot(
        accountId: 'account-trade',
        creditLimitMinor: 1000000,
        availableCreditMinor: 750000,
      ),
    ],
    carts: [
      Cart(
        id: 'cart-consumer',
        items: [
          CartItem(
            productId: productOne,
            variantId: variantOne,
            quantity: 1,
            unitPriceMinor: 129900,
          ),
        ],
      ),
    ],
    identities: [consumer, buyer, manager],
  );
}

/// In-memory [CatalogRepository] and [InventoryRepository] over a seed.
final class InMemoryCatalogRepository
    implements CatalogRepository, InventoryRepository {
  InMemoryCatalogRepository({
    required List<Product> products,
    required List<Variant> variants,
    required List<InventoryAvailability> inventory,
  })  : _products = List.unmodifiable(products),
        _variants = List.unmodifiable(variants),
        _inventory = List.unmodifiable(inventory);

  final List<Product> _products;
  final List<Variant> _variants;
  final List<InventoryAvailability> _inventory;

  @override
  Future<List<Product>> listProducts({String? categoryId}) async => categoryId == null
      ? _products
      : _products.where((product) => product.categoryId == categoryId).toList();

  @override
  Future<Product?> getProduct(String productId) async {
    for (final product in _products) {
      if (product.id == productId) {
        return product;
      }
    }
    return null;
  }

  @override
  Future<List<Variant>> listVariants(String productId) async => _variants
      .where((variant) => variant.productId == productId)
      .toList();

  @override
  Future<InventoryAvailability?> getAvailability(String variantId) async {
    for (final level in _inventory) {
      if (level.variantId == variantId) {
        return level;
      }
    }
    return null;
  }

  @override
  Future<List<InventoryAvailability>> listAvailability(
    Iterable<String> variantIds,
  ) async {
    final wanted = variantIds.toSet();
    return _inventory
        .where((level) => wanted.contains(level.variantId))
        .toList();
  }
}

/// In-memory [CartRepository].
final class InMemoryCartRepository implements CartRepository {
  InMemoryCartRepository({Iterable<Cart> carts = const []}) {
    for (final cart in carts) {
      _carts[cart.id] = cart;
    }
  }

  final Map<String, Cart> _carts = {};

  @override
  Future<Cart?> getCart(String cartId) async => _carts[cartId];

  @override
  Future<Cart> saveCart(Cart cart, {String? accountId}) async {
    _carts[cart.id] = cart;
    return cart;
  }
}

/// In-memory [OrderRepository] with caller-keyed idempotency.
final class InMemoryOrderRepository implements OrderRepository {
  final Map<String, Order> _ordersByIdempotencyKey = {};
  int _sequence = 0;

  @override
  Future<Order> createOrder({
    required Cart cart,
    required IdempotencyKey idempotencyKey,
    int? totalMinor,
    String? accountId,
  }) async {
    final existing = _ordersByIdempotencyKey[idempotencyKey.value];
    if (existing != null) {
      return existing;
    }
    final order = Order.fromCart(
      cart,
      id: 'order-${++_sequence}',
      totalMinor: totalMinor,
    );
    _ordersByIdempotencyKey[idempotencyKey.value] = order;
    return order;
  }
}

/// In-memory [QuoteRepository] with caller-keyed idempotency.
final class InMemoryQuoteRepository implements QuoteRepository {
  final Map<String, Rfq> _rfqsById = {};
  final Map<String, Rfq> _rfqsByIdempotencyKey = {};
  final Map<String, Quotation> _quotationsById = {};
  final Map<String, Quotation> _quotationsByIdempotencyKey = {};
  int _rfqSequence = 0;

  @override
  Future<Rfq> createRfq({
    required String accountId,
    required List<CartItem> items,
    required IdempotencyKey idempotencyKey,
    String? message,
  }) async {
    final existing = _rfqsByIdempotencyKey[idempotencyKey.value];
    if (existing != null) {
      return existing;
    }
    final rfq = Rfq(
      id: 'rfq-${++_rfqSequence}',
      accountId: accountId,
      items: items,
      message: message,
    );
    _rfqsById[rfq.id] = rfq;
    _rfqsByIdempotencyKey[idempotencyKey.value] = rfq;
    return rfq;
  }

  @override
  Future<Rfq?> getRfq(String rfqId) async => _rfqsById[rfqId];

  @override
  Future<Quotation> saveQuotation({
    required Quotation quotation,
    required IdempotencyKey idempotencyKey,
  }) async {
    final existing = _quotationsByIdempotencyKey[idempotencyKey.value];
    if (existing != null) {
      return existing;
    }
    _quotationsById[quotation.id] = quotation;
    _quotationsByIdempotencyKey[idempotencyKey.value] = quotation;
    return quotation;
  }

  @override
  Future<Quotation?> getQuotation(String quotationId) async =>
      _quotationsById[quotationId];
}

/// In-memory [AccountRepository] and [CustomerRepository] over a seed.
final class InMemoryAccountRepository
    implements AccountRepository, CustomerRepository {
  InMemoryAccountRepository({
    required List<CustomerProfile> customers,
    required List<BusinessAccount> accounts,
    required List<AccountMembership> memberships,
    required List<CreditSnapshot> credits,
  })  : _customers = List.unmodifiable(customers),
        _accounts = List.unmodifiable(accounts),
        _memberships = List.unmodifiable(memberships),
        _credits = List.unmodifiable(credits);

  final List<CustomerProfile> _customers;
  final List<BusinessAccount> _accounts;
  final List<AccountMembership> _memberships;
  final List<CreditSnapshot> _credits;
  final Map<String, CustomerProfile> _savedProfiles = {};

  @override
  Future<List<BusinessAccount>> listAccountsForIdentity(
    String identityId,
  ) async {
    final accountIds = _memberships
        .where((membership) => membership.identityId == identityId)
        .map((membership) => membership.accountId)
        .toSet();
    return _accounts
        .where((account) => accountIds.contains(account.id))
        .toList();
  }

  @override
  Future<AccountMembership?> getMembership({
    required String accountId,
    required String identityId,
  }) async {
    for (final membership in _memberships) {
      if (membership.accountId == accountId &&
          membership.identityId == identityId) {
        return membership;
      }
    }
    return null;
  }

  @override
  Future<CreditSnapshot?> getCreditSnapshot(String accountId) async {
    for (final credit in _credits) {
      if (credit.accountId == accountId) {
        return credit;
      }
    }
    return null;
  }

  @override
  Future<CustomerProfile?> getProfile(String identityId) async {
    for (final profile in _savedProfiles.values) {
      if (profile.identityId == identityId) {
        return profile;
      }
    }
    for (final profile in _customers) {
      if (profile.identityId == identityId) {
        return profile;
      }
    }
    return null;
  }

  @override
  Future<CustomerProfile> saveProfile(CustomerProfile profile) async {
    _savedProfiles[profile.identityId] = profile;
    return profile;
  }
}

/// Deterministic [AuthService] over a fixed identity set.
///
/// Sign-in resolves an identity by email (case-insensitive); unknown emails and
/// blank passwords raise a provider-neutral [DomainFailure] so failure states
/// stay deterministic and testable.
final class DeterministicAuthService implements AuthService {
  DeterministicAuthService({required Map<String, AppIdentity> identitiesByEmail})
      : _identitiesByEmail = {
          for (final entry in identitiesByEmail.entries)
            entry.key.toLowerCase(): entry.value,
        };

  final Map<String, AppIdentity> _identitiesByEmail;
  AppIdentity? _current;

  @override
  Stream<AppIdentity?> authStateChanges() => Stream<AppIdentity?>.value(_current);

  @override
  Future<AppIdentity> signIn({
    required String email,
    required String password,
  }) async {
    if (password.trim().isEmpty) {
      throw const DomainFailure(
        code: DomainFailureCode.validation,
        operation: 'signIn',
        retryable: false,
        message: 'Password must not be empty',
      );
    }
    final identity = _identitiesByEmail[email.trim().toLowerCase()];
    if (identity == null) {
      throw DomainFailure(
        code: DomainFailureCode.unauthorized,
        operation: 'signIn',
        retryable: false,
        message: 'Unknown identity for $email',
      );
    }
    _current = identity;
    return identity;
  }

  @override
  Future<void> signOut() async {
    _current = null;
  }

  @override
  Future<AppIdentity?> currentIdentity() async => _current;

  @override
  Future<AppIdentity> refreshSession() async {
    final identity = _current;
    if (identity == null) {
      throw const DomainFailure(
        code: DomainFailureCode.unauthorized,
        operation: 'refreshSession',
        retryable: false,
        message: 'No active session to refresh',
      );
    }
    return identity;
  }
}

/// The deterministic, in-memory boundaries used by dev/test composition.
final class DeterministicCommerceBoundaries {
  DeterministicCommerceBoundaries({ReferenceCommerceSeed? seed})
      : seed = seed ?? defaultReferenceCommerceSeed() {
    catalog = InMemoryCatalogRepository(
      products: this.seed.products,
      variants: this.seed.variants,
      inventory: this.seed.inventory,
    );
    carts = InMemoryCartRepository(carts: this.seed.carts);
    orders = InMemoryOrderRepository();
    quotes = InMemoryQuoteRepository();
    accounts = InMemoryAccountRepository(
      customers: this.seed.customers,
      accounts: this.seed.accounts,
      memberships: this.seed.memberships,
      credits: this.seed.credits,
    );
    auth = DeterministicAuthService(
      identitiesByEmail: this.seed.identitiesByEmail,
    );
  }

  final ReferenceCommerceSeed seed;
  late final InMemoryCatalogRepository catalog;
  late final InMemoryCartRepository carts;
  late final InMemoryOrderRepository orders;
  late final InMemoryQuoteRepository quotes;
  late final InMemoryAccountRepository accounts;
  late final DeterministicAuthService auth;
}
