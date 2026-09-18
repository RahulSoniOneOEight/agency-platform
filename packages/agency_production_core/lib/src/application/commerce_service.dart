import '../domain/domain_failure.dart';
import '../domain/models.dart';
import '../ports/repositories.dart';

/// A variant together with its resolved inventory availability.
final class CatalogVariant {
  const CatalogVariant({required this.variant, this.available});

  final Variant variant;

  /// Available units, or `null` when no availability record exists.
  final int? available;
}

/// A product together with its variants and their availability.
final class CatalogProduct {
  CatalogProduct({
    required this.product,
    List<CatalogVariant> variants = const [],
  }) : variants = List.unmodifiable(variants);

  final Product product;
  final List<CatalogVariant> variants;
}

/// Read-only commerce use cases.
///
/// Composes provider-neutral repository reads; it never touches a provider
/// directly. Failures from repositories are already normalized to
/// [DomainFailure] by the adapter boundary, so this service only ever catches
/// [DomainFailure] (to attach the use-case operation) and never swallows
/// provider exceptions.
final class CommerceService {
  CommerceService({
    required CatalogRepository catalog,
    required InventoryRepository inventory,
  })  : _catalog = catalog,
        _inventory = inventory;

  final CatalogRepository _catalog;
  final InventoryRepository _inventory;

  /// Loads products (optionally filtered by [categoryId]) and composes each
  /// product's variants with their inventory availability.
  Future<List<CatalogProduct>> loadCatalog({String? categoryId}) async {
    try {
      final products = await _catalog.listProducts(categoryId: categoryId);

      final variantLists = <List<Variant>>[];
      for (final product in products) {
        variantLists.add(await _catalog.listVariants(product.id));
      }

      final variantIds = [
        for (final variants in variantLists) ...variants.map((v) => v.id),
      ];
      final availability = await _inventory.listAvailability(variantIds);
      final availableByVariant = {
        for (final level in availability) level.variantId: level.available,
      };

      return [
        for (var index = 0; index < products.length; index++)
          CatalogProduct(
            product: products[index],
            variants: [
              for (final variant in variantLists[index])
                CatalogVariant(
                  variant: variant,
                  available: availableByVariant[variant.id],
                ),
            ],
          ),
      ];
    } on DomainFailure catch (failure) {
      throw _scope(failure);
    }
  }

  DomainFailure _scope(DomainFailure failure) => DomainFailure(
        code: failure.code,
        operation: 'load_catalog',
        retryable: failure.retryable,
        message: failure.message,
        correlationId: failure.correlationId,
      );
}
