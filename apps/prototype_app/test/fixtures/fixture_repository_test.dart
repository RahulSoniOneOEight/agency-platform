import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/fixtures/fixture_repository.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

void main() {
  test('product content comes from the runtime fixture payload', () {
    final fixtures = defaultFixtures();
    (fixtures['products'] as List)[0]['name'] = 'Runtime Widget';
    (fixtures['products'] as List)[0]['price'] = 4321;
    final runtime = PrototypeRuntime.fromMap(canonicalBundle(fixtures: fixtures));

    final repository = FixtureRepository.fromRuntime(runtime);

    expect(repository.products, hasLength(1));
    expect(repository.products.single.name, 'Runtime Widget');
    expect(repository.products.single.price.current, 4321);
    expect(repository.products.single.sku, 'SKU-ELE-1000');
    expect(repository.products.single.rating, 4.1);
    expect(repository.products.single.stock, 18);
  });

  test('services are converted from fixture objects to names', () {
    final fixtures = defaultFixtures();
    fixtures['services'] = [
      {
        'id': 'svc-01',
        'name': 'Initial Consultation',
        'price': 499,
        'duration_minutes': 30,
        'rating': 4.5,
      },
    ];
    final runtime = PrototypeRuntime.fromMap(canonicalBundle(fixtures: fixtures));

    expect(FixtureRepository.fromRuntime(runtime).services, ['Initial Consultation']);
  });

  test('malformed fixture products fail visibly', () {
    final fixtures = defaultFixtures();
    (fixtures['products'] as List)[0].remove('name');
    final runtime = PrototypeRuntime.fromMap(canonicalBundle(fixtures: fixtures));

    expect(() => FixtureRepository.fromRuntime(runtime), throwsFormatException);
  });
}
