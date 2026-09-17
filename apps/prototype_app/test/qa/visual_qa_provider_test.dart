import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/qa/qa_domain_error.dart';
import 'package:prototype_app/qa/qa_finding.dart';
import 'package:prototype_app/qa/visual_qa_provider.dart';

Map<String, dynamic> candidateJson({
  String category = 'spacing',
  String severity = 'major',
  String summary = 'Product-card spacing is inconsistent with the governed token.',
  String surface = 'prototype',
  String? screen = 'commerce.home',
  String? story,
  String state = 'default',
  String? direction = 'b',
  String? mixRef,
  String? section = 'home.product-grid',
  Map<String, dynamic>? region,
  String screenshotRef = 'sha256:capture-1',
  String ruleSource = 'design_contract',
  String ruleRef = 'spacing.card.gap',
  String? baselineRef,
  double? confidence = 0.91,
  List<Map<String, dynamic>> evidence = const [],
}) {
  return {
    'category': category,
    'severity': severity,
    'summary': summary,
    'surface': surface,
    'screen': screen,
    'story': story,
    'state': state,
    'direction': direction,
    'mix_ref': mixRef,
    'section': section,
    'region': region,
    'screenshot_ref': screenshotRef,
    'rule_source': ruleSource,
    'rule_ref': ruleRef,
    'baseline_ref': baselineRef,
    'confidence': confidence,
    'evidence': evidence,
  };
}

VisualQaContext context() => const VisualQaContext(
      clientId: 'prototype-demo',
      surface: QaSurface.prototype,
      screen: 'commerce.home',
      state: 'default',
      direction: 'b',
      sourceCommitSha: 'abc123',
      fixtureVersion: 'demo-v1',
    );

VisualQaAuthorityBundle bundle() => VisualQaAuthorityBundle(
      entries: [
        const VisualQaAuthorityEntry(
          source: QaRuleSource.approvedExperience,
          refs: ['approved-experience.yaml'],
        ),
        const VisualQaAuthorityEntry(
          source: QaRuleSource.designContract,
          refs: ['design-contract/tokens'],
        ),
      ],
    );

void main() {
  group('authority bundle', () {
    test('entries must be ordered highest authority first', () {
      expect(
        () => VisualQaAuthorityBundle(
          entries: [
            const VisualQaAuthorityEntry(
              source: QaRuleSource.visualHeuristic,
              refs: ['heuristics'],
            ),
            const VisualQaAuthorityEntry(
              source: QaRuleSource.approvedExperience,
              refs: ['approved'],
            ),
          ],
        ),
        throwsA(isA<InvalidQaFinding>()),
      );
    });

    test('a source may appear at most once', () {
      expect(
        () => VisualQaAuthorityBundle(
          entries: [
            const VisualQaAuthorityEntry(
              source: QaRuleSource.designContract,
              refs: ['a'],
            ),
            const VisualQaAuthorityEntry(
              source: QaRuleSource.designContract,
              refs: ['b'],
            ),
          ],
        ),
        throwsA(isA<InvalidQaFinding>()),
      );
    });

    test('no layer may claim to override higher authority', () {
      expect(
        () => VisualQaAuthorityBundle(
          entries: [
            const VisualQaAuthorityEntry(
              source: QaRuleSource.approvedExperience,
              refs: ['approved'],
            ),
            const VisualQaAuthorityEntry(
              source: QaRuleSource.visualHeuristic,
              refs: ['heuristics'],
              overridesHigherAuthority: true,
            ),
          ],
        ),
        throwsA(isA<InvalidQaFinding>()),
      );
    });

    test('serializes every authority layer in order', () {
      final json = bundle().toJson();
      final layers = json['layers'] as List<dynamic>;
      expect(
        layers.map((layer) => (layer as Map)['source']),
        ['approved_experience', 'design_contract'],
      );
      expect(layers.map((layer) => (layer as Map)['authority_rank']), [0, 1]);
      expect(
        layers.every((layer) => (layer as Map)['overrides_higher_authority'] == false),
        isTrue,
      );
    });
  });

  group('candidate contract', () {
    test('a complete candidate is accepted', () {
      final candidate = VisualQaCandidate.fromJson(candidateJson());
      expect(candidate.category, 'spacing');
      expect(candidate.ruleSource, QaRuleSource.designContract);
      expect(candidate.severity, QaSeverity.major);
    });

    test('a candidate without a rule source is rejected', () {
      final json = candidateJson()..remove('rule_source');
      expect(
        () => VisualQaCandidate.fromJson(json),
        throwsA(isA<InvalidQaFinding>()),
      );
    });

    test('a candidate with an unknown severity is rejected', () {
      expect(
        () => VisualQaCandidate.fromJson(candidateJson(severity: 'critical')),
        throwsA(isA<InvalidQaFinding>()),
      );
    });

    test('a candidate without a screenshot reference is rejected', () {
      final json = candidateJson()..remove('screenshot_ref');
      expect(
        () => VisualQaCandidate.fromJson(json),
        throwsA(isA<InvalidQaFinding>()),
      );
    });

    test('a candidate cannot smuggle review authority', () {
      for (final forbidden in const [
        'feedback_id',
        'blocking',
        'review_status',
        'approval',
        'quality_score',
        'score',
      ]) {
        final json = candidateJson()..[forbidden] = 'x';
        expect(
          () => VisualQaCandidate.fromJson(json),
          throwsA(isA<InvalidQaFinding>()),
          reason: 'candidate must reject $forbidden',
        );
      }
    });

    test('an out-of-range region is rejected', () {
      expect(
        () => VisualQaCandidate.fromJson(
          candidateJson(region: {'x': -0.2, 'y': 0, 'width': 0.5, 'height': 0.5}),
        ),
        throwsA(isA<InvalidQaRegion>()),
      );
    });

    test('confidence must stay within the unit interval', () {
      expect(
        () => VisualQaCandidate.fromJson(candidateJson(confidence: 1.4)),
        throwsA(isA<InvalidQaFinding>()),
      );
    });

    test('a widgetbook candidate requires a story', () {
      expect(
        () => VisualQaCandidate.fromJson(
          candidateJson(surface: 'widgetbook', screen: null),
        ),
        throwsA(isA<InvalidQaFinding>()),
      );
      final story = VisualQaCandidate.fromJson(
        candidateJson(surface: 'widgetbook', screen: null, story: 'AgencyButton.Primary'),
      );
      expect(story.story, 'AgencyButton.Primary');
    });

    test('unknown candidate fields are rejected', () {
      final json = candidateJson()..['notes'] = 'free-form narration';
      expect(
        () => VisualQaCandidate.fromJson(json),
        throwsA(isA<InvalidQaFinding>()),
      );
    });

    test('candidate strings are trimmed at the boundary', () {
      final candidate = VisualQaCandidate.fromJson(
        candidateJson(category: '  spacing  ', ruleRef: ' spacing.card.gap '),
      );
      expect(candidate.category, 'spacing');
      expect(candidate.ruleRef, 'spacing.card.gap');
    });

    test('prototype candidates must not declare a story', () {
      expect(
        () => VisualQaCandidate.fromJson(
          candidateJson(story: 'AgencyButton.Primary'),
        ),
        throwsA(isA<InvalidQaFinding>()),
      );
    });

    test('widgetbook candidates must not declare a screen', () {
      expect(
        () => VisualQaCandidate.fromJson(
          candidateJson(
            surface: 'widgetbook',
            screen: 'commerce.home',
            story: 'AgencyButton.Primary',
          ),
        ),
        throwsA(isA<InvalidQaFinding>()),
      );
    });
  });

  group('candidate to finding mapping', () {
    test('a candidate maps onto a schema-valid QaFinding', () {
      final candidate = VisualQaCandidate.fromJson(
        candidateJson(region: {'x': 0.1, 'y': 0.4, 'width': 0.8, 'height': 0.2}),
      );
      final finding = candidate.toFinding(
        id: 'qa-001',
        context: context(),
        actorId: 'visual-qa',
        at: DateTime.utc(2026, 9, 17, 10),
      );
      expect(finding, isA<QaFinding>());
      expect(finding.status, QaFindingStatus.detected);
      expect(finding.clientId, 'prototype-demo');
      expect(finding.screenshotRef, 'sha256:capture-1');
      expect(finding.sourceCommitSha, 'abc123');
      expect(finding.region, isNotNull);
      expect(finding.blocking, isNull);
      expect(finding.dedupeKey, contains('qa-dedupe:v1'));
    });

    test('mapping never creates review or blocking state', () {
      final finding = VisualQaCandidate.fromJson(candidateJson())
          .toFinding(
        id: 'qa-002',
        context: context(),
        actorId: 'visual-qa',
        at: DateTime.utc(2026, 9, 17, 10),
      );
      expect(finding.feedbackId, isNull);
      expect(finding.isPromoted, isFalse);
      expect(finding.blocking, isNull);
    });

    test('the provider seam does not depend on the review subsystem', () {
      final source = File('lib/qa/visual_qa_provider.dart').readAsStringSync();
      expect(source.contains('feedback_record'), isFalse);
      expect(source.contains('review_coordinator'), isFalse);
      expect(source.contains('FeedbackRecord'), isFalse);
    });
  });

  group('provider neutrality', () {
    test('a fixture provider returns its deterministic candidates', () async {
      final provider = FixtureVisualQaProvider(
        candidates: [VisualQaCandidate.fromJson(candidateJson())],
      );
      final request = VisualQaRequest(
        context: context(),
        artifacts: const [
          VisualQaArtifactRef(
            captureId: 'sha256:capture-1',
            contentHash: 'sha256:content-1',
          ),
        ],
        authority: bundle(),
      );
      final first = await provider.review(request);
      final second = await provider.review(request);
      expect(first.map((candidate) => candidate.category), ['spacing']);
      expect(first, second);
      expect(provider.name, 'fixture');
    });

    test('any implementation of the interface is accepted', () async {
      final VisualQaProvider provider = _CustomProvider();
      final candidates = await provider.review(
        VisualQaRequest(
          context: context(),
          artifacts: const [],
          authority: bundle(),
        ),
      );
      expect(candidates, isEmpty);
      expect(provider.name, 'custom');
    });

    test('a request carries the artifact identity and authority bundle', () {
      final request = VisualQaRequest(
        context: context(),
        artifacts: const [
          VisualQaArtifactRef(
            captureId: 'sha256:capture-1',
            contentHash: 'sha256:content-1',
            viewportWidth: 390,
            viewportHeight: 844,
          ),
        ],
        authority: bundle(),
      );
      expect(request.artifacts.single.captureId, 'sha256:capture-1');
      expect(request.authority.entries.first.source, QaRuleSource.approvedExperience);
    });
  });
}

final class _CustomProvider implements VisualQaProvider {
  @override
  String get name => 'custom';

  @override
  Future<List<VisualQaCandidate>> review(VisualQaRequest request) async => const [];
}
