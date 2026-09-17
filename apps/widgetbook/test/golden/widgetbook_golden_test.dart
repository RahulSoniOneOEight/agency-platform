import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Governed golden regression coverage for high-value reusable surfaces.
///
/// These are deterministic regression checks, **not** aesthetic judgments.
/// Baselines live beside this test under `goldens/` and change only through an
/// explicit, reviewer-controlled `flutter test --update-goldens` run; a failing
/// comparison never rewrites a baseline.
///
/// Coverage is intentionally selective: shared primitives and the product card
/// (with its governed variants, density, stock, and wrapping states) â€” not every
/// possible permutation.

const _sampleProduct = AgencyProduct(
  id: 'sku-108',
  name: 'Industrial LED Driver 60W',
  sku: 'LED-DRV-60W',
  stock: 84,
  rating: 4.6,
  price: AgencyPrice(current: 1899, compareAt: 2199),
);

const _longNameProduct = AgencyProduct(
  id: 'sku-110',
  name: 'Industrial-Grade Three-Phase Variable Frequency Drive with Brake Chopper',
  sku: 'VFD-3PH-BRK',
  stock: 3,
  price: AgencyPrice(current: 184999, compareAt: 199999),
);

const _outOfStockProduct = AgencyProduct(
  id: 'sku-111',
  name: 'Replacement Filter Cartridge',
  sku: 'FLT-REPL-01',
  stock: 0,
  price: AgencyPrice(current: 2499),
);

Future<void> _pumpGolden(
  WidgetTester tester,
  Widget child, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AgencyTheme.lightDefault(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('AgencyButton goldens', () {
    testWidgets('primary', (tester) async {
      await _pumpGolden(
        tester,
        SizedBox(
          width: 280,
          child: AgencyButton(label: 'Continue', onPressed: () {}),
        ),
        size: const Size(320, 160),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/agency_button_primary.png'),
      );
    });

    testWidgets('disabled', (tester) async {
      await _pumpGolden(
        tester,
        const SizedBox(
          width: 280,
          child: AgencyButton(label: 'Continue', onPressed: null),
        ),
        size: const Size(320, 160),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/agency_button_disabled.png'),
      );
    });
  });

  group('AgencySearchField goldens', () {
    testWidgets('default', (tester) async {
      await _pumpGolden(
        tester,
        const SizedBox(
          width: 360,
          child: AgencySearchField(hintText: 'Search products or SKU'),
        ),
        size: const Size(400, 140),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/agency_search_field_default.png'),
      );
    });
  });

  group('ProductCard goldens', () {
    testWidgets('standard', (tester) async {
      await _pumpGolden(
        tester,
        const SizedBox(width: 260, child: ProductCard(product: _sampleProduct)),
        size: const Size(300, 420),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/product_card_standard.png'),
      );
    });

    testWidgets('b2b dense', (tester) async {
      await _pumpGolden(
        tester,
        const SizedBox(
          width: 260,
          child: ProductCard(
            product: _sampleProduct,
            variant: ProductCardVariant.b2b,
            density: AgencyDensity.dense,
          ),
        ),
        size: const Size(300, 420),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/product_card_b2b_dense.png'),
      );
    });

    testWidgets('out of stock b2b', (tester) async {
      await _pumpGolden(
        tester,
        const SizedBox(
          width: 260,
          child: ProductCard(
            product: _outOfStockProduct,
            variant: ProductCardVariant.b2b,
          ),
        ),
        size: const Size(300, 420),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/product_card_out_of_stock_b2b.png'),
      );
    });

    testWidgets('long name wrapping', (tester) async {
      await _pumpGolden(
        tester,
        const SizedBox(
          width: 260,
          child: ProductCard(
            product: _longNameProduct,
            variant: ProductCardVariant.b2b,
          ),
        ),
        size: const Size(300, 420),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/product_card_long_name_b2b.png'),
      );
    });
  });
}
