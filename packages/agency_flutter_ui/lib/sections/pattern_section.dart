import 'package:flutter/material.dart';

import '../foundation/agency_tokens.dart';
import '../patterns/pattern_shell.dart';

/// One governed, ordered composition slot of a prototype pattern.
///
/// A [PatternSection] is a stable composition boundary identified by [id]. It is
/// not a component library and does not own identity authority: the widget in
/// [child] is the existing shared implementation. Patterns and the review mixed
/// preview compose the same [PatternSection] instances so there is exactly one
/// screen implementation.
class PatternSection {
  const PatternSection({required this.id, required this.child});

  /// Stable section id (e.g. `plp.product-grid`).
  final String id;

  /// The existing shared widget rendered in this slot.
  final Widget child;
}

/// The full composition of a pattern: shell metadata plus ordered sections.
///
/// Rendering a composition through [buildPatternComposition] reproduces the
/// exact same [AgencyPatternShell] child list the pattern rendered before the
/// C.3 section seam was introduced.
class PatternComposition {
  const PatternComposition({
    required this.title,
    this.subtitle,
    required this.density,
    required this.sections,
  });

  final String title;
  final String? subtitle;
  final AgencyDensity density;
  final List<PatternSection> sections;
}

/// Renders a [PatternComposition] through the shared [AgencyPatternShell].
Widget buildPatternComposition(PatternComposition composition) {
  return AgencyPatternShell(
    title: composition.title,
    subtitle: composition.subtitle,
    density: composition.density,
    children: [for (final section in composition.sections) section.child],
  );
}
