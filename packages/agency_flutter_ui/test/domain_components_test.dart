import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const product = AgencyProduct(
    id: 'p1',
    name: 'USB-C Hub',
    price: AgencyPrice(current: 2499, compareAt: 2999),
    rating: 4.6,
    stock: 24,
  );

  testWidgets('product card renders product and B2B SKU context', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ProductCard(
          product: product,
          variant: ProductCardVariant.b2b,
          density: AgencyDensity.dense,
        ),
      ),
    ));
    expect(find.text('USB-C Hub'), findsOneWidget);
    expect(find.textContaining('₹'), findsWidgets);
  });

  testWidgets('credit summary exposes available credit', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: CreditSummary(limit: 100000, used: 35000)),
    ));
    expect(find.textContaining('65,000'), findsOneWidget);
  });

  testWidgets('merchandising split tile renders two product slots', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MerchandisingSplitTile(
          title: 'Complete the setup',
          left: product,
          right: AgencyProduct(
            id: 'p2',
            name: '65W Charger',
            price: AgencyPrice(current: 1799),
          ),
        ),
      ),
    ));
    expect(find.text('USB-C Hub'), findsOneWidget);
    expect(find.text('65W Charger'), findsOneWidget);
  });
}
