class AgencyPrice {
  const AgencyPrice({required this.current, this.compareAt});

  final int current;
  final int? compareAt;
}

class AgencyProduct {
  const AgencyProduct({
    required this.id,
    required this.name,
    required this.price,
    this.sku,
    this.rating,
    this.stock,
    this.subtitle,
  });

  final String id;
  final String name;
  final AgencyPrice price;
  final String? sku;
  final double? rating;
  final int? stock;
  final String? subtitle;
}
