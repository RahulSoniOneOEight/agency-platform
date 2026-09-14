import 'package:agency_flutter_ui/agency_flutter_ui.dart';

class PrototypeDirection {
  const PrototypeDirection({
    required this.id,
    required this.name,
    required this.strategicGoal,
    required this.navigation,
    required this.primaryJourney,
    required this.discoveryModel,
    required this.merchandising,
    required this.density,
    required this.transactionModel,
    required this.patterns,
    required this.components,
  });

  final String id;
  final String name;
  final String strategicGoal;
  final String navigation;
  final String primaryJourney;
  final String discoveryModel;
  final String merchandising;
  final AgencyDensity density;
  final String transactionModel;
  final List<String> patterns;
  final List<String> components;

  bool get isTrade =>
      transactionModel.contains('rfq') ||
      transactionModel.contains('trade') ||
      navigation.contains('trade') ||
      navigation.contains('rfq') ||
      patterns.contains('trade-dashboard');

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

    final densityName = requiredString('density');
    final density = switch (densityName) {
      'airy' => AgencyDensity.airy,
      'balanced' => AgencyDensity.balanced,
      'dense' => AgencyDensity.dense,
      _ => throw FormatException('Unknown density: $densityName'),
    };

    return PrototypeDirection(
      id: requiredString('id'),
      name: requiredString('name'),
      strategicGoal: requiredString('strategic_goal'),
      navigation: requiredString('navigation'),
      primaryJourney: requiredString('primary_journey'),
      discoveryModel: requiredString('discovery_model'),
      merchandising: requiredString('merchandising'),
      density: density,
      transactionModel: requiredString('transaction_model'),
      patterns: requiredList('patterns'),
      components: requiredList('components'),
    );
  }
}
