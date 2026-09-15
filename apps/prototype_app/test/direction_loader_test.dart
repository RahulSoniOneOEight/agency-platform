import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/direction/direction_loader.dart';
import 'package:prototype_app/runtime/prototype_runtime.dart';
import 'package:prototype_app/runtime/runtime_exception.dart';

import 'support/runtime_fixtures.dart';

Matcher throwsDirectionNotFound() => throwsA(
      isA<RuntimeException>()
          .having((error) => error.code, 'code', RuntimeException.directionNotFound),
    );

void main() {
  test('resolves a declared direction from the runtime', () {
    final runtime = PrototypeRuntime.fromMap(canonicalBundle());

    expect(DirectionLoader.resolve(runtime, 'a').id, 'a');
    expect(DirectionLoader.resolve(runtime, 'b').id, 'b');
  });

  test('direction c is absent for a two-direction client', () {
    final runtime = PrototypeRuntime.fromMap(
      canonicalBundle(directionIds: const ['a', 'b']),
    );

    expect(runtime.directions.containsKey('c'), isFalse);
    expect(() => DirectionLoader.resolve(runtime, 'c'), throwsDirectionNotFound());
  });

  test('unknown direction never falls back to direction a', () {
    final runtime = PrototypeRuntime.fromMap(canonicalBundle());

    expect(() => DirectionLoader.resolve(runtime, 'z'), throwsDirectionNotFound());
  });
}
