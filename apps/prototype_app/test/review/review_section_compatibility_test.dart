import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/review_section_compatibility.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';

import '../support/runtime_fixtures.dart';

/// Three directions with asymmetric pattern/component exposure so availability
/// and compatibility are exercised deterministically.
PrototypeRuntime buildRuntime() {
  return PrototypeRuntime.fromMap(
    canonicalBundle(
      directionIds: const ['a', 'b', 'c'],
      patterns: const {
        'a': ['commerce.plp', 'commerce.pdp', 'commerce.search'],
        'b': ['commerce.trade-dashboard'],
        'c': ['commerce.plp', 'commerce.pdp', 'commerce.search'],
      },
      components: const {
        'a': ['commerce.product-card', 'commerce.price-display', 'commerce.search-field'],
        'b': ['commerce.credit-summary'],
        'c': ['commerce.product-card', 'commerce.price-display'],
      },
    ),
  );
}

ReviewSectionCompatibilityResult evaluate(
  PrototypeRuntime runtime, {
  required String screenId,
  required String sectionId,
  required String source,
  String base = 'a',
}) {
  return ReviewSectionCompatibility.evaluate(
    runtime: runtime,
    screenId: screenId,
    sectionId: sectionId,
    sourceDirectionId: source,
    baseDirectionId: base,
  );
}

void main() {
  late PrototypeRuntime runtime;

  setUp(() {
    runtime = buildRuntime();
  });

  test('allows a section the source direction exposes and supports', () {
    final plp = evaluate(
      runtime,
      screenId: 'commerce.plp',
      sectionId: 'plp.product-grid',
      source: 'c',
    );
    expect(plp.allowed, isTrue);
    expect(plp.reason, isNull);

    final pdp = evaluate(
      runtime,
      screenId: 'commerce.pdp',
      sectionId: 'pdp.price',
      source: 'c',
    );
    expect(pdp.allowed, isTrue);
  });

  test('allows the base direction itself as a source', () {
    final result = evaluate(
      runtime,
      screenId: 'commerce.search',
      sectionId: 'search.search-field',
      source: 'a',
    );
    expect(result.allowed, isTrue);
  });

  test('rejects a source direction that does not expose the screen', () {
    final result = evaluate(
      runtime,
      screenId: 'commerce.plp',
      sectionId: 'plp.product-grid',
      source: 'b',
    );
    expect(result.allowed, isFalse);
    expect(result.reason, 'Not present in Direction B');
  });

  test('rejects a source direction that lacks the governed component', () {
    final result = evaluate(
      runtime,
      screenId: 'commerce.search',
      sectionId: 'search.search-field',
      source: 'c',
    );
    expect(result.allowed, isFalse);
    expect(result.reason, 'Not present in Direction C');
  });

  test('rejects an unknown section id', () {
    final result = evaluate(
      runtime,
      screenId: 'commerce.plp',
      sectionId: 'commerce.nope',
      source: 'a',
    );
    expect(result.allowed, isFalse);
    expect(result.reason, 'Unknown section');
  });

  test('rejects a section that does not belong to the screen', () {
    final result = evaluate(
      runtime,
      screenId: 'commerce.home',
      sectionId: 'plp.product-grid',
      source: 'a',
    );
    expect(result.allowed, isFalse);
    expect(result.reason, 'Section does not belong to this screen');
  });

  test('rejects an unknown direction', () {
    final result = evaluate(
      runtime,
      screenId: 'commerce.plp',
      sectionId: 'plp.product-grid',
      source: 'z',
    );
    expect(result.allowed, isFalse);
    expect(result.reason, 'Unknown direction');
  });

  test('rejects when the base screen does not expose the slot', () {
    final result = evaluate(
      runtime,
      screenId: 'commerce.plp',
      sectionId: 'plp.product-grid',
      source: 'a',
      base: 'b',
    );
    expect(result.allowed, isFalse);
    expect(result.reason, 'Not compatible with this screen layout');
  });

  test('rejects a source whose density is unsupported by the component binding', () {
    final spacious = PrototypeRuntime.fromMap(
      canonicalBundle(
        directionIds: const ['a', 'b'],
        patterns: const {'a': ['commerce.pdp']},
        components: const {'a': ['commerce.price-display']},
        densities: const {'a': 'spacious'},
      ),
    );

    final result = evaluate(
      spacious,
      screenId: 'commerce.pdp',
      sectionId: 'pdp.price',
      source: 'a',
    );
    expect(result.allowed, isFalse);
    expect(result.reason, 'Not compatible with this screen layout');
  });

  test('is deterministic and non-ranking across repeated calls', () {
    final first = evaluate(
      runtime,
      screenId: 'commerce.plp',
      sectionId: 'plp.product-grid',
      source: 'c',
    );
    final second = evaluate(
      runtime,
      screenId: 'commerce.plp',
      sectionId: 'plp.product-grid',
      source: 'c',
    );
    expect(first.allowed, second.allowed);
    expect(first.reason, second.reason);
  });
}
