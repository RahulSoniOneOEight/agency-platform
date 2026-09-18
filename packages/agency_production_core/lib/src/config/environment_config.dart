enum ProductionEnvironment { dev, staging, production }

final class EnvironmentConfig {
  EnvironmentConfig({
    required this.environment,
    required this.apiBaseUrl,
    this.supabaseUrl = '',
    this.supabaseAnonKey = '',
    this.analyticsEnabled = false,
    Map<String, bool> featureFlags = const {},
    Map<String, String> integrationModes = const {},
    this.appVersion,
  })  : featureFlags = Map.unmodifiable(featureFlags),
        integrationModes = Map.unmodifiable(integrationModes) {
    if (apiBaseUrl.trim().isEmpty) {
      throw ArgumentError.value(apiBaseUrl, 'apiBaseUrl', 'must not be empty');
    }
  }

  factory EnvironmentConfig.fromJson(Map<String, Object?> json) {
    for (final key in json.keys) {
      final normalized = key.toLowerCase();
      final privileged = _privilegedKeyFragments
          .any((fragment) => normalized.contains(fragment));
      if (privileged || !_allowedKeys.contains(key)) {
        throw FormatException(
          'Unsupported or privileged configuration key: $key',
        );
      }
    }

    final rawEnvironment = json['environment'];
    if (rawEnvironment is! String) {
      throw const FormatException(
        '"environment" is required and must be a string',
      );
    }
    final environment = switch (rawEnvironment) {
      'dev' => ProductionEnvironment.dev,
      'staging' => ProductionEnvironment.staging,
      'production' => ProductionEnvironment.production,
      _ => throw FormatException('Unsupported environment: $rawEnvironment'),
    };

    final apiBaseUrl = _readString(json, 'api_base_url');
    if (apiBaseUrl == null || apiBaseUrl.trim().isEmpty) {
      throw const FormatException(
        '"api_base_url" is required and must be a non-empty string',
      );
    }

    return EnvironmentConfig(
      environment: environment,
      apiBaseUrl: apiBaseUrl,
      supabaseUrl: _readString(json, 'supabase_url') ?? '',
      supabaseAnonKey: _readString(json, 'supabase_anon_key') ?? '',
      analyticsEnabled: _readBool(json, 'analytics_enabled') ?? false,
      featureFlags: _readBoolMap(json, 'feature_flags'),
      integrationModes: _readStringMap(json, 'integration_modes'),
      appVersion: _readString(json, 'app_version'),
    );
  }

  final ProductionEnvironment environment;
  final String apiBaseUrl;
  final String supabaseUrl;
  final String supabaseAnonKey;
  final bool analyticsEnabled;
  final Map<String, bool> featureFlags;
  final Map<String, String> integrationModes;
  final String? appVersion;
}

const Set<String> _allowedKeys = {
  'environment',
  'api_base_url',
  'supabase_url',
  'supabase_anon_key',
  'analytics_enabled',
  'feature_flags',
  'integration_modes',
  'app_version',
};

const List<String> _privilegedKeyFragments = [
  'service_role',
  'service-role',
  'secret',
  'private_key',
  'private-key',
  'password',
  'webhook',
  'whatsapp_token',
  'credential',
];

String? _readString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('"$key" must be a string');
  }
  return value;
}

bool? _readBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! bool) {
    throw FormatException('"$key" must be a boolean');
  }
  return value;
}

Map<String, bool> _readBoolMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return const {};
  }
  if (value is! Map) {
    throw FormatException('"$key" must be an object');
  }
  final result = <String, bool>{};
  for (final entry in value.entries) {
    final entryKey = entry.key;
    final entryValue = entry.value;
    if (entryKey is! String || entryValue is! bool) {
      throw FormatException('"$key" must map strings to booleans');
    }
    result[entryKey] = entryValue;
  }
  return result;
}

Map<String, String> _readStringMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return const {};
  }
  if (value is! Map) {
    throw FormatException('"$key" must be an object');
  }
  final result = <String, String>{};
  for (final entry in value.entries) {
    final entryKey = entry.key;
    final entryValue = entry.value;
    if (entryKey is! String || entryValue is! String) {
      throw FormatException('"$key" must map strings to strings');
    }
    result[entryKey] = entryValue;
  }
  return result;
}
