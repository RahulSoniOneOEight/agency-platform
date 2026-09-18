import 'dart:convert';
import 'dart:io';

import 'package:agency_integration_adapters/agency_integration_adapters.dart';
import 'package:agency_production_core/agency_production_core.dart';
import 'package:production_app/runtime/deterministic_boundaries.dart';
import 'package:production_app/runtime/reference_commerce_runtime.dart';

/// Deterministic, client-safe `dev` configuration mirroring the canonical
/// `client-projects/reference-commerce/production/config/dev.json`.
///
/// It is built in-process (no asset load) so the harness can be constructed
/// synchronously inside failure-state tests.
EnvironmentConfig devEnvironmentConfig() => EnvironmentConfig(
      environment: ProductionEnvironment.dev,
      apiBaseUrl: 'https://api.dev.agency-platform.example',
      featureFlags: const {
        'b2b_rfq': true,
        'whatsapp_notifications': false,
      },
      integrationModes: const {
        'payment': 'fake',
        'shipping': 'fake',
        'erp': 'fake',
        'crm': 'fake',
        'whatsapp': 'fake',
      },
      appVersion: '0.1.0',
    );

/// Test harness that composes the reference-commerce runtime exactly like
/// `ProductionCompositionRoot`, but with deterministic boundaries that can be
/// substituted.
///
/// It wires the *same* application services (`CommerceService`, `OrderService`,
/// `QuoteService`) and the same provider-neutral ports as production
/// composition. Substitution only replaces persistence boundaries; a test can
/// never bypass an application service for a journey mutation.
final class ReferenceCommerceHarness {
  ReferenceCommerceHarness({
    ReferenceCommerceSeed? seed,
    EnvironmentConfig? config,
    AuthService? auth,
    CatalogRepository? catalog,
    InventoryRepository? inventory,
    CartRepository? carts,
    OrderRepository? orders,
    QuoteRepository? quotes,
    AccountRepository? accounts,
    FakeErpAdapter? erp,
  }) {
    final resolvedSeed = seed ?? defaultReferenceCommerceSeed();
    final base = DeterministicCommerceBoundaries(seed: resolvedSeed);

    this.seed = resolvedSeed;
    this.config = config ?? devEnvironmentConfig();
    catalogRepository = catalog ?? base.catalog;
    inventoryRepository = inventory ?? base.catalog;
    cartRepository = carts ?? base.carts;
    orderRepository = RecordingOrderRepository(orders ?? base.orders);
    quoteRepository = quotes ?? base.quotes;
    accountRepository = accounts ?? base.accounts;
    this.auth = auth ?? base.auth;
    this.erp = erp ?? FakeErpAdapter();

    commerce = CommerceService(
      catalog: catalogRepository,
      inventory: inventoryRepository,
    );
    orderService = OrderService(
      carts: cartRepository,
      orders: orderRepository,
    );
    quoteService = QuoteService(
      quotes: quoteRepository,
      accounts: accountRepository,
      orders: orderRepository,
    );
    runtime = ReferenceCommerceRuntime(
      config: this.config,
      auth: this.auth,
      commerce: commerce,
      orders: orderService,
      quotes: quoteService,
      payment: FakePaymentAdapter(),
      shipping: FakeShippingAdapter(),
      erp: this.erp,
      crm: FakeCrmAdapter(),
      whatsapp: FakeWhatsAppAdapter(),
      isSupabaseBacked: false,
    );
  }

  late final ReferenceCommerceSeed seed;
  late final EnvironmentConfig config;
  late final AuthService auth;
  late final CatalogRepository catalogRepository;
  late final InventoryRepository inventoryRepository;
  late final CartRepository cartRepository;
  late final RecordingOrderRepository orderRepository;
  late final QuoteRepository quoteRepository;
  late final AccountRepository accountRepository;
  late final FakeErpAdapter erp;

  late final CommerceService commerce;
  late final OrderService orderService;
  late final QuoteService quoteService;
  late final ReferenceCommerceRuntime runtime;
}

/// Wraps an [OrderRepository] and records the distinct orders it persisted.
///
/// A duplicate idempotent submission must not grow [distinctOrderCount], which
/// is exactly the B2C duplicate-protection assertion.
final class RecordingOrderRepository implements OrderRepository {
  RecordingOrderRepository(this._inner);

  final OrderRepository _inner;
  final List<Order> _orders = [];

  List<Order> get orders => List.unmodifiable(_orders);

  int get distinctOrderCount => _orders.length;

  @override
  Future<Order> createOrder({
    required Cart cart,
    required IdempotencyKey idempotencyKey,
    int? totalMinor,
    String? accountId,
  }) async {
    final order = await _inner.createOrder(
      cart: cart,
      idempotencyKey: idempotencyKey,
      totalMinor: totalMinor,
      accountId: accountId,
    );
    if (!_orders.any((existing) => existing.id == order.id)) {
      _orders.add(order);
    }
    return order;
  }
}

/// A [CatalogRepository] whose reads always fail with a normalized failure.
final class FailingCatalogRepository implements CatalogRepository {
  FailingCatalogRepository({required this.failure});

  final DomainFailure failure;

  @override
  Future<List<Product>> listProducts({String? categoryId}) async =>
      throw failure;

  @override
  Future<Product?> getProduct(String productId) async => throw failure;

  @override
  Future<List<Variant>> listVariants(String productId) async => throw failure;
}

/// An [InventoryRepository] whose reads always fail with a normalized failure.
final class FailingInventoryRepository implements InventoryRepository {
  FailingInventoryRepository({required this.failure});

  final DomainFailure failure;

  @override
  Future<InventoryAvailability?> getAvailability(String variantId) async =>
      throw failure;

  @override
  Future<List<InventoryAvailability>> listAvailability(
    Iterable<String> variantIds,
  ) async =>
      throw failure;
}

/// A [CartRepository] whose reads always fail with a normalized failure.
final class FailingCartRepository implements CartRepository {
  FailingCartRepository({required this.failure});

  final DomainFailure failure;

  @override
  Future<Cart?> getCart(String cartId) async => throw failure;

  @override
  Future<Cart> saveCart(Cart cart, {String? accountId}) async => throw failure;
}

/// An [OrderRepository] whose writes always fail with a normalized failure.
final class FailingOrderRepository implements OrderRepository {
  FailingOrderRepository({required this.failure});

  final DomainFailure failure;

  @override
  Future<Order> createOrder({
    required Cart cart,
    required IdempotencyKey idempotencyKey,
    int? totalMinor,
    String? accountId,
  }) async =>
      throw failure;
}

/// A deterministic [AuthService] whose session can be expired or revoked.
///
/// [expireSession] models an expired access token with a still-valid refresh
/// token: [refreshSession] succeeds and restores the identity. [signOut]
/// revokes the refresh token too, so a subsequent [refreshSession] fails with a
/// non-retryable `unauthorized` [DomainFailure].
final class ExpirableAuthService implements AuthService {
  ExpirableAuthService({required Map<String, AppIdentity> identitiesByEmail})
      : _identitiesByEmail = {
          for (final entry in identitiesByEmail.entries)
            entry.key.toLowerCase(): entry.value,
        };

  final Map<String, AppIdentity> _identitiesByEmail;
  AppIdentity? _current;
  AppIdentity? _refreshable;

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
    _refreshable = identity;
    return identity;
  }

  /// Expires the access token while keeping the refresh token valid.
  void expireSession() {
    _current = null;
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _refreshable = null;
  }

  @override
  Future<AppIdentity?> currentIdentity() async => _current;

  @override
  Future<AppIdentity> refreshSession() async {
    final identity = _current ?? _refreshable;
    if (identity == null) {
      throw const DomainFailure(
        code: DomainFailureCode.unauthorized,
        operation: 'refreshSession',
        retryable: false,
        message: 'No active session to refresh',
      );
    }
    _current = identity;
    return identity;
  }
}

/// One deterministic scenario declared in
/// `client-projects/reference-commerce/production/fixtures/integration-scenarios.json`.
final class IntegrationScenario {
  const IntegrationScenario({
    required this.id,
    required this.kind,
    this.expectedCode,
    this.expectedRetryable,
    this.expectedOperation,
    this.expectedError,
    this.contrastCode,
    this.contrastRetryable,
  });

  final String id;
  final String kind;
  final DomainFailureCode? expectedCode;
  final bool? expectedRetryable;
  final String? expectedOperation;
  final String? expectedError;
  final DomainFailureCode? contrastCode;
  final bool? contrastRetryable;
}

/// A named journey and its ordered, fixture-defined step ids.
final class IntegrationJourney {
  const IntegrationJourney({required this.id, required this.steps});

  final String id;
  final List<String> steps;
}

/// One expected failure case declared under `b2b_path.cases`.
final class IntegrationCase {
  const IntegrationCase({
    required this.id,
    this.expectedCode,
    this.expectedRetryable,
    this.expectedOperation,
  });

  final String id;
  final DomainFailureCode? expectedCode;
  final bool? expectedRetryable;
  final String? expectedOperation;
}

/// Typed view over the committed integration-scenarios fixture.
final class IntegrationScenarios {
  const IntegrationScenarios({
    required this.version,
    required this.clientId,
    required this.b2cPath,
    required this.b2bPath,
    required this.b2bCases,
    required this.failureScenarios,
  });

  final int version;
  final String clientId;
  final IntegrationJourney b2cPath;
  final IntegrationJourney b2bPath;
  final List<IntegrationCase> b2bCases;
  final List<IntegrationScenario> failureScenarios;

  Set<String> get failureScenarioIds =>
      {for (final scenario in failureScenarios) scenario.id};

  Set<String> get b2bCaseIds => {for (final entry in b2bCases) entry.id};

  IntegrationScenario failureById(String id) =>
      failureScenarios.firstWhere((scenario) => scenario.id == id);

  IntegrationCase b2bCaseById(String id) =>
      b2bCases.firstWhere((scenarioCase) => scenarioCase.id == id);
}

const String _scenarioRelativePath =
    'client-projects/reference-commerce/production/fixtures/'
    'integration-scenarios.json';

/// Loads and parses the committed integration-scenarios fixture.
///
/// The fixture lives outside the app package, so the repository root is located
/// by walking up from the current directory; tests run from the app directory.
IntegrationScenarios loadIntegrationScenarios() {
  final file = _locateScenarioFile();
  final decoded = json.decode(file.readAsStringSync());
  if (decoded is! Map) {
    throw StateError('integration-scenarios.json must be a JSON object');
  }
  final root = Map<String, Object?>.from(decoded);

  final b2c = Map<String, Object?>.from(root['b2c_path']! as Map);
  final b2b = Map<String, Object?>.from(root['b2b_path']! as Map);
  final cases = b2b['cases'] as List? ?? const [];

  return IntegrationScenarios(
    version: root['version']! as int,
    clientId: root['client_id']! as String,
    b2cPath: _parseJourney(b2c),
    b2bPath: _parseJourney(b2b),
    b2bCases: [
      for (final entry in cases)
        _parseCase(Map<String, Object?>.from(entry as Map)),
    ],
    failureScenarios: [
      for (final entry in root['failure_scenarios']! as List)
        _parseScenario(Map<String, Object?>.from(entry as Map)),
    ],
  );
}

IntegrationJourney _parseJourney(Map<String, Object?> json) =>
    IntegrationJourney(
      id: json['id']! as String,
      steps: _stringList(json['steps']),
    );

IntegrationCase _parseCase(Map<String, Object?> json) => IntegrationCase(
      id: json['id']! as String,
      expectedCode: _code(json['expected_code']),
      expectedRetryable: json['retryable'] as bool?,
      expectedOperation: json['operation'] as String?,
    );

IntegrationScenario _parseScenario(Map<String, Object?> json) =>
    IntegrationScenario(
      id: json['id']! as String,
      kind: json['kind']! as String,
      expectedCode: _code(json['expected_code']),
      expectedRetryable: json['retryable'] as bool?,
      expectedOperation: json['operation'] as String?,
      expectedError: json['expected_error'] as String?,
      contrastCode: _code(json['contrast_code']),
      contrastRetryable: json['contrast_retryable'] as bool?,
    );

DomainFailureCode? _code(Object? value) => value == null
    ? null
    : DomainFailureCode.values.byName(value as String);

List<String> _stringList(Object? value) =>
    [for (final entry in value! as List) entry as String];

File _locateScenarioFile() {
  var directory = Directory.current;
  for (var depth = 0; depth < 8; depth++) {
    final candidate = File('${directory.path}/$_scenarioRelativePath');
    if (candidate.existsSync()) {
      return candidate;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      break;
    }
    directory = parent;
  }
  throw StateError(
    'Unable to locate $_scenarioRelativePath from ${Directory.current.path}',
  );
}
