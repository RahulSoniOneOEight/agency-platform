/// Immutable per-screen review decision.
///
/// A decision optionally overrides the overall/screen direction and optionally
/// overrides individual governed sections. Both collections are wrapped so the
/// value object can never be mutated after construction.
final class ReviewScreenDecision {
  ReviewScreenDecision({
    this.direction,
    Map<String, String> sections = const {},
  }) : sections = Map<String, String>.unmodifiable(sections);

  /// Explicit screen direction override; `null` means inherit from overall.
  final String? direction;

  /// Section overrides keyed by governed section id (`sectionId -> directionId`).
  final Map<String, String> sections;

  factory ReviewScreenDecision.fromJson(Map<String, dynamic> json) {
    final direction = json['direction'];
    if (direction != null && direction is! String) {
      throw const FormatException('Invalid review screen decision direction');
    }
    if (direction is String && direction.trim().isEmpty) {
      throw const FormatException('Invalid review screen decision direction');
    }
    final rawSections = json['sections'];
    if (rawSections != null && rawSections is! Map) {
      throw const FormatException('Invalid review screen decision sections');
    }
    final sections = <String, String>{};
    if (rawSections is Map) {
      for (final entry in rawSections.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String ||
            key.trim().isEmpty ||
            value is! String ||
            value.trim().isEmpty) {
          throw const FormatException('Invalid review screen decision section');
        }
        sections[key] = value;
      }
    }
    return ReviewScreenDecision(
      direction: direction as String?,
      sections: sections,
    );
  }

  /// Deterministic canonical serialization: `direction` only when non-null and
  /// section keys sorted.
  Map<String, dynamic> toJson() {
    final sortedSections = sections.keys.toList()..sort();
    return {
      if (direction != null) 'direction': direction,
      'sections': {
        for (final key in sortedSections) key: sections[key],
      },
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReviewScreenDecision &&
        other.direction == direction &&
        _mapEquals(other.sections, sections);
  }

  @override
  int get hashCode => Object.hash(
        direction,
        Object.hashAllUnordered(
          sections.entries.map((entry) => Object.hash(entry.key, entry.value)),
        ),
      );
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
