import '../direction/prototype_direction.dart';
import 'resource_binding.dart';
import 'runtime_theme.dart';

/// Immutable aggregate of one generated client runtime bundle.
///
/// This is the single source of client-specific directions, fixtures, theme,
/// and B.1C resource bindings for the shared Flutter prototype app. There is no
/// hard-coded client data and no implicit fallback: a requested direction that
/// is not declared by this runtime is a governed error handled by the loader.
class PrototypeRuntime {
  const PrototypeRuntime({
    required this.clientId,
    required this.defaultDirection,
    required this.directions,
    required this.fixtures,
    required this.theme,
    required this.directionThemes,
    required this.resources,
    required this.directionOverrides,
    required this.allowedDirections,
    required this.queryParameter,
  });

  final String clientId;
  final String defaultDirection;
  final Map<String, PrototypeDirection> directions;
  final Map<String, dynamic> fixtures;

  /// Resolved base theme (preset + brand, preset density).
  final RuntimeTheme theme;

  /// Resolved per-direction themes keyed by direction id.
  final Map<String, RuntimeTheme> directionThemes;

  final Map<String, ResourceBinding> resources;

  /// Canonical resources scoped to a specific direction, keyed by canonical
  /// resource ID. Base bindings are intentionally not merged here; selecting
  /// and merging base and override bindings remains outside B.1B.
  final Map<String, Map<String, ResourceBinding>> directionOverrides;
  final List<String> allowedDirections;
  final String? queryParameter;

  /// The active resolved theme: the direction theme when declared, otherwise
  /// the resolved base theme. Never a seed fallback.
  RuntimeTheme themeForDirection(String directionId) =>
      directionThemes[directionId] ?? theme;

  PrototypeDirection direction(String id) {
    final value = directions[id];
    if (value == null) {
      throw FormatException('Unknown direction: $id');
    }
    return value;
  }

  PrototypeDirection get defaultDirectionValue => direction(defaultDirection);

  ResourceBinding? resource(String id) => resources[id];

  Map<String, ResourceBinding> overridesFor(String directionId) =>
      directionOverrides[directionId] ?? const {};

  factory PrototypeRuntime.fromMap(Map<String, dynamic> map) {
    if (map['version'] != 1) {
      throw const FormatException('Runtime bundle version must be 1');
    }

    final clientId = map['client_id'];
    if (clientId is! String || clientId.trim().isEmpty) {
      throw const FormatException('Missing runtime client_id');
    }

    final rawDirections = map['directions'];
    if (rawDirections is! Map || rawDirections.length < 2 || rawDirections.length > 3) {
      throw const FormatException('Runtime must declare two or three directions');
    }

    final directions = <String, PrototypeDirection>{};
    for (final entry in rawDirections.entries) {
      final id = entry.key;
      final value = entry.value;
      if (id is! String || value is! Map) {
        throw const FormatException('Invalid runtime direction entry');
      }
      final direction = PrototypeDirection.fromMap(value.cast<String, dynamic>());
      if (direction.id != id) {
        throw FormatException('Direction key $id does not match embedded id ${direction.id}');
      }
      directions[id] = direction;
    }

    final defaultDirection = map['default_direction'];
    if (defaultDirection is! String || !directions.containsKey(defaultDirection)) {
      throw const FormatException('Runtime default_direction must exist in directions');
    }

    final rawAllowed = (map['review'] is Map)
        ? (map['review'] as Map)['allowed_directions']
        : null;
    if (rawAllowed is! List || rawAllowed.any((item) => item is! String)) {
      throw const FormatException('Runtime review.allowed_directions must be a string list');
    }
    final allowedDirections = rawAllowed.cast<String>();
    if (allowedDirections.toSet().length != allowedDirections.length ||
        allowedDirections.toSet().difference(directions.keys.toSet()).isNotEmpty ||
        directions.keys.toSet().difference(allowedDirections.toSet()).isNotEmpty) {
      throw const FormatException('Runtime allowed_directions must match declared directions');
    }

    final rawFixtures = map['fixtures'];
    if (rawFixtures is! Map) {
      throw const FormatException('Runtime fixtures must be an object');
    }

    final rawTheme = map['theme'];
    if (rawTheme is! Map) {
      throw const FormatException('Runtime theme must be a resolved theme object');
    }
    final RuntimeTheme theme;
    try {
      theme = RuntimeTheme.fromJson(rawTheme.cast<String, Object?>());
    } on FormatException catch (error) {
      throw FormatException('Runtime theme is invalid: ${error.message}');
    }

    final rawDirectionThemes = map['direction_themes'] ?? const <String, dynamic>{};
    if (rawDirectionThemes is! Map) {
      throw const FormatException('Runtime direction_themes must be an object');
    }
    final directionThemes = <String, RuntimeTheme>{};
    for (final entry in rawDirectionThemes.entries) {
      final directionId = entry.key;
      if (directionId is! String || !directions.containsKey(directionId)) {
        throw FormatException(
          'Runtime direction_themes references unknown direction: $directionId',
        );
      }
      final value = entry.value;
      if (value is! Map) {
        throw FormatException('Runtime direction_themes[$directionId] must be an object');
      }
      try {
        directionThemes[directionId] =
            RuntimeTheme.fromJson(value.cast<String, Object?>());
      } on FormatException catch (error) {
        throw FormatException(
          'Runtime direction_themes[$directionId] is invalid: ${error.message}',
        );
      }
    }

    final rawResources = map['resources'] ?? const <String, dynamic>{};
    if (rawResources is! Map) {
      throw const FormatException('Runtime resources must be an object');
    }

    final resources = <String, ResourceBinding>{};
    final directionOverrides = <String, Map<String, ResourceBinding>>{};
    for (final entry in rawResources.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String) {
        throw const FormatException('Runtime resource IDs must be strings');
      }
      if (key == 'direction_overrides') {
        if (value is! Map) {
          throw const FormatException('Runtime resources.direction_overrides must be an object');
        }
        for (final override in value.entries) {
          final directionId = override.key;
          final group = override.value;
          if (directionId is! String || !directions.containsKey(directionId)) {
            throw FormatException('Resource override references unknown direction: $directionId');
          }
          if (group is! Map) {
            throw FormatException('Resource override group for $directionId must be an object');
          }
          final bindings = <String, ResourceBinding>{};
          for (final binding in group.entries) {
            final resourceId = binding.key;
            final payload = binding.value;
            if (resourceId is! String || payload is! Map) {
              throw FormatException('Invalid resource override for $directionId');
            }
            bindings[resourceId] =
                ResourceBinding.fromMap(resourceId, payload.cast<String, dynamic>());
          }
          directionOverrides[directionId] = bindings;
        }
        continue;
      }
      if (value is! Map) {
        throw FormatException('Invalid resource binding: $key');
      }
      resources[key] = ResourceBinding.fromMap(key, value.cast<String, dynamic>());
    }

    return PrototypeRuntime(
      clientId: clientId,
      defaultDirection: defaultDirection,
      directions: Map<String, PrototypeDirection>.unmodifiable(directions),
      fixtures: Map<String, dynamic>.from(rawFixtures),
      theme: theme,
      directionThemes: Map<String, RuntimeTheme>.unmodifiable(directionThemes),
      resources: Map<String, ResourceBinding>.unmodifiable(resources),
      directionOverrides: Map<String, Map<String, ResourceBinding>>.unmodifiable(
        directionOverrides.map(
          (key, value) =>
              MapEntry(key, Map<String, ResourceBinding>.unmodifiable(value)),
        ),
      ),
      allowedDirections: List<String>.unmodifiable(allowedDirections),
      queryParameter: (map['review'] is Map &&
              (map['review'] as Map)['query_parameter'] is String)
          ? (map['review'] as Map)['query_parameter'] as String
          : null,
    );
  }
}
