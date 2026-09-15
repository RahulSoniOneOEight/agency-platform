import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/registry/canonical_pattern_adapter.dart';

void main() {
  test('every canonical pattern maps to a known internal registry key', () {
    for (final canonicalId in CanonicalPatternAdapter.canonicalIds) {
      final key = CanonicalPatternAdapter.toRegistryKey(canonicalId);
      expect(() => PatternRegistry.resolve(key), returnsNormally, reason: canonicalId);
    }
  });

  test('canonical mappings never collide on an internal key', () {
    final keys = CanonicalPatternAdapter.canonicalToRegistry.values.toList();
    expect(keys.toSet().length, keys.length);
  });

  test('unsupported canonical ids fail visibly without prefix stripping', () {
    expect(
      () => CanonicalPatternAdapter.toRegistryKey('commerce.checkout'),
      throwsArgumentError,
    );
    expect(
      () => CanonicalPatternAdapter.toRegistryKey('checkout'),
      throwsArgumentError,
    );
    expect(
      () => CanonicalPatternAdapter.toRegistryKey('commerce.unknown'),
      throwsArgumentError,
    );
  });
}
