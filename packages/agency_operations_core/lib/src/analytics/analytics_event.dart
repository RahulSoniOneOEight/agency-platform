import 'package:flutter/foundation.dart';

/// A governed analytics event.
///
/// The event name is validated as non-empty. Parameters are stored as an
/// unmodifiable map so a tracked event cannot be mutated after construction.
final class AnalyticsEvent {
  AnalyticsEvent({
    required this.name,
    Map<String, Object?> parameters = const {},
    this.environment,
  }) : parameters = Map.unmodifiable(parameters) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
  }

  final String name;
  final Map<String, Object?> parameters;
  final String? environment;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnalyticsEvent &&
          other.name == name &&
          mapEquals(other.parameters, parameters) &&
          other.environment == environment;

  @override
  int get hashCode {
    final keys = parameters.keys.toList()..sort();
    return Object.hash(
      name,
      environment,
      Object.hashAll(keys),
      Object.hashAll(keys.map((key) => parameters[key])),
    );
  }

  @override
  String toString() =>
      'AnalyticsEvent(name: $name, environment: $environment, '
      'parameters: $parameters)';
}
