import 'package:agency_flutter_ui/agency_flutter_ui.dart';

import '../runtime/prototype_runtime.dart';

/// Runtime-backed prototype fixtures.
///
/// Product and service content originates from the generated client bundle.
/// The repository converts the generic JSON payload into the shared
/// `agency_flutter_ui` models so screens never read raw fixture shapes.
class FixtureRepository {
  const FixtureRepository({required this.products, required this.services});

  final List<AgencyProduct> products;
  final List<String> services;

  factory FixtureRepository.fromRuntime(PrototypeRuntime runtime) =>
      FixtureRepository.fromMap(runtime.fixtures);

  factory FixtureRepository.fromMap(Map<String, dynamic> fixtures) {
    final rawProducts = fixtures['products'];
    final rawServices = fixtures['services'];
    if (rawProducts is! List || rawServices is! List) {
      throw const FormatException('Runtime fixtures must declare products and services lists');
    }
    return FixtureRepository(
      products: rawProducts.map(_productFromFixture).toList(growable: false),
      services: rawServices.map(_serviceFromFixture).toList(growable: false),
    );
  }
}

AgencyProduct _productFromFixture(dynamic value) {
  if (value is! Map) {
    throw const FormatException('Fixture product must be an object');
  }
  final id = value['id'];
  final name = value['name'];
  final price = value['price'];
  if (id is! String || id.isEmpty) {
    throw const FormatException('Fixture product id must be a non-empty string');
  }
  if (name is! String || name.isEmpty) {
    throw const FormatException('Fixture product name must be a non-empty string');
  }
  if (price is! num) {
    throw const FormatException('Fixture product price must be a number');
  }
  final compareAt = value['compare_at'];
  final rating = value['rating'];
  final stock = value['stock'];
  final sku = value['sku'];
  return AgencyProduct(
    id: id,
    name: name,
    price: AgencyPrice(
      current: price.round(),
      compareAt: compareAt is num ? compareAt.round() : null,
    ),
    sku: sku is String ? sku : null,
    rating: rating is num ? rating.toDouble() : null,
    stock: stock is num ? stock.round() : null,
  );
}

String _serviceFromFixture(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  if (value is Map && value['name'] is String && (value['name'] as String).isNotEmpty) {
    return value['name'] as String;
  }
  throw const FormatException('Fixture service must be a name or object with a name');
}
