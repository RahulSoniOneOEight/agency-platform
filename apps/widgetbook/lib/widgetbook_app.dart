import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

final _sampleProduct = AgencyProduct(
  id: 'sku-108',
  name: 'Industrial LED Driver 60W',
  sku: 'LED-DRV-60W',
  stock: 84,
  rating: 4.6,
  price: AgencyPrice(current: 1899, compareAt: 2199),
);

Widget buildAgencyWidgetbook() {
  return Widgetbook.material(
    directories: [
      WidgetbookFolder(
        name: 'Primitives',
        children: [
          WidgetbookComponent(
            name: 'AgencyButton',
            useCases: [
              WidgetbookUseCase(
                name: 'Primary',
                builder: (_) => AgencyButton(label: 'Continue', onPressed: () {}),
              ),
              WidgetbookUseCase(
                name: 'Secondary',
                builder: (_) => AgencyButton(
                  label: 'Request quote',
                  variant: AgencyButtonVariant.secondary,
                  onPressed: () {},
                ),
              ),
            ],
          ),
          WidgetbookComponent(
            name: 'AgencySearchField',
            useCases: [
              WidgetbookUseCase(
                name: 'Default',
                builder: (_) => const SizedBox(
                  width: 360,
                  child: AgencySearchField(hintText: 'Search products or SKU'),
                ),
              ),
            ],
          ),
        ],
      ),
      WidgetbookFolder(
        name: 'Commerce',
        children: [
          WidgetbookComponent(
            name: 'ProductCard',
            useCases: [
              WidgetbookUseCase(
                name: 'Standard',
                builder: (_) => SizedBox(
                  width: 260,
                  child: ProductCard(product: _sampleProduct),
                ),
              ),
              WidgetbookUseCase(
                name: 'B2B',
                builder: (_) => SizedBox(
                  width: 260,
                  child: ProductCard(
                    product: _sampleProduct,
                    variant: ProductCardVariant.b2b,
                    density: AgencyDensity.dense,
                  ),
                ),
              ),
              WidgetbookUseCase(
                name: 'Compact',
                builder: (_) => SizedBox(
                  width: 220,
                  child: ProductCard(
                    product: _sampleProduct,
                    variant: ProductCardVariant.compact,
                    density: AgencyDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
    appBuilder: (context, child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AgencyTheme.light(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    ),
  );
}
