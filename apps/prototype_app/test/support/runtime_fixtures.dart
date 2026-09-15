Map<String, dynamic> canonicalDirection({
  String id = 'a',
  String density = 'compact',
}) {
  return {
    'id': id,
    'name': 'Search-led Trade',
    'strategic_goal': 'reduce known-item order time',
    'navigation_model': 'search-led',
    'primary_journey': 'search-to-order',
    'discovery_model': 'sku-search',
    'merchandising_model': 'availability-and-price',
    'density': density,
    'transaction_model': 'checkout-plus-rfq',
    'patterns': ['commerce.search'],
    'components': ['commerce.product-card'],
    'component_variants': [
      {'component': 'commerce.product-card', 'variant': 'b2b'},
    ],
    'required_resources': ['asset.home.hero'],
  };
}

Map<String, dynamic> defaultFixtures() {
  return {
    'industry': 'electronics-appliances',
    'seed': 108,
    'products': [
      {
        'id': 'prd-01',
        'sku': 'SKU-ELE-1000',
        'name': 'USB-C Hub',
        'price': 674,
        'compare_at': 674,
        'rating': 4.1,
        'stock': 18,
        'category': 'category-1',
      },
    ],
    'services': <dynamic>[],
  };
}

Map<String, dynamic> canonicalBundle({
  List<String> directionIds = const ['a', 'b'],
  Map<String, dynamic>? fixtures,
  Map<String, dynamic>? resources,
}) {
  return {
    'version': 1,
    'client_id': 'prototype-demo',
    'default_direction': 'a',
    'directions': {
      for (final id in directionIds) id: canonicalDirection(id: id),
    },
    'fixtures': fixtures ?? defaultFixtures(),
    'theme': {'seed_color': '#6750A4'},
    'resources': resources ??
        {
          'asset.home.hero': {
            'candidate_id': 'pexels-42',
            'source': 'pexels',
            'type': 'image',
            'asset': {'url': 'https://example.test/hero.jpg', 'width': 2400},
            'provider_extension': {'license': 'Pexels'},
          },
          'direction_overrides': {
            'b': {
              'asset.home.hero': {
                'candidate_id': 'client-hero',
                'source': 'client',
                'type': 'image',
                'asset': {'path': 'input/assets/hero.jpg'},
              },
            },
          },
        },
    'review': {
      'query_parameter': 'direction',
      'allowed_directions': directionIds,
    },
  };
}
