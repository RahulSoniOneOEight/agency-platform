import 'package:agency_flutter_ui/agency_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Inline copy of the exact runtime resolved-theme shape emitted by the
/// design-contract compiler into the client runtime bundle.
Map<String, Object?> resolvedThemeJson() => {
      'version': 1,
      'color': <String, Object?>{
        'primary': '#1155CC',
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
      'typography': <String, Object?>{
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
        'heading_emphasis': 'normal',
      },
      'spacing': <String, Object?>{
        'inline': 8,
        'control': 12,
        'card': 16,
        'tile': 12,
        'section': 40,
      },
      'radius': <String, Object?>{'control': 12, 'card': 20},
      'elevation': <String, Object?>{'card': 1, 'overlay': 4},
      'size': <String, Object?>{'control_height': 44, 'control_height_compact': 36, 'icon': 20},
      'density': <String, Object?>{'default': 'spacious'},
      'motion': <String, Object?>{
        'fast_ms': 150,
        'normal_ms': 250,
        'slow_ms': 400,
        'easing': 'ease-out',
      },
      'breakpoints': <String, Object?>{'mobile': 0, 'tablet': 768, 'desktop': 1200},
    };

Map<String, Object?> withDensity(String density) {
  final json = resolvedThemeJson();
  (json['density']! as Map)['default'] = density;
  return json;
}

void main() {
  group('AgencyResolvedTheme.fromJson', () {
    test('parses the real resolved runtime shape', () {
      final theme = AgencyResolvedTheme.fromJson(resolvedThemeJson());

      expect(theme.colors['primary'], const Color(0xFF1155CC));
      expect(theme.colors['surface'], const Color(0xFFFFFFFF));
      expect(theme.colors['on_error'], const Color(0xFFFFFFFF));
      expect(theme.typography.fontFamily, 'Inter');
      expect(theme.typography.fontFallback, 'Roboto');
      expect(theme.typography.display, 40);
      expect(theme.typography.lineHeightBody, 1.5);
      expect(theme.typography.weightEmphasis, 700);
      expect(theme.typography.headingEmphasis, 'normal');
      expect(theme.spacing['section'], 40);
      expect(theme.radius['card'], 20);
      expect(theme.elevation['overlay'], 4);
      expect(theme.size['control_height'], 44);
      expect(theme.density, 'spacious');
      expect(theme.motion.fastMs, 150);
      expect(theme.motion.easing, 'ease-out');
      expect(theme.breakpoints['desktop'], 1200);
    });

    test('parses #AARRGGBB colors', () {
      final json = resolvedThemeJson();
      (json['color']! as Map)['surface'] = '#801155CC';
      final theme = AgencyResolvedTheme.fromJson(json);

      expect(theme.colors['surface'], const Color(0x801155CC));
    });

    test('rejects a missing group', () {
      final json = resolvedThemeJson()..remove('motion');
      expect(() => AgencyResolvedTheme.fromJson(json), throwsFormatException);
    });

    test('rejects an unknown top-level group', () {
      final json = resolvedThemeJson()..['extra'] = <String, Object?>{};
      expect(() => AgencyResolvedTheme.fromJson(json), throwsFormatException);
    });

    test('rejects an unknown key inside a group', () {
      final json = resolvedThemeJson();
      (json['spacing']! as Map)['gap'] = 4;
      expect(() => AgencyResolvedTheme.fromJson(json), throwsFormatException);
    });

    test('rejects a wrong value type', () {
      final json = resolvedThemeJson();
      (json['spacing']! as Map)['section'] = '40';
      expect(() => AgencyResolvedTheme.fromJson(json), throwsFormatException);
    });

    test('rejects a non-finite number', () {
      final json = resolvedThemeJson();
      (json['spacing']! as Map)['section'] = double.infinity;
      expect(() => AgencyResolvedTheme.fromJson(json), throwsFormatException);
    });

    test('rejects a negative number', () {
      final json = resolvedThemeJson();
      (json['spacing']! as Map)['section'] = -4;
      expect(() => AgencyResolvedTheme.fromJson(json), throwsFormatException);
    });

    test('rejects a malformed color', () {
      final json = resolvedThemeJson();
      (json['color']! as Map)['primary'] = '1155CC';
      expect(() => AgencyResolvedTheme.fromJson(json), throwsFormatException);
    });

    test('rejects a non-canonical density', () {
      expect(
        () => AgencyResolvedTheme.fromJson(withDensity('dense')),
        throwsFormatException,
      );
    });

    test('rejects a non-1 version', () {
      final json = resolvedThemeJson()..['version'] = 2;
      expect(() => AgencyResolvedTheme.fromJson(json), throwsFormatException);
    });

    test('parses all canonical densities', () {
      expect(AgencyResolvedTheme.fromJson(withDensity('compact')).density, 'compact');
      expect(AgencyResolvedTheme.fromJson(withDensity('normal')).density, 'normal');
      expect(AgencyResolvedTheme.fromJson(withDensity('spacious')).density, 'spacious');
    });
  });

  group('AgencyTheme.light', () {
    test('builds ThemeData from resolved semantic colors', () {
      final resolved = AgencyResolvedTheme.fromJson(resolvedThemeJson());
      final theme = AgencyTheme.light(resolved);

      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.primary, const Color(0xFF1155CC));
      expect(theme.colorScheme.secondary, const Color(0xFFEF8A23));
      expect(theme.colorScheme.onPrimary, const Color(0xFFFFFFFF));
      expect(theme.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
      expect(theme.cardTheme.elevation, 1);
    });

    test('builds the type scale from resolved typography', () {
      final resolved = AgencyResolvedTheme.fromJson(resolvedThemeJson());
      final theme = AgencyTheme.light(resolved);

      expect(theme.textTheme.bodyLarge!.fontSize, 15);
      expect(theme.textTheme.displayLarge!.fontSize, 40);
      expect(theme.textTheme.bodyLarge!.height, 1.5);
      expect(theme.textTheme.bodyLarge!.fontFamily, 'Roboto');
    });

    test('attaches AgencyThemeTokens with resolved semantics', () {
      final resolved = AgencyResolvedTheme.fromJson(resolvedThemeJson());
      final theme = AgencyTheme.light(resolved);

      final tokens = theme.extension<AgencyThemeTokens>();
      expect(tokens, isNotNull);
      expect(tokens!.sectionSpacing, 40);
      expect(tokens.cardRadius, 20);
      expect(tokens.controlRadius, 12);
      expect(tokens.motionFast, const Duration(milliseconds: 150));
      expect(tokens.density, 'spacious');
      expect(tokens.breakpointTablet, 768);
    });

    test('lightDefault uses the agency default resolved theme', () {
      final theme = AgencyTheme.lightDefault();

      expect(theme.colorScheme.primary, const Color(0xFF2454FF));
      expect(theme.scaffoldBackgroundColor, const Color(0xFFFFFFFF));
      expect(AgencyTheme.defaultResolved.density, 'normal');
      expect(AgencyTheme.defaultResolved.radius['card'], 20);
    });
  });

  group('AgencyThemeTokens.of', () {
    testWidgets('returns the ambient tokens', (tester) async {
      final theme = AgencyTheme.light(AgencyResolvedTheme.fromJson(resolvedThemeJson()));
      late AgencyThemeTokens tokens;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              tokens = AgencyThemeTokens.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(tokens.sectionSpacing, 40);
      expect(tokens.density, 'spacious');
    });

    testWidgets('throws a FlutterError when absent', (tester) async {
      Object? error;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              try {
                AgencyThemeTokens.of(context);
              } catch (caught) {
                error = caught;
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(error, isA<FlutterError>());
    });
  });
}
