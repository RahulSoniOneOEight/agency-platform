import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/fixtures/fixture_repository.dart';
import 'package:prototype_app/registry/design_contract_resolver.dart';
import 'package:prototype_app/registry/prototype_registry.dart';
import 'package:prototype_app/review/review_section_registry.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

void main() {
  group('ReviewSectionRegistry', () {
    test('section ids are unique and stable', () {
      final ids = ReviewSectionRegistry.all.map((d) => d.id).toList();

      expect(ids.toSet().length, ids.length, reason: 'duplicate section id');
      expect(
        ids,
        containsAll(<String>[
          'home.product-grid',
          'plp.product-grid',
          'search.search-field',
          'search.results-grid',
          'pdp.price',
        ]),
      );
    });

    test('every definition belongs to exactly one governed screen', () {
      for (final definition in ReviewSectionRegistry.all) {
        expect(definition.screenId, startsWith('commerce.'));
        final siblings = ReviewSectionRegistry.sectionsForScreen(definition.screenId);
        expect(
          siblings.where((section) => section.id == definition.id).length,
          1,
          reason: '${definition.id} is not unique within ${definition.screenId}',
        );
      }
    });

    test('every backing component id resolves through B.1D bindings', () {
      for (final definition in ReviewSectionRegistry.all) {
        expect(
          () => DesignContractResolver.component(definition.componentId),
          returnsNormally,
          reason: '${definition.id} references unknown component ${definition.componentId}',
        );
      }
    });

    test('definition() finds known ids and returns null for unknown ids', () {
      expect(ReviewSectionRegistry.definition('plp.product-grid')!.screenId, 'commerce.plp');
      expect(ReviewSectionRegistry.definition('commerce.nope'), isNull);
    });

    test('sectionsForScreen is deterministic and empty for unknown screens', () {
      expect(
        ReviewSectionRegistry.sectionsForScreen('commerce.plp').map((d) => d.id).toList(),
        equals(<String>['plp.product-grid']),
      );
      expect(
        ReviewSectionRegistry.sectionsForScreen('commerce.search').map((d) => d.id).toList(),
        equals(<String>['search.search-field', 'search.results-grid']),
      );
      expect(ReviewSectionRegistry.sectionsForScreen('commerce.unknown'), isEmpty);
    });

    test('every registered section is exposed by the shared pattern composition', () {
      final runtime = PrototypeRuntime.fromMap(
        canonicalBundle(directionIds: const ['a', 'c'], resources: const {}),
      );
      final direction = runtime.directions['a']!;
      final fixtures = FixtureRepository.fromRuntime(runtime);

      for (final definition in ReviewSectionRegistry.all) {
        final composition =
            PrototypeRegistry.compositionFor(definition.screenId, direction, fixtures);
        expect(composition, isNotNull,
            reason: '${definition.screenId} is not composed from sections');
        expect(
          composition!.sections.map((section) => section.id),
          contains(definition.id),
          reason: '${definition.id} is not exposed by the ${definition.screenId} composition',
        );
      }
    });

    test('each registered section maps to its expected shared section widget', () {
      final runtime = PrototypeRuntime.fromMap(
        canonicalBundle(directionIds: const ['a', 'c'], resources: const {}),
      );
      final direction = runtime.directions['a']!;
      final fixtures = FixtureRepository.fromRuntime(runtime);

      const expected = <String, Type>{
        'home.product-grid': ProductGridSection,
        'plp.product-grid': ProductGridSection,
        'search.search-field': SearchFieldSection,
        'search.results-grid': CompactProductRowSection,
        'pdp.price': PriceSection,
      };

      for (final definition in ReviewSectionRegistry.all) {
        final composition =
            PrototypeRegistry.compositionFor(definition.screenId, direction, fixtures)!;
        final section = composition.sections
            .firstWhere((candidate) => candidate.id == definition.id);
        expect(
          section.child.runtimeType,
          expected[definition.id],
          reason: '${definition.id} composes the wrong section widget for '
              'component ${definition.componentId}',
        );
      }
    });
  });
}
