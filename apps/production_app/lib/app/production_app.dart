import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:agency_production_core/agency_production_core.dart';
import 'package:flutter/material.dart';

import '../runtime/reference_commerce_runtime.dart';

/// The reference-commerce production shell.
///
/// It reuses the approved shared UI system (`agency_flutter_ui` theme,
/// primitives, and the `commerce.product-card` component) and renders real data
/// from the provider-neutral application services. No new UX pattern is
/// introduced and no widget is copied from `apps/prototype_app`.
class ProductionApp extends StatelessWidget {
  const ProductionApp({super.key, required this.runtime});

  final ReferenceCommerceRuntime runtime;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Reference Commerce',
      theme: AgencyTheme.lightDefault(),
      home: ProductionHomeScreen(runtime: runtime),
    );
  }
}

class ProductionHomeScreen extends StatefulWidget {
  const ProductionHomeScreen({super.key, required this.runtime});

  final ReferenceCommerceRuntime runtime;

  @override
  State<ProductionHomeScreen> createState() => _ProductionHomeScreenState();
}

class _ProductionHomeScreenState extends State<ProductionHomeScreen> {
  late final Future<List<CatalogProduct>> _catalog;

  @override
  void initState() {
    super.initState();
    _catalog = widget.runtime.commerce.loadCatalog();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = widget.runtime;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reference Commerce'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: AgencyChip(
                label: runtime.environment.name,
                selected: true,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _EnvironmentPanel(runtime: runtime),
          const SizedBox(height: 16),
          Text('Catalog', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          FutureBuilder<List<CatalogProduct>>(
            future: _catalog,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final error = snapshot.error;
              if (error != null) {
                return _CatalogError(error: error);
              }
              final products = snapshot.requireData;
              if (products.isEmpty) {
                return const Text('No products available.');
              }
              return Column(
                children: [
                  for (final product in products)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ProductCard(product: _toAgencyProduct(product)),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EnvironmentPanel extends StatelessWidget {
  const _EnvironmentPanel({required this.runtime});

  final ReferenceCommerceRuntime runtime;

  @override
  Widget build(BuildContext context) {
    final config = runtime.config;
    final theme = Theme.of(context);
    return AgencySurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Runtime', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Environment: ${config.environment.name}'),
          Text('API base URL: ${config.apiBaseUrl}'),
          Text('App version: ${config.appVersion ?? 'unversioned'}'),
          Text('Analytics: ${config.analyticsEnabled ? 'enabled' : 'disabled'}'),
          Text(
            'Persistence: ${runtime.isSupabaseBacked ? 'Supabase' : 'deterministic in-memory'}',
          ),
          const SizedBox(height: 12),
          Text('Integration modes', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in config.integrationModes.entries)
                AgencyChip(label: '${entry.key}: ${entry.value}'),
            ],
          ),
          if (config.featureFlags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Feature flags', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in config.featureFlags.entries)
                  AgencyChip(
                    label: entry.key,
                    selected: entry.value,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CatalogError extends StatelessWidget {
  const _CatalogError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final message = error is DomainFailure
        ? (error as DomainFailure).message
        : 'Unable to load the catalog.';
    return AgencySurface(
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

AgencyProduct _toAgencyProduct(CatalogProduct entry) {
  int? stock;
  for (final variant in entry.variants) {
    final available = variant.available;
    if (available != null) {
      stock = (stock ?? 0) + available;
    }
  }
  return AgencyProduct(
    id: entry.product.id,
    name: entry.product.name,
    sku: entry.product.sku,
    price: AgencyPrice(current: entry.product.priceMinor),
    stock: stock,
    subtitle: entry.product.description,
  );
}
