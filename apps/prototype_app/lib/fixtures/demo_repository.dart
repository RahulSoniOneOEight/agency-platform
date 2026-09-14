import 'package:agency_flutter_ui/agency_flutter_ui.dart';

abstract final class DemoRepository {
  static const products = <AgencyProduct>[
    AgencyProduct(id: 'p1', name: 'USB-C Hub', sku: 'SKU-ELE-1001', price: AgencyPrice(current: 2499, compareAt: 2999), rating: 4.6, stock: 24),
    AgencyProduct(id: 'p2', name: 'Wireless Mouse', sku: 'SKU-ELE-1002', price: AgencyPrice(current: 1899), rating: 4.5, stock: 68),
    AgencyProduct(id: 'p3', name: 'Mechanical Keyboard', sku: 'SKU-ELE-1003', price: AgencyPrice(current: 4999, compareAt: 5499), rating: 4.7, stock: 31),
    AgencyProduct(id: 'p4', name: '27-inch Monitor', sku: 'SKU-ELE-1004', price: AgencyPrice(current: 17999), rating: 4.4, stock: 12),
    AgencyProduct(id: 'p5', name: 'Laptop Stand', sku: 'SKU-ELE-1005', price: AgencyPrice(current: 1599), rating: 4.3, stock: 46),
    AgencyProduct(id: 'p6', name: '65W Charger', sku: 'SKU-ELE-1006', price: AgencyPrice(current: 1799, compareAt: 2099), rating: 4.6, stock: 53),
    AgencyProduct(id: 'p7', name: 'Noise-Cancel Headphones', sku: 'SKU-ELE-1007', price: AgencyPrice(current: 8499), rating: 4.8, stock: 18),
    AgencyProduct(id: 'p8', name: 'Portable SSD', sku: 'SKU-ELE-1008', price: AgencyPrice(current: 6799), rating: 4.7, stock: 27),
  ];

  static const services = <String>[
    'Initial Consultation',
    'Express Repair',
    'Home Visit',
    'Annual Maintenance',
  ];
}
