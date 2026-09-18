import 'package:agency_production_core/agency_production_core.dart';

/// The provider-neutral aggregate the production app boots from.
///
/// It holds the client-safe [config] plus the fully wired application services
/// and integration ports. No provider type appears here: adapters are selected
/// by [ProductionCompositionRoot] and cross this boundary only as ports.
final class ReferenceCommerceRuntime {
  ReferenceCommerceRuntime({
    required this.config,
    required this.auth,
    required this.commerce,
    required this.orders,
    required this.quotes,
    required this.payment,
    required this.shipping,
    required this.erp,
    required this.crm,
    required this.whatsapp,
    required this.isSupabaseBacked,
  });

  final EnvironmentConfig config;
  final AuthService auth;
  final CommerceService commerce;
  final OrderService orders;
  final QuoteService quotes;
  final PaymentPort payment;
  final ShippingPort shipping;
  final ErpPort erp;
  final CrmPort crm;
  final WhatsAppPort whatsapp;

  /// Whether the persistence boundary is backed by Supabase (staging/production
  /// with client-safe config) rather than the deterministic in-memory boundary.
  final bool isSupabaseBacked;

  ProductionEnvironment get environment => config.environment;
}
