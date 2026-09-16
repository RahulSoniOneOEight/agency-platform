Map<String, dynamic> canonicalDirection({
  String id = 'a',
  String density = 'compact',
  String name = 'Search-led Trade',
  String strategicGoal = 'reduce known-item order time',
}) {
  return {
    'id': id,
    'name': name,
    'strategic_goal': strategicGoal,
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

/// Exact resolved-theme shape emitted by the design-contract compiler into the
/// client runtime bundle. Kept inline so Flutter tests never invent defaults.
Map<String, Object?> resolvedThemeMap({
  String primary = '#1155CC',
  String density = 'normal',
  double section = 40,
  double cardRadius = 20,
  String headingEmphasis = 'normal',
}) {
  return {
    'version': 1,
    'color': {
      'primary': primary,
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
    'typography': {
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
      'heading_emphasis': headingEmphasis,
    },
    'spacing': {
      'inline': 8,
      'control': 12,
      'card': 16,
      'tile': 12,
      'section': section,
    },
    'radius': {'control': 12, 'card': cardRadius},
    'elevation': {'card': 1, 'overlay': 4},
    'size': {'control_height': 44, 'control_height_compact': 36, 'icon': 20},
    'density': {'default': density},
    'motion': {
      'fast_ms': 150,
      'normal_ms': 250,
      'slow_ms': 400,
      'easing': 'ease-out',
    },
    'breakpoints': {'mobile': 0, 'tablet': 768, 'desktop': 1200},
  };
}

Map<String, dynamic> canonicalBundle({
  List<String> directionIds = const ['a', 'b'],
  Map<String, String>? names,
  Map<String, String>? strategicGoals,
  Map<String, dynamic>? fixtures,
  Map<String, dynamic>? resources,
  Map<String, Object?>? theme,
  Map<String, Map<String, Object?>>? directionThemes,
}) {
  return {
    'version': 1,
    'client_id': 'prototype-demo',
    'default_direction': 'a',
    'directions': {
      for (final id in directionIds)
        id: canonicalDirection(
          id: id,
          name: names?[id] ?? 'Search-led Trade',
          strategicGoal: strategicGoals?[id] ?? 'reduce known-item order time',
        ),
    },
    'fixtures': fixtures ?? defaultFixtures(),
    'theme': theme ?? resolvedThemeMap(),
    if (directionThemes != null) 'direction_themes': directionThemes,
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
