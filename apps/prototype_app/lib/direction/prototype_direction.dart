import 'package:agency_flutter_ui/agency_flutter_ui.dart';

class ComponentVariant {
  const ComponentVariant({required this.component, required this.variant});

  final String component;
  final String variant;

  factory ComponentVariant.fromMap(Map<String, dynamic> map) {
    final component = map['component'];
    final variant = map['variant'];
    if (component is! String || component.trim().isEmpty) {
      throw const FormatException('Missing component variant component');
    }
    if (variant is! String || variant.trim().isEmpty) {
      throw const FormatException('Missing component variant variant');
    }
    return ComponentVariant(component: component, variant: variant);
  }
}

class PrototypeDirection {
  const PrototypeDirection({
    required this.id,
    required this.name,
    required this.strategicGoal,
    required this.navigationModel,
    required this.primaryJourney,
    required this.discoveryModel,
    required this.merchandisingModel,
    required this.canonicalDensity,
    required this.density,
    required this.transactionModel,
    required this.patterns,
    required this.components,
    required this.componentVariants,
    required this.requiredResources,
  });

  final String id;
  final String name;
  final String strategicGoal;
  final String navigationModel;
  final String primaryJourney;
  final String discoveryModel;
  final String merchandisingModel;
  final String canonicalDensity;
  final AgencyDensity density;
  final String transactionModel;
  final List<String> patterns;
  final List<String> components;
  final List<ComponentVariant> componentVariants;
  final List<String> requiredResources;

  bool get isTrade =>
      transactionModel.contains('rfq') ||
      transactionModel.contains('trade') ||
      navigationModel.contains('trade') ||
      navigationModel.contains('rfq') ||
      patterns.contains('commerce.trade-dashboard');

  factory PrototypeDirection.fromMap(Map<String, dynamic> map) {
    String requiredString(String key) {
      final value = map[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Missing direction field: $key');
      }
      return value;
    }

    List<String> requiredList(String key) {
      final value = map[key];
      if (value is! List || value.isEmpty || value.any((item) => item is! String)) {
        throw FormatException('Invalid direction list: $key');
      }
      return value.cast<String>();
    }

    List<String> optionalStringList(String key) {
      final value = map[key];
      if (value == null) return const [];
      if (value is! List || value.any((item) => item is! String)) {
        throw FormatException('Invalid direction list: $key');
      }
      return value.cast<String>();
    }

    List<ComponentVariant> optionalVariants(String key) {
      final value = map[key];
      if (value == null) return const [];
      if (value is! List) {
        throw FormatException('Invalid direction list: $key');
      }
      return value
          .map((item) {
            if (item is! Map) {
              throw FormatException('Invalid component variant entry: $key');
            }
            return ComponentVariant.fromMap(item.cast<String, dynamic>());
          })
          .toList(growable: false);
    }

    final densityName = requiredString('density');
    final density = switch (densityName) {
      'compact' => AgencyDensity.dense,
      'normal' => AgencyDensity.balanced,
      'spacious' => AgencyDensity.airy,
      _ => throw FormatException('Unknown density: $densityName'),
    };

    return PrototypeDirection(
      id: requiredString('id'),
      name: requiredString('name'),
      strategicGoal: requiredString('strategic_goal'),
      navigationModel: requiredString('navigation_model'),
      primaryJourney: requiredString('primary_journey'),
      discoveryModel: requiredString('discovery_model'),
      merchandisingModel: requiredString('merchandising_model'),
      canonicalDensity: densityName,
      density: density,
      transactionModel: requiredString('transaction_model'),
      patterns: requiredList('patterns'),
      components: requiredList('components'),
      componentVariants: optionalVariants('component_variants'),
      requiredResources: optionalStringList('required_resources'),
    );
  }
}
