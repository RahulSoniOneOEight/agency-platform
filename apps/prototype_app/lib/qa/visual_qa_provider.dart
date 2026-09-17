/// Provider-neutral Visual AI QA seam.
///
/// A [VisualQaProvider] turns captured screenshots plus context and an explicit
/// **authority bundle** into normalized [VisualQaCandidate]s. It may only ever
/// produce candidates that map onto a [QaFinding]; it cannot approve experience,
/// change review status, resolve feedback, create refinement batches, mutate
/// runtime, or update baselines.
///
/// The comparison authority hierarchy is fixed and explicit:
/// approved experience → design contract → accepted baseline → linked reference
/// → general visual-quality heuristics. A lower layer can never be represented
/// as overriding a higher one.
library;

import 'qa_domain_error.dart';
import 'qa_finding.dart';

/// One layer of the authority bundle.
final class VisualQaAuthorityEntry {
  const VisualQaAuthorityEntry({
    required this.source,
    this.refs = const [],
    this.overridesHigherAuthority = false,
  });

  final QaRuleSource source;
  final List<String> refs;

  /// Must always be false; a lower layer may never override a higher one.
  final bool overridesHigherAuthority;

  Map<String, dynamic> toJson(int rank) => {
        'source': qaRuleSourceToWire(source),
        'authority_rank': rank,
        'refs': refs,
        'overrides_higher_authority': overridesHigherAuthority,
      };
}

/// An explicitly ordered, non-invertible authority bundle for a review request.
final class VisualQaAuthorityBundle {
  VisualQaAuthorityBundle({required List<VisualQaAuthorityEntry> entries})
      : entries = List<VisualQaAuthorityEntry>.unmodifiable(entries) {
    var lastRank = -1;
    final seen = <QaRuleSource>{};
    for (final entry in this.entries) {
      if (entry.overridesHigherAuthority) {
        throw const InvalidQaFinding(
          'no authority layer may override higher authority',
        );
      }
      if (!seen.add(entry.source)) {
        throw InvalidQaFinding(
          'authority source appears more than once: ${entry.source.name}',
        );
      }
      final rank = entry.source.authorityRank;
      if (rank <= lastRank) {
        throw const InvalidQaFinding(
          'authority bundle must be ordered highest authority first',
        );
      }
      lastRank = rank;
    }
  }

  final List<VisualQaAuthorityEntry> entries;

  factory VisualQaAuthorityBundle.fromJson(Map<String, dynamic> json) {
    final raw = json['layers'];
    if (raw is! List) {
      throw const InvalidQaFinding('authority bundle requires layers');
    }
    final entries = <VisualQaAuthorityEntry>[];
    for (final layer in raw) {
      if (layer is! Map || layer.keys.any((key) => key is! String)) {
        throw const InvalidQaFinding('authority layer must be an object');
      }
      final source = layer['source'];
      if (source is! String) {
        throw const InvalidQaFinding('authority layer requires a source');
      }
      final refs = layer['refs'] ?? const [];
      if (refs is! List || refs.any((ref) => ref is! String)) {
        throw const InvalidQaFinding('authority layer refs must be strings');
      }
      entries.add(
        VisualQaAuthorityEntry(
          source: qaRuleSourceFromWire(source),
          refs: refs.cast<String>(),
          overridesHigherAuthority:
              layer['overrides_higher_authority'] == true,
        ),
      );
    }
    return VisualQaAuthorityBundle(entries: entries);
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'layers': [
          for (var index = 0; index < entries.length; index++)
            entries[index].toJson(entries[index].source.authorityRank),
        ],
      };
}

/// Identity of a capture the provider is asked to review.
final class VisualQaArtifactRef {
  const VisualQaArtifactRef({
    required this.captureId,
    required this.contentHash,
    this.viewportWidth,
    this.viewportHeight,
  });

  final String captureId;
  final String contentHash;
  final int? viewportWidth;
  final int? viewportHeight;
}

/// What is being reviewed: client, surface, state, and source commit.
final class VisualQaContext {
  const VisualQaContext({
    required this.clientId,
    required this.surface,
    required this.state,
    required this.sourceCommitSha,
    this.screen,
    this.story,
    this.direction,
    this.mixRef,
    this.section,
    this.fixtureVersion,
  });

  final String clientId;
  final QaSurface surface;
  final String state;
  final String sourceCommitSha;
  final String? screen;
  final String? story;
  final String? direction;
  final String? mixRef;
  final String? section;
  final String? fixtureVersion;
}

/// A complete, provider-neutral review request.
final class VisualQaRequest {
  const VisualQaRequest({
    required this.context,
    required this.artifacts,
    required this.authority,
  });

  final VisualQaContext context;
  final List<VisualQaArtifactRef> artifacts;
  final VisualQaAuthorityBundle authority;
}

/// Provider-neutral review interface. Core records never depend on one model.
abstract interface class VisualQaProvider {
  String get name;

  Future<List<VisualQaCandidate>> review(VisualQaRequest request);
}

/// A validated, normalized candidate produced by a provider.
final class VisualQaCandidate {
  VisualQaCandidate._({
    required this.category,
    required this.severity,
    required this.summary,
    required this.surface,
    required this.state,
    required this.screenshotRef,
    required this.ruleSource,
    required this.ruleRef,
    required this.evidence,
    this.screen,
    this.story,
    this.direction,
    this.mixRef,
    this.section,
    this.region,
    this.baselineRef,
    this.confidence,
  });

  final String category;
  final QaSeverity severity;
  final String summary;
  final QaSurface surface;
  final String state;
  final String screenshotRef;
  final QaRuleSource ruleSource;
  final String ruleRef;
  final List<QaEvidence> evidence;
  final String? screen;
  final String? story;
  final String? direction;
  final String? mixRef;
  final String? section;
  final QaRegion? region;
  final String? baselineRef;
  final double? confidence;

  /// Keys a provider must never emit: automated QA cannot express review
  /// authority or collapse findings into a single design score.
  static const Set<String> forbiddenKeys = {
    'feedback_id',
    'blocking',
    'review_status',
    'approval',
    'approved',
    'resolved',
    'resolution',
    'quality_score',
    'score',
    'overall_score',
    'merge_gate',
  };

  factory VisualQaCandidate.fromJson(Map<String, dynamic> json) {
    final forbidden = forbiddenKeys.intersection(json.keys.toSet());
    if (forbidden.isNotEmpty) {
      throw InvalidQaFinding(
        'QA candidate must not express review authority: '
        '${forbidden.toList()..sort()}',
      );
    }

    String require(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw InvalidQaFinding('QA candidate missing $key');
      }
      return value;
    }

    String? optional(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String || value.trim().isEmpty) {
        throw InvalidQaFinding('QA candidate $key must be a string');
      }
      return value;
    }

    final surface = qaSurfaceFromWire(require('surface'));
    final screen = optional('screen');
    final story = optional('story');
    if (surface == QaSurface.prototype && screen == null) {
      throw const InvalidQaFinding('prototype QA candidate requires a screen');
    }
    if (surface == QaSurface.widgetbook && story == null) {
      throw const InvalidQaFinding('widgetbook QA candidate requires a story');
    }

    final confidence = json['confidence'];
    if (confidence != null && confidence is! num) {
      throw const InvalidQaFinding('QA candidate confidence must be numeric');
    }
    final confidenceValue = confidence == null ? null : (confidence as num).toDouble();
    if (confidenceValue != null &&
        (confidenceValue.isNaN ||
            confidenceValue.isInfinite ||
            confidenceValue < 0 ||
            confidenceValue > 1)) {
      throw const InvalidQaFinding(
        'QA candidate confidence must be within [0, 1]',
      );
    }

    QaRegion? region;
    final rawRegion = json['region'];
    if (rawRegion != null) {
      if (rawRegion is! Map || rawRegion.keys.any((key) => key is! String)) {
        throw const InvalidQaFinding('QA candidate region must be an object');
      }
      region = QaRegion.fromJson(rawRegion.cast<String, dynamic>());
    }

    final rawEvidence = json['evidence'] ?? const [];
    if (rawEvidence is! List) {
      throw const InvalidQaFinding('QA candidate evidence must be a list');
    }
    final evidence = <QaEvidence>[];
    for (final item in rawEvidence) {
      if (item is! Map || item.keys.any((key) => key is! String)) {
        throw const InvalidQaFinding('QA candidate evidence must be an object');
      }
      evidence.add(QaEvidence.fromJson(item.cast<String, dynamic>()));
    }

    return VisualQaCandidate._(
      category: require('category'),
      severity: qaSeverityFromWire(require('severity')),
      summary: require('summary'),
      surface: surface,
      state: require('state'),
      screenshotRef: require('screenshot_ref'),
      ruleSource: qaRuleSourceFromWire(require('rule_source')),
      ruleRef: require('rule_ref'),
      evidence: evidence,
      screen: screen,
      story: story,
      direction: optional('direction'),
      mixRef: optional('mix_ref'),
      section: optional('section'),
      region: region,
      baselineRef: optional('baseline_ref'),
      confidence: confidenceValue,
    );
  }

  /// Maps the candidate onto a `detected` [QaFinding].
  ///
  /// This is the only conversion a provider's output may undergo: it produces an
  /// automated QA finding, never human-review feedback.
  QaFinding toFinding({
    required String id,
    required VisualQaContext context,
    required String actorId,
    required DateTime at,
  }) {
    return QaFinding.detected(
      id: id,
      clientId: context.clientId,
      severity: severity,
      category: category,
      surface: surface,
      screen: screen,
      story: story,
      state: state,
      direction: direction ?? context.direction,
      mixRef: mixRef ?? context.mixRef,
      section: section ?? context.section,
      region: region,
      screenshotRef: screenshotRef,
      sourceCommitSha: context.sourceCommitSha,
      ruleSource: ruleSource,
      ruleRef: ruleRef,
      baselineRef: baselineRef,
      summary: summary,
      evidence: evidence,
      confidence: confidence,
      actorId: actorId,
      at: at,
    );
  }
}

/// Deterministic, offline provider used by tests and ordinary CI.
final class FixtureVisualQaProvider implements VisualQaProvider {
  FixtureVisualQaProvider({List<VisualQaCandidate> candidates = const []})
      : _candidates = List<VisualQaCandidate>.unmodifiable(candidates);

  final List<VisualQaCandidate> _candidates;

  @override
  String get name => 'fixture';

  @override
  Future<List<VisualQaCandidate>> review(VisualQaRequest request) async =>
      _candidates;
}
