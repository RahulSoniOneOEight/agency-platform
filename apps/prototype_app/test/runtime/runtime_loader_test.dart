import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/runtime/runtime_exception.dart';
import 'package:prototype_app/runtime/runtime_loader.dart';

class FakeAssetBundle extends CachingAssetBundle {
  FakeAssetBundle(this.values);

  final Map<String, String> values;

  @override
  Future<ByteData> load(String key) async {
    final value = values[key];
    if (value == null) {
      throw Exception('Unable to load asset: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(value)));
  }
}

String checkedInBundle() =>
    File('assets/generated/prototype-demo.json').readAsStringSync();

Matcher throwsRuntimeCode(String code) => throwsA(
      isA<RuntimeException>().having((error) => error.code, 'code', code),
    );

void main() {
  test('loads the checked-in prototype-demo runtime bundle', () async {
    final bundle = FakeAssetBundle({
      'assets/generated/prototype-demo.json': checkedInBundle(),
    });

    final runtime = await RuntimeLoader.loadClient('prototype-demo', bundle: bundle);

    expect(runtime.clientId, 'prototype-demo');
    expect(runtime.defaultDirection, 'a');
    expect(runtime.allowedDirections, ['a', 'b', 'c']);
    expect(runtime.directions.keys.toSet(), {'a', 'b', 'c'});
    expect(runtime.direction('b').navigationModel, 'dashboard');
    expect(runtime.direction('a').density.name, 'dense');
    expect(runtime.resource('asset.home.hero')!.candidateId, 'pexels-fixture-1001');
  });

  test('preserves canonical B.1C resource bindings from the checked-in bundle', () async {
    final bundle = FakeAssetBundle({
      'assets/generated/prototype-demo.json': checkedInBundle(),
    });

    final runtime = await RuntimeLoader.loadClient('prototype-demo', bundle: bundle);

    final hero = runtime.resource('asset.home.hero')!;
    expect(hero.id, 'asset.home.hero');
    expect(hero.candidateId, 'pexels-fixture-1001');
    expect(hero.source, 'pexels');
    expect(hero.type, 'image');
    expect(hero.asset, {
      'url': 'https://images.pexels.com/photos/fixture/hero.jpg',
      'width': 2400,
      'height': 1350,
    });

    final cart = runtime.resource('icon.commerce.cart')!;
    expect(cart.id, 'icon.commerce.cart');
    expect(cart.source, 'agency');
    expect(cart.type, 'icon');
    expect(cart.asset, {'provider': 'iconoir', 'name': 'cart'});

    final logo = runtime.resource('asset.brand.logo')!;
    expect(logo.id, 'asset.brand.logo');
    expect(logo.asset, {'path': 'input/brand/brand-assets/logo.svg'});

    expect(runtime.overridesFor('a'), isEmpty);
  });

  test('unknown client throws client_not_found without fallback', () async {
    final bundle = FakeAssetBundle({
      'assets/generated/prototype-demo.json': checkedInBundle(),
    });

    await expectLater(
      RuntimeLoader.loadClient('does-not-exist', bundle: bundle),
      throwsRuntimeCode(RuntimeException.clientNotFound),
    );
  });

  test('malformed JSON throws invalid_bundle', () async {
    final bundle = FakeAssetBundle({'assets/generated/acme.json': '{not json'});

    await expectLater(
      RuntimeLoader.loadClient('acme', bundle: bundle),
      throwsRuntimeCode(RuntimeException.invalidBundle),
    );
  });

  test('bundle client id mismatch throws invalid_bundle', () async {
    final mismatched =
        checkedInBundle().replaceFirst('"prototype-demo"', '"other-client"');
    final bundle = FakeAssetBundle({
      'assets/generated/prototype-demo.json': mismatched,
    });

    await expectLater(
      RuntimeLoader.loadClient('prototype-demo', bundle: bundle),
      throwsRuntimeCode(RuntimeException.invalidBundle),
    );
  });

  test('non-object bundle root throws invalid_bundle', () async {
    final bundle = FakeAssetBundle({'assets/generated/acme.json': '[]'});

    await expectLater(
      RuntimeLoader.loadClient('acme', bundle: bundle),
      throwsRuntimeCode(RuntimeException.invalidBundle),
    );
  });

  test('asset path is always derived from a safe client id', () async {
    expect(
      RuntimeLoader.assetPathFor('prototype-demo'),
      'assets/generated/prototype-demo.json',
    );

    await expectLater(
      RuntimeLoader.loadClient('../secrets'),
      throwsRuntimeCode(RuntimeException.clientNotFound),
    );
    await expectLater(
      RuntimeLoader.loadClient('nested/client'),
      throwsRuntimeCode(RuntimeException.clientNotFound),
    );
  });
}
