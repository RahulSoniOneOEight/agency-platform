import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

const _sampleProduct = AgencyProduct(
  id: 'sku-108',
  name: 'Industrial LED Driver 60W',
  sku: 'LED-DRV-60W',
  stock: 84,
  rating: 4.6,
  price: AgencyPrice(current: 1899, compareAt: 2199),
);

const _sampleSecondProduct = AgencyProduct(
  id: 'sku-109',
  name: '65W USB-C Charger',
  sku: 'CHG-65W',
  stock: 47,
  rating: 4.5,
  price: AgencyPrice(current: 1799),
);

Widget buildAgencyWidgetbook() {
  return Widgetbook.material(
    directories: [
      WidgetbookCategory(
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
      WidgetbookCategory(
        name: 'Commerce',
        children: [
          WidgetbookComponent(
            name: 'ProductCard',
            useCases: [
              WidgetbookUseCase(
                name: 'Standard',
                builder: (_) => const SizedBox(
                  width: 260,
                  child: ProductCard(product: _sampleProduct),
                ),
              ),
              WidgetbookUseCase(
                name: 'B2B dense',
                builder: (_) => const SizedBox(
                  width: 260,
                  child: ProductCard(
                    product: _sampleProduct,
                    variant: ProductCardVariant.b2b,
                    density: AgencyDensity.dense,
                  ),
                ),
              ),
              WidgetbookUseCase(
                name: 'Compact card',
                builder: (_) => const SizedBox(
                  width: 220,
                  child: ProductCard(
                    product: _sampleProduct,
                    variant: ProductCardVariant.compact,
                    density: AgencyDensity.dense,
                  ),
                ),
              ),
            ],
          ),
          WidgetbookComponent(
            name: 'MerchandisingSplitTile',
            useCases: [
              WidgetbookUseCase(
                name: 'Complementary products',
                builder: (_) => const SizedBox(
                  width: 560,
                  child: MerchandisingSplitTile(
                    title: 'Complete the setup',
                    left: _sampleProduct,
                    right: _sampleSecondProduct,
                  ),
                ),
              ),
            ],
          ),
          WidgetbookComponent(
            name: 'Trade',
            useCases: [
              WidgetbookUseCase(
                name: 'Credit summary',
                builder: (_) => const SizedBox(
                  width: 420,
                  child: CreditSummary(limit: 250000, used: 92000),
                ),
              ),
              WidgetbookUseCase(
                name: 'Quote',
                builder: (_) => const SizedBox(
                  width: 420,
                  child: QuoteCard(
                    quoteId: 'QT-24017',
                    status: 'Awaiting approval',
                    total: 78600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      WidgetbookCategory(
        name: 'Patterns',
        children: [
          WidgetbookComponent(
            name: 'TradeDashboard',
            useCases: [
              WidgetbookUseCase(
                name: 'Default',
                builder: (_) => const SizedBox(
                  width: 900,
                  height: 700,
                  child: TradeDashboardPattern(),
                ),
              ),
            ],
          ),
          WidgetbookComponent(
            name: 'RFQ',
            useCases: [
              WidgetbookUseCase(
                name: 'Default',
                builder: (_) => const SizedBox(
                  width: 900,
                  height: 700,
                  child: RfqPattern(products: [_sampleProduct, _sampleSecondProduct]),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
    appBuilder: (context, child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AgencyTheme.lightDefault(),
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
