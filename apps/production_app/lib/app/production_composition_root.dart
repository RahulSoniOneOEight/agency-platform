import 'package:agency_integration_adapters/agency_integration_adapters.dart';
import 'package:agency_production_core/agency_production_core.dart';
import 'package:agency_supabase_adapter/agency_supabase_adapter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../runtime/deterministic_boundaries.dart';
import '../runtime/reference_commerce_runtime.dart';

/// Builds the reference-commerce production runtime from client-safe config.
///
/// Composition rules (Milestone H.1):
/// - `dev` always uses the deterministic in-memory boundaries.
/// - `staging`/`production` use the Supabase adapters **only** when client-safe
///   `supabase_url` + `supabase_anon_key` are present; otherwise they fall back
///   to the deterministic boundaries so the app still boots in CI without a
///   live Supabase project.
/// - Missing privileged server credentials (service role, payment/ERP/WhatsApp
///   secrets) are a server concern and are never read or required here.
/// - Integration ports are the deterministic fake adapters: H.1 ships
///   production-shaped interfaces, not live vendor clients.
abstract final class ProductionCompositionRoot {
  static ReferenceCommerceRuntime referenceCommerce(EnvironmentConfig config) {
    final boundaries = _resolveBoundaries(config);
    return ReferenceCommerceRuntime(
      config: config,
      auth: boundaries.auth,
      commerce: CommerceService(
        catalog: boundaries.catalog,
        inventory: boundaries.inventory,
      ),
      orders: OrderService(
        carts: boundaries.carts,
        orders: boundaries.orders,
      ),
      quotes: QuoteService(
        quotes: boundaries.quotes,
        accounts: boundaries.accounts,
        orders: boundaries.orders,
      ),
      payment: FakePaymentAdapter(),
      shipping: FakeShippingAdapter(),
      erp: FakeErpAdapter(),
      crm: FakeCrmAdapter(),
      whatsapp: FakeWhatsAppAdapter(),
      isSupabaseBacked: boundaries.isSupabaseBacked,
    );
  }

  /// Whether [config] carries the client-safe Supabase pair the app can use.
  static bool hasClientSafeSupabaseConfig(EnvironmentConfig config) =>
      config.supabaseUrl.trim().isNotEmpty &&
      config.supabaseAnonKey.trim().isNotEmpty;

  static _Boundaries _resolveBoundaries(EnvironmentConfig config) {
    if (config.environment != ProductionEnvironment.dev &&
        hasClientSafeSupabaseConfig(config)) {
      return _supabaseBoundaries(config);
    }
    return _deterministicBoundaries();
  }

  static _Boundaries _deterministicBoundaries() {
    final boundaries = DeterministicCommerceBoundaries();
    return _Boundaries(
      catalog: boundaries.catalog,
      inventory: boundaries.catalog,
      carts: boundaries.carts,
      orders: boundaries.orders,
      quotes: boundaries.quotes,
      accounts: boundaries.accounts,
      auth: boundaries.auth,
      isSupabaseBacked: false,
    );
  }

  static _Boundaries _supabaseBoundaries(EnvironmentConfig config) {
    // Lazy construction only: no request is issued by these constructors.
    final client = SupabaseClient(config.supabaseUrl, config.supabaseAnonKey);
    final query = createSupabaseQueryClient(client);
    final catalog = SupabaseCatalogRepository(query: query);
    return _Boundaries(
      catalog: catalog,
      inventory: catalog,
      carts: SupabaseCartRepository(query: query),
      orders: SupabaseOrderRepository(query: query),
      quotes: SupabaseQuoteRepository(query: query),
      accounts: SupabaseAccountRepository(query: query),
      auth: SupabaseAuthAdapter(
        auth: createSupabaseAuthClient(client.auth),
        query: query,
      ),
      isSupabaseBacked: true,
    );
  }
}

/// Internal bundle of the persistence/auth boundaries the services depend on.
final class _Boundaries {
  const _Boundaries({
    required this.catalog,
    required this.inventory,
    required this.carts,
    required this.orders,
    required this.quotes,
    required this.accounts,
    required this.auth,
    required this.isSupabaseBacked,
  });

  final CatalogRepository catalog;
  final InventoryRepository inventory;
  final CartRepository carts;
  final OrderRepository orders;
  final QuoteRepository quotes;
  final AccountRepository accounts;
  final AuthService auth;
  final bool isSupabaseBacked;
}
