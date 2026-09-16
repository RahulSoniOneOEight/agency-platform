import 'package:flutter/material.dart';

final RegExp _colorPattern = RegExp(r'^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$');

const List<String> _colorKeys = [
  'primary',
  'on_primary',
  'secondary',
  'on_secondary',
  'surface',
  'surface_muted',
  'text_primary',
  'text_secondary',
  'border',
  'error',
  'on_error',
];

const List<String> _spacingKeys = ['inline', 'control', 'card', 'tile', 'section'];
const List<String> _radiusKeys = ['control', 'card'];
const List<String> _elevationKeys = ['card', 'overlay'];
const List<String> _sizeKeys = ['control_height', 'control_height_compact', 'icon'];
const List<String> _breakpointKeys = ['mobile', 'tablet', 'desktop'];

const Set<String> _canonicalDensities = {'compact', 'normal', 'spacious'};

/// Typography semantics of a resolved agency theme.
@immutable
class AgencyTypography {
  const AgencyTypography({
    required this.fontFamily,
    required this.fontFallback,
    required this.display,
    required this.headline,
    required this.title,
    required this.body,
    required this.label,
    required this.lineHeightBody,
    required this.weightRegular,
    required this.weightEmphasis,
    required this.headingEmphasis,
  });

  final String fontFamily;
  final String fontFallback;
  final double display;
  final double headline;
  final double title;
  final double body;
  final double label;
  final double lineHeightBody;
  final int weightRegular;
  final int weightEmphasis;
  final String headingEmphasis;

  bool get hasStrongHeadings => headingEmphasis == 'strong';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgencyTypography &&
          fontFamily == other.fontFamily &&
          fontFallback == other.fontFallback &&
          display == other.display &&
          headline == other.headline &&
          title == other.title &&
          body == other.body &&
          label == other.label &&
          lineHeightBody == other.lineHeightBody &&
          weightRegular == other.weightRegular &&
          weightEmphasis == other.weightEmphasis &&
          headingEmphasis == other.headingEmphasis;

  @override
  int get hashCode => Object.hash(
        fontFamily,
        fontFallback,
        display,
        headline,
        title,
        body,
        label,
        lineHeightBody,
        weightRegular,
        weightEmphasis,
        headingEmphasis,
      );
}

/// Motion timing semantics of a resolved agency theme.
@immutable
class AgencyMotion {
  const AgencyMotion({
    required this.fastMs,
    required this.normalMs,
    required this.slowMs,
    required this.easing,
  });

  final int fastMs;
  final int normalMs;
  final int slowMs;
  final String easing;

  Duration get fast => Duration(milliseconds: fastMs);
  Duration get normal => Duration(milliseconds: normalMs);
  Duration get slow => Duration(milliseconds: slowMs);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgencyMotion &&
          fastMs == other.fastMs &&
          normalMs == other.normalMs &&
          slowMs == other.slowMs &&
          easing == other.easing;

  @override
  int get hashCode => Object.hash(fastMs, normalMs, slowMs, easing);
}

/// Fully resolved agency theme produced by the design-contract compiler.
///
/// This type parses the exact runtime bundle shape and deliberately inserts no
/// design defaults: an invalid or incomplete theme is a governed
/// [FormatException], never a silent fallback.
@immutable
class AgencyResolvedTheme {
  const AgencyResolvedTheme({
    required this.colors,
    required this.typography,
    required this.spacing,
    required this.radius,
    required this.elevation,
    required this.size,
    required this.density,
    required this.motion,
    required this.breakpoints,
  });

  static const int version = 1;

  final Map<String, Color> colors;
  final AgencyTypography typography;
  final Map<String, double> spacing;
  final Map<String, double> radius;
  final Map<String, double> elevation;
  final Map<String, double> size;
  final String density;
  final AgencyMotion motion;
  final Map<String, double> breakpoints;

  Color color(String key) {
    final value = colors[key];
    if (value == null) {
      throw FlutterError('AgencyResolvedTheme has no color "$key"');
    }
    return value;
  }

  factory AgencyResolvedTheme.fromJson(Map<String, Object?> json) {
    final rawVersion = json['version'];
    if (rawVersion is! int || rawVersion != version) {
      throw const FormatException('theme.version must be 1');
    }

    const groupNames = [
      'color',
      'typography',
      'spacing',
      'radius',
      'elevation',
      'size',
      'density',
      'motion',
      'breakpoints',
    ];
    final allowedKeys = <String>{'version', ...groupNames};
    for (final key in json.keys) {
      if (!allowedKeys.contains(key)) {
        throw FormatException('theme: unknown key "$key"');
      }
    }
    for (final name in groupNames) {
      if (!json.containsKey(name)) {
        throw FormatException('theme.$name is required');
      }
    }

    return AgencyResolvedTheme(
      colors: Map<String, Color>.unmodifiable(_parseColors(_group(json, 'color'))),
      typography: _parseTypography(_group(json, 'typography')),
      spacing: Map<String, double>.unmodifiable(
        _parseNumberGroup(_group(json, 'spacing'), 'spacing', _spacingKeys),
      ),
      radius: Map<String, double>.unmodifiable(
        _parseNumberGroup(_group(json, 'radius'), 'radius', _radiusKeys),
      ),
      elevation: Map<String, double>.unmodifiable(
        _parseNumberGroup(_group(json, 'elevation'), 'elevation', _elevationKeys),
      ),
      size: Map<String, double>.unmodifiable(
        _parseNumberGroup(_group(json, 'size'), 'size', _sizeKeys),
      ),
      density: _parseDensity(_group(json, 'density')),
      motion: _parseMotion(_group(json, 'motion')),
      breakpoints: Map<String, double>.unmodifiable(
        _parseNumberGroup(_group(json, 'breakpoints'), 'breakpoints', _breakpointKeys),
      ),
    );
  }
}

Map<String, Object?> _group(Map<String, Object?> json, String name) {
  final value = json[name];
  if (value is! Map) {
    throw FormatException('theme.$name must be an object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw FormatException('theme.$name keys must be strings');
    }
    result[key] = entry.value;
  }
  return result;
}

void _requireExactKeys(
  Map<String, Object?> group,
  String name,
  List<String> required,
) {
  final requiredSet = required.toSet();
  for (final key in group.keys) {
    if (!requiredSet.contains(key)) {
      throw FormatException('theme.$name: unknown key "$key"');
    }
  }
  for (final key in required) {
    if (!group.containsKey(key)) {
      throw FormatException('theme.$name.$key is required');
    }
  }
}

Map<String, Color> _parseColors(Map<String, Object?> group) {
  _requireExactKeys(group, 'color', _colorKeys);
  final result = <String, Color>{};
  for (final key in _colorKeys) {
    final value = group[key];
    if (value is! String || !_colorPattern.hasMatch(value)) {
      throw FormatException('theme.color.$key must be a #RRGGBB or #AARRGGBB color');
    }
    final hex = value.substring(1);
    final parsed = int.parse(hex, radix: 16);
    result[key] = hex.length == 6 ? Color(0xFF000000 | parsed) : Color(parsed);
  }
  return result;
}

Map<String, double> _parseNumberGroup(
  Map<String, Object?> group,
  String name,
  List<String> keys,
) {
  _requireExactKeys(group, name, keys);
  final result = <String, double>{};
  for (final key in keys) {
    result[key] = _requireNumber(group, name, key);
  }
  return result;
}

AgencyTypography _parseTypography(Map<String, Object?> group) {
  const keys = [
    'font_family',
    'font_fallback',
    'display',
    'headline',
    'title',
    'body',
    'label',
    'line_height_body',
    'weight_regular',
    'weight_emphasis',
    'heading_emphasis',
  ];
  _requireExactKeys(group, 'typography', keys);
  return AgencyTypography(
    fontFamily: _requireString(group, 'typography', 'font_family'),
    fontFallback: _requireString(group, 'typography', 'font_fallback'),
    display: _requireNumber(group, 'typography', 'display'),
    headline: _requireNumber(group, 'typography', 'headline'),
    title: _requireNumber(group, 'typography', 'title'),
    body: _requireNumber(group, 'typography', 'body'),
    label: _requireNumber(group, 'typography', 'label'),
    lineHeightBody: _requireNumber(group, 'typography', 'line_height_body'),
    weightRegular: _requireInt(group, 'typography', 'weight_regular'),
    weightEmphasis: _requireInt(group, 'typography', 'weight_emphasis'),
    headingEmphasis: _requireString(group, 'typography', 'heading_emphasis'),
  );
}

String _parseDensity(Map<String, Object?> group) {
  _requireExactKeys(group, 'density', const ['default']);
  final value = group['default'];
  if (value is! String || !_canonicalDensities.contains(value)) {
    throw const FormatException(
      'theme.density.default must be compact, normal, or spacious',
    );
  }
  return value;
}

AgencyMotion _parseMotion(Map<String, Object?> group) {
  const keys = ['fast_ms', 'normal_ms', 'slow_ms', 'easing'];
  _requireExactKeys(group, 'motion', keys);
  return AgencyMotion(
    fastMs: _requireInt(group, 'motion', 'fast_ms'),
    normalMs: _requireInt(group, 'motion', 'normal_ms'),
    slowMs: _requireInt(group, 'motion', 'slow_ms'),
    easing: _requireString(group, 'motion', 'easing'),
  );
}

double _requireNumber(Map<String, Object?> group, String name, String key) {
  final value = group[key];
  if (value is! num || !value.isFinite || value < 0) {
    throw FormatException('theme.$name.$key must be a finite non-negative number');
  }
  return value.toDouble();
}

int _requireInt(Map<String, Object?> group, String name, String key) {
  final value = group[key];
  if (value is! num ||
      !value.isFinite ||
      value < 0 ||
      value != value.truncateToDouble()) {
    throw FormatException('theme.$name.$key must be a non-negative integer');
  }
  return value.toInt();
}

String _requireString(Map<String, Object?> group, String name, String key) {
  final value = group[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('theme.$name.$key must be a non-empty string');
  }
  return value;
}

/// Agency-specific semantics not represented cleanly by Material [ThemeData].
@immutable
class AgencyThemeTokens extends ThemeExtension<AgencyThemeTokens> {
  const AgencyThemeTokens({
    required this.sectionSpacing,
    required this.cardSpacing,
    required this.tileGap,
    required this.inlineSpacing,
    required this.controlSpacing,
    required this.controlRadius,
    required this.cardRadius,
    required this.overlayElevation,
    required this.controlHeight,
    required this.compactControlHeight,
    required this.iconSize,
    required this.motionFast,
    required this.motionNormal,
    required this.breakpointMobile,
    required this.breakpointTablet,
    required this.breakpointDesktop,
    required this.density,
  });

  final double sectionSpacing;
  final double cardSpacing;
  final double tileGap;
  final double inlineSpacing;
  final double controlSpacing;
  final double controlRadius;
  final double cardRadius;
  final double overlayElevation;
  final double controlHeight;
  final double compactControlHeight;
  final double iconSize;
  final Duration motionFast;
  final Duration motionNormal;
  final double breakpointMobile;
  final double breakpointTablet;
  final double breakpointDesktop;
  final String density;

  factory AgencyThemeTokens.fromResolved(AgencyResolvedTheme theme) {
    return AgencyThemeTokens(
      sectionSpacing: theme.spacing['section']!,
      cardSpacing: theme.spacing['card']!,
      tileGap: theme.spacing['tile']!,
      inlineSpacing: theme.spacing['inline']!,
      controlSpacing: theme.spacing['control']!,
      controlRadius: theme.radius['control']!,
      cardRadius: theme.radius['card']!,
      overlayElevation: theme.elevation['overlay']!,
      controlHeight: theme.size['control_height']!,
      compactControlHeight: theme.size['control_height_compact']!,
      iconSize: theme.size['icon']!,
      motionFast: theme.motion.fast,
      motionNormal: theme.motion.normal,
      breakpointMobile: theme.breakpoints['mobile']!,
      breakpointTablet: theme.breakpoints['tablet']!,
      breakpointDesktop: theme.breakpoints['desktop']!,
      density: theme.density,
    );
  }

  /// Reads the ambient agency tokens, failing clearly when absent.
  static AgencyThemeTokens of(BuildContext context) {
    final tokens = Theme.of(context).extension<AgencyThemeTokens>();
    if (tokens == null) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary(
          'AgencyThemeTokens.of() was called with a context that does not '
          'contain AgencyThemeTokens.',
        ),
        ErrorDescription(
          'No AgencyThemeTokens ThemeExtension was found in the ambient '
          'ThemeData.',
        ),
        ErrorHint(
          'Wrap the widget tree in a Theme that includes '
          'AgencyTheme.light(resolvedTheme) or AgencyTheme.lightDefault().',
        ),
      ]);
    }
    return tokens;
  }

  @override
  AgencyThemeTokens copyWith({
    double? sectionSpacing,
    double? cardSpacing,
    double? tileGap,
    double? inlineSpacing,
    double? controlSpacing,
    double? controlRadius,
    double? cardRadius,
    double? overlayElevation,
    double? controlHeight,
    double? compactControlHeight,
    double? iconSize,
    Duration? motionFast,
    Duration? motionNormal,
    double? breakpointMobile,
    double? breakpointTablet,
    double? breakpointDesktop,
    String? density,
  }) {
    return AgencyThemeTokens(
      sectionSpacing: sectionSpacing ?? this.sectionSpacing,
      cardSpacing: cardSpacing ?? this.cardSpacing,
      tileGap: tileGap ?? this.tileGap,
      inlineSpacing: inlineSpacing ?? this.inlineSpacing,
      controlSpacing: controlSpacing ?? this.controlSpacing,
      controlRadius: controlRadius ?? this.controlRadius,
      cardRadius: cardRadius ?? this.cardRadius,
      overlayElevation: overlayElevation ?? this.overlayElevation,
      controlHeight: controlHeight ?? this.controlHeight,
      compactControlHeight: compactControlHeight ?? this.compactControlHeight,
      iconSize: iconSize ?? this.iconSize,
      motionFast: motionFast ?? this.motionFast,
      motionNormal: motionNormal ?? this.motionNormal,
      breakpointMobile: breakpointMobile ?? this.breakpointMobile,
      breakpointTablet: breakpointTablet ?? this.breakpointTablet,
      breakpointDesktop: breakpointDesktop ?? this.breakpointDesktop,
      density: density ?? this.density,
    );
  }

  @override
  AgencyThemeTokens lerp(covariant AgencyThemeTokens? other, double t) {
    if (other == null) {
      return this;
    }
    return AgencyThemeTokens(
      sectionSpacing: _lerpDouble(sectionSpacing, other.sectionSpacing, t),
      cardSpacing: _lerpDouble(cardSpacing, other.cardSpacing, t),
      tileGap: _lerpDouble(tileGap, other.tileGap, t),
      inlineSpacing: _lerpDouble(inlineSpacing, other.inlineSpacing, t),
      controlSpacing: _lerpDouble(controlSpacing, other.controlSpacing, t),
      controlRadius: _lerpDouble(controlRadius, other.controlRadius, t),
      cardRadius: _lerpDouble(cardRadius, other.cardRadius, t),
      overlayElevation: _lerpDouble(overlayElevation, other.overlayElevation, t),
      controlHeight: _lerpDouble(controlHeight, other.controlHeight, t),
      compactControlHeight: _lerpDouble(
        compactControlHeight,
        other.compactControlHeight,
        t,
      ),
      iconSize: _lerpDouble(iconSize, other.iconSize, t),
      motionFast: _lerpDuration(motionFast, other.motionFast, t),
      motionNormal: _lerpDuration(motionNormal, other.motionNormal, t),
      breakpointMobile: _lerpDouble(breakpointMobile, other.breakpointMobile, t),
      breakpointTablet: _lerpDouble(breakpointTablet, other.breakpointTablet, t),
      breakpointDesktop: _lerpDouble(breakpointDesktop, other.breakpointDesktop, t),
      density: t < 0.5 ? density : other.density,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgencyThemeTokens &&
          sectionSpacing == other.sectionSpacing &&
          cardSpacing == other.cardSpacing &&
          tileGap == other.tileGap &&
          inlineSpacing == other.inlineSpacing &&
          controlSpacing == other.controlSpacing &&
          controlRadius == other.controlRadius &&
          cardRadius == other.cardRadius &&
          overlayElevation == other.overlayElevation &&
          controlHeight == other.controlHeight &&
          compactControlHeight == other.compactControlHeight &&
          iconSize == other.iconSize &&
          motionFast == other.motionFast &&
          motionNormal == other.motionNormal &&
          breakpointMobile == other.breakpointMobile &&
          breakpointTablet == other.breakpointTablet &&
          breakpointDesktop == other.breakpointDesktop &&
          density == other.density;

  @override
  int get hashCode => Object.hash(
        sectionSpacing,
        cardSpacing,
        tileGap,
        inlineSpacing,
        controlSpacing,
        controlRadius,
        cardRadius,
        overlayElevation,
        controlHeight,
        compactControlHeight,
        iconSize,
        motionFast,
        motionNormal,
        breakpointMobile,
        breakpointTablet,
        breakpointDesktop,
        density,
      );
}

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

Duration _lerpDuration(Duration a, Duration b, double t) => Duration(
      microseconds:
          (a.inMicroseconds + (b.inMicroseconds - a.inMicroseconds) * t).round(),
    );
