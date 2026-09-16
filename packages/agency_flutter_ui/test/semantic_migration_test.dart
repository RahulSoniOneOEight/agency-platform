import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a minimal resolved-theme map matching the runtime bundle shape.
///
/// Values are parameterized so two themes can differ only in the semantics
/// under test (spacing/radius/control sizing).
Map<String, Object?> resolvedThemeJson({
  required double cardSpacing,
  required double tileGap,
  required double sectionSpacing,
  required double controlRadius,
  required double cardRadius,
  required double controlHeight,
}) =>
    <String, Object?>{
      'version': 1,
      'color': <String, Object?>{
        'primary': '#1155CC',
        'on_primary': '#FFFFFF',
        'secondary': '#EF8A23',
        'on_secondary': '#FFFFFF',
        'surface': '#FFFFFF',
        'surface_muted': '#F7F8FA',
        'text_primary': '#16181D',
        'text_secondary': '#626874',
        'border': '#E4E6EB',
        'error': '#D32F2F',
        'on_error': '#FFFFFF',
      },
      'typography': <String, Object?>{
        'font_family': 'Inter',
        'font_fallback': 'Roboto',
        'display': 40,
        'headline': 32,
        'title': 22,
        'body': 15,
        'label': 13,
        'line_height_body': 1.5,
        'weight_regular': 400,
        'weight_emphasis': 700,
        'heading_emphasis': 'normal',
      },
      'spacing': <String, Object?>{
        'inline': 8,
        'control': 12,
        'card': cardSpacing,
        'tile': tileGap,
        'section': sectionSpacing,
      },
      'radius': <String, Object?>{'control': controlRadius, 'card': cardRadius},
      'elevation': <String, Object?>{'card': 1, 'overlay': 4},
      'size': <String, Object?>{
        'control_height': controlHeight,
        'control_height_compact': 36,
        'icon': 20,
      },
      'density': <String, Object?>{'default': 'normal'},
      'motion': <String, Object?>{
        'fast_ms': 150,
        'normal_ms': 250,
        'slow_ms': 400,
        'easing': 'ease-out',
      },
      'breakpoints': <String, Object?>{'mobile': 0, 'tablet': 768, 'desktop': 1200},
    };

final ThemeData themeA = AgencyTheme.light(
  AgencyResolvedTheme.fromJson(resolvedThemeJson(
    cardSpacing: 16,
    tileGap: 12,
    sectionSpacing: 32,
    controlRadius: 12,
    cardRadius: 20,
    controlHeight: 44,
  )),
);

final ThemeData themeB = AgencyTheme.light(
  AgencyResolvedTheme.fromJson(resolvedThemeJson(
    cardSpacing: 32,
    tileGap: 24,
    sectionSpacing: 48,
    controlRadius: 4,
    cardRadius: 40,
    controlHeight: 60,
  )),
);

const AgencyProduct product = AgencyProduct(
  id: 'p1',
  name: 'USB-C Hub',
  price: AgencyPrice(current: 2499, compareAt: 2999),
  rating: 4.6,
  stock: 24,
);

const AgencyProduct listProductA = AgencyProduct(
  id: 'l1',
  name: 'Hub',
  price: AgencyPrice(current: 999),
);

const AgencyProduct listProductB = AgencyProduct(
  id: 'l2',
  name: 'Arm',
  price: AgencyPrice(current: 1299),
);

Future<void> pumpThemed(WidgetTester tester, ThemeData theme, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(theme: theme, home: Scaffold(body: child)),
  );
  await tester.pumpAndSettle();
}

EdgeInsetsGeometry surfacePadding(WidgetTester tester, String label) {
  return tester
      .widget<Padding>(
        find.ancestor(of: find.text(label), matching: find.byType(Padding)).first,
      )
      .padding;
}

BorderRadius? productCardOuterRadius(WidgetTester tester) {
  final ink = tester.widget<InkWell>(
    find.descendant(of: find.byType(ProductCard), matching: find.byType(InkWell)),
  );
  return ink.borderRadius;
}

BorderRadius? productCardImageRadius(WidgetTester tester) {
  final containers = tester.widgetList<Container>(
    find.descendant(of: find.byType(ProductCard), matching: find.byType(Container)),
  );
  final image = containers.firstWhere(
    (c) =>
        c.decoration is BoxDecoration &&
        (c.decoration! as BoxDecoration).borderRadius != null,
  );
  return (image.decoration! as BoxDecoration).borderRadius as BorderRadius;
}

BorderRadius? firstProductCardRadius(WidgetTester tester) {
  final ink = tester.widget<InkWell>(
    find.descendant(
      of: find.byType(ProductCard).first,
      matching: find.byType(InkWell),
    ),
  );
  return ink.borderRadius;
}

Set<double> boxHeights(WidgetTester tester, Type ancestor) {
  return tester
      .widgetList<SizedBox>(
        find.descendant(of: find.byType(ancestor), matching: find.byType(SizedBox)),
      )
      .map((s) => s.height)
      .whereType<double>()
      .toSet();
}

void main() {
  testWidgets('AgencySurface default padding follows theme card spacing',
      (tester) async {
    await pumpThemed(tester, themeA, const AgencySurface(child: Text('surface')));
    expect(surfacePadding(tester, 'surface'), const EdgeInsets.all(16));

    await pumpThemed(tester, themeB, const AgencySurface(child: Text('surface')));
    expect(surfacePadding(tester, 'surface'), const EdgeInsets.all(32));
  });

  testWidgets('AgencySurface explicit padding still overrides the theme',
      (tester) async {
    await pumpThemed(
      tester,
      themeB,
      const AgencySurface(
        padding: EdgeInsets.all(4),
        child: Text('surface'),
      ),
    );
    expect(surfacePadding(tester, 'surface'), const EdgeInsets.all(4));
  });

  testWidgets('ProductCard uses theme cardRadius, controlRadius and tileGap',
      (tester) async {
    await pumpThemed(tester, themeA, const ProductCard(product: product));
    expect(productCardOuterRadius(tester), BorderRadius.circular(20));
    expect(productCardImageRadius(tester), BorderRadius.circular(12));
    expect(boxHeights(tester, ProductCard), contains(12.0));

    await pumpThemed(tester, themeB, const ProductCard(product: product));
    expect(productCardOuterRadius(tester), BorderRadius.circular(40));
    expect(productCardImageRadius(tester), BorderRadius.circular(4));
    expect(boxHeights(tester, ProductCard), contains(24.0));
  });

  testWidgets('AgencySearchField uses theme control height and radius',
      (tester) async {
    await pumpThemed(
      tester,
      themeA,
      const SizedBox(width: 360, child: AgencySearchField()),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    final border = field.decoration!.border! as OutlineInputBorder;
    expect(border.borderRadius, BorderRadius.circular(12));
    final box = tester.widget<SizedBox>(
      find.ancestor(of: find.byType(TextField), matching: find.byType(SizedBox)).first,
    );
    expect(box.height, 44);

    await pumpThemed(
      tester,
      themeB,
      const SizedBox(width: 360, child: AgencySearchField()),
    );
    final fieldB = tester.widget<TextField>(find.byType(TextField));
    final borderB = fieldB.decoration!.border! as OutlineInputBorder;
    expect(borderB.borderRadius, BorderRadius.circular(4));
    final boxB = tester.widget<SizedBox>(
      find.ancestor(of: find.byType(TextField), matching: find.byType(SizedBox)).first,
    );
    expect(boxB.height, 60);
  });

  testWidgets('AgencyButton uses theme control height and radius',
      (tester) async {
    await pumpThemed(
      tester,
      themeA,
      AgencyButton(label: 'Continue', onPressed: () {}),
    );
    final buttonA = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(buttonA.style!.minimumSize!.resolve(const <WidgetState>{})!.height, 44);
    final shapeA =
        buttonA.style!.shape!.resolve(const <WidgetState>{})! as RoundedRectangleBorder;
    expect(shapeA.borderRadius, BorderRadius.circular(12));

    await pumpThemed(
      tester,
      themeB,
      AgencyButton(label: 'Continue', onPressed: () {}),
    );
    final buttonB = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(buttonB.style!.minimumSize!.resolve(const <WidgetState>{})!.height, 60);
    final shapeB =
        buttonB.style!.shape!.resolve(const <WidgetState>{})! as RoundedRectangleBorder;
    expect(shapeB.borderRadius, BorderRadius.circular(4));
  });

  testWidgets('CategoryTile uses theme card radius and tile gap', (tester) async {
    await pumpThemed(tester, themeA, const CategoryTile(label: 'Cables'));
    final inkA = tester.widget<InkWell>(find.byType(InkWell));
    expect(inkA.borderRadius, BorderRadius.circular(20));
    final decorationA =
        tester.widget<Container>(find.byType(Container)).decoration! as BoxDecoration;
    expect(decorationA.borderRadius, BorderRadius.circular(20));
    expect(boxHeights(tester, CategoryTile), contains(12.0));

    await pumpThemed(tester, themeB, const CategoryTile(label: 'Cables'));
    final inkB = tester.widget<InkWell>(find.byType(InkWell));
    expect(inkB.borderRadius, BorderRadius.circular(40));
    expect(boxHeights(tester, CategoryTile), contains(24.0));
  });

  testWidgets('AgencyPatternShell uses theme section spacing', (tester) async {
    await pumpThemed(
      tester,
      themeA,
      const AgencyPatternShell(title: 'Explore', children: [Text('a'), Text('b')]),
    );
    expect(boxHeights(tester, AgencyPatternShell), contains(32.0));

    await pumpThemed(
      tester,
      themeB,
      const AgencyPatternShell(title: 'Explore', children: [Text('a'), Text('b')]),
    );
    expect(boxHeights(tester, AgencyPatternShell), contains(48.0));
  });

  testWidgets('AgencyButton secondary and text stay intrinsic width',
      (tester) async {
    await pumpThemed(
      tester,
      themeA,
      AgencyButton(
        label: 'Request quote',
        variant: AgencyButtonVariant.secondary,
        onPressed: () {},
      ),
    );
    final outlined = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    final outlinedMin =
        outlined.style!.minimumSize!.resolve(const <WidgetState>{})!;
    expect(outlinedMin.width, 0);
    expect(outlinedMin.height, 44);

    await pumpThemed(
      tester,
      themeA,
      AgencyButton(
        label: 'More',
        variant: AgencyButtonVariant.text,
        onPressed: () {},
      ),
    );
    final text = tester.widget<TextButton>(find.byType(TextButton));
    final textMin = text.style!.minimumSize!.resolve(const <WidgetState>{})!;
    expect(textMin.width, 0);
    expect(textMin.height, 44);
  });

  testWidgets('PlpPattern renders theme tile gap and card radius',
      (tester) async {
    await pumpThemed(
      tester,
      themeA,
      const PlpPattern(products: [listProductA, listProductB]),
    );
    final cardsA = find.byType(ProductCard);
    expect(cardsA, findsNWidgets(2));
    final gapA =
        tester.getTopLeft(cardsA.at(1)).dx - tester.getTopRight(cardsA.at(0)).dx;
    expect(gapA, 12);
    expect(firstProductCardRadius(tester), BorderRadius.circular(20));

    await pumpThemed(
      tester,
      themeB,
      const PlpPattern(products: [listProductA, listProductB]),
    );
    final cardsB = find.byType(ProductCard);
    expect(cardsB, findsNWidgets(2));
    final gapB =
        tester.getTopLeft(cardsB.at(1)).dx - tester.getTopRight(cardsB.at(0)).dx;
    expect(gapB, 24);
    expect(firstProductCardRadius(tester), BorderRadius.circular(40));
  });
}
