import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/qa/qa_domain_error.dart';
import 'package:prototype_app/qa/qa_finding.dart';

const reviewerId = 'reviewer-1';

DateTime at(int minute) => DateTime.utc(2026, 9, 17, 10, minute);

QaFinding sampleFinding({
  String id = 'qa-001',
  QaSeverity severity = QaSeverity.major,
  String category = 'spacing',
  QaSurface surface = QaSurface.prototype,
  String? screen = 'commerce.home',
  String? story,
  String state = 'default',
  String? direction = 'b',
  String? mixRef,
  String? section = 'home.product-grid',
  QaRegion? region,
  String screenshotRef = 'sha256:capture-1',
  String sourceCommitSha = 'abc123',
  QaRuleSource ruleSource = QaRuleSource.designContract,
  String ruleRef = 'spacing.card.gap',
  String? baselineRef,
  String summary = 'Product-card spacing is inconsistent with the governed token.',
  List<QaEvidence> evidence = const [],
  double? confidence = 0.91,
  DateTime? detectedAt,
}) {
  return QaFinding.detected(
    id: id,
    clientId: 'prototype-demo',
    severity: severity,
    category: category,
    surface: surface,
    screen: screen,
    story: story,
    state: state,
    direction: direction,
    mixRef: mixRef,
    section: section,
    region: region,
    screenshotRef: screenshotRef,
    sourceCommitSha: sourceCommitSha,
    ruleSource: ruleSource,
    ruleRef: ruleRef,
    baselineRef: baselineRef,
    summary: summary,
    evidence: evidence,
    confidence: confidence,
    actorId: 'visual-qa',
    at: detectedAt ?? at(0),
  );
}

void main() {
  group('lifecycle and append-only history', () {
    test('detected finding starts in the detected state', () {
      final finding = sampleFinding();
      expect(finding.status, QaFindingStatus.detected);
      expect(finding.isTerminal, isFalse);
      expect(finding.history.map((event) => event.event), [
        QaFindingEventType.detected,
      ]);
    });

    test('triage then dismiss preserves append-only history', () {
      final finding = sampleFinding();
      final triaged = finding.triage(actorId: reviewerId, at: at(1));
      final dismissed = triaged.dismiss(
        actorId: reviewerId,
        at: at(2),
        reason: 'not reproducible',
      );
      expect(dismissed.status, QaFindingStatus.dismissed);
      expect(dismissed.history.map((event) => event.event), [
        QaFindingEventType.detected,
        QaFindingEventType.triaged,
        QaFindingEventType.dismissed,
      ]);
      expect(dismissed.history.last.reason, 'not reproducible');
      // The earlier value objects are untouched.
      expect(finding.status, QaFindingStatus.detected);
      expect(triaged.status, QaFindingStatus.triaged);
      expect(triaged.history, hasLength(2));
    });

    test('accept risk records a reason', () {
      final accepted = sampleFinding()
          .triage(actorId: reviewerId, at: at(1))
          .acceptRisk(actorId: reviewerId, at: at(2), reason: 'approved dense layout');
      expect(accepted.status, QaFindingStatus.acceptedRisk);
      expect(accepted.history.last.reason, 'approved dense layout');
    });

    test('promotion requires triage first', () {
      expect(
        () => sampleFinding().promote(
          actorId: reviewerId,
          at: at(1),
          feedbackId: 'feedback-1',
        ),
        throwsA(isA<InvalidQaTransition>()),
      );
    });

    test('promotion stores the originating feedback id', () {
      final promoted = sampleFinding()
          .triage(actorId: reviewerId, at: at(1))
          .promote(actorId: reviewerId, at: at(2), feedbackId: 'feedback-1');
      expect(promoted.status, QaFindingStatus.promoted);
      expect(promoted.feedbackId, 'feedback-1');
      expect(promoted.isPromoted, isTrue);
      expect(promoted.isTerminal, isTrue);
      expect(promoted.history.last.feedbackId, 'feedback-1');
    });

    test('promotion requires a non-empty feedback id', () {
      final triaged = sampleFinding().triage(actorId: reviewerId, at: at(1));
      expect(
        () => triaged.promote(actorId: reviewerId, at: at(2), feedbackId: '  '),
        throwsA(isA<QaEvidenceMissing>()),
      );
    });

    test('terminal findings cannot be re-promoted or dismissed', () {
      final promoted = sampleFinding()
          .triage(actorId: reviewerId, at: at(1))
          .promote(actorId: reviewerId, at: at(2), feedbackId: 'feedback-1');
      expect(
        () => promoted.dismiss(actorId: reviewerId, at: at(3), reason: 'x'),
        throwsA(isA<InvalidQaTransition>()),
      );
      expect(
        () => promoted.promote(
          actorId: reviewerId,
          at: at(3),
          feedbackId: 'feedback-2',
        ),
        throwsA(isA<InvalidQaTransition>()),
      );
    });

    test('dismiss and accept-risk require a reason', () {
      final triaged = sampleFinding().triage(actorId: reviewerId, at: at(1));
      expect(
        () => triaged.dismiss(actorId: reviewerId, at: at(2), reason: ''),
        throwsA(isA<QaEvidenceMissing>()),
      );
      expect(
        () => triaged.acceptRisk(actorId: reviewerId, at: at(2), reason: ' '),
        throwsA(isA<QaEvidenceMissing>()),
      );
    });

    test('triage is only legal from detected', () {
      final triaged = sampleFinding().triage(actorId: reviewerId, at: at(1));
      expect(
        () => triaged.triage(actorId: reviewerId, at: at(2)),
        throwsA(isA<InvalidQaTransition>()),
      );
    });

    test('dismissal and accept-risk require prior triage', () {
      expect(
        () => sampleFinding().dismiss(actorId: reviewerId, at: at(1), reason: 'x'),
        throwsA(isA<InvalidQaTransition>()),
      );
      expect(
        () => sampleFinding().acceptRisk(
          actorId: reviewerId,
          at: at(1),
          reason: 'x',
        ),
        throwsA(isA<InvalidQaTransition>()),
      );
    });
  });

  group('severity semantics', () {
    test('severity does not imply review blocking', () {
      expect(sampleFinding(severity: QaSeverity.blocker).blocking, isNull);
      expect(sampleFinding(severity: QaSeverity.info).blocking, isNull);
    });

    test('every severity round-trips through the wire vocabulary', () {
      for (final severity in QaSeverity.values) {
        expect(qaSeverityFromWire(qaSeverityToWire(severity)), severity);
      }
      expect(
        QaSeverity.values.map(qaSeverityToWire),
        ['info', 'minor', 'major', 'blocker'],
      );
    });

    test('a blocker severity finding is not automatically terminal', () {
      expect(sampleFinding(severity: QaSeverity.blocker).status,
          QaFindingStatus.detected);
    });
  });

  group('authority hierarchy', () {
    test('rule sources are ordered by authority', () {
      expect(QaRuleSource.byAuthority, [
        QaRuleSource.approvedExperience,
        QaRuleSource.designContract,
        QaRuleSource.acceptedBaseline,
        QaRuleSource.linkedReference,
        QaRuleSource.visualHeuristic,
      ]);
      expect(
        QaRuleSource.approvedExperience.authorityRank,
        lessThan(QaRuleSource.visualHeuristic.authorityRank),
      );
    });

    test('a heuristic cannot outrank an approved decision', () {
      expect(
        QaRuleSource.visualHeuristic.outranks(QaRuleSource.approvedExperience),
        isFalse,
      );
      expect(
        QaRuleSource.approvedExperience.outranks(QaRuleSource.visualHeuristic),
        isTrue,
      );
    });

    test('rule source wire vocabulary is stable', () {
      expect(
        QaRuleSource.values.map(qaRuleSourceToWire),
        [
          'approved_experience',
          'design_contract',
          'accepted_baseline',
          'linked_reference',
          'visual_heuristic',
        ],
      );
    });

    test('findings record their provenance', () {
      final finding = sampleFinding(
        ruleSource: QaRuleSource.acceptedBaseline,
        ruleRef: 'baseline-001',
        baselineRef: 'baseline-001',
      );
      expect(finding.ruleSource, QaRuleSource.acceptedBaseline);
      expect(finding.ruleRef, 'baseline-001');
      expect(finding.baselineRef, 'baseline-001');
    });
  });

  group('evidence and regions', () {
    test('normalized regions are accepted', () {
      final region = QaRegion(x: 0.10, y: 0.42, width: 0.80, height: 0.24);
      expect(region.isNormalized, isTrue);
      expect(sampleFinding(region: region).region, region);
    });

    test('out-of-range regions are rejected', () {
      expect(
        () => QaRegion(x: -0.1, y: 0, width: 0.5, height: 0.5),
        throwsA(isA<InvalidQaRegion>()),
      );
      expect(
        () => QaRegion(x: 0.8, y: 0, width: 0.5, height: 0.5),
        throwsA(isA<InvalidQaRegion>()),
      );
      expect(
        () => QaRegion(x: 0, y: 0, width: 0, height: 0.5),
        throwsA(isA<InvalidQaRegion>()),
      );
    });

    test('evidence must carry a region, reference, or note', () {
      expect(() => QaEvidence(), throwsA(isA<InvalidQaEvidence>()));
      expect(
        QaEvidence(ref: 'diff.png').hasContent,
        isTrue,
      );
    });

    test('confidence must be within [0, 1]', () {
      expect(
        () => sampleFinding(confidence: 1.4),
        throwsA(isA<InvalidQaFinding>()),
      );
      expect(sampleFinding(confidence: null).confidence, isNull);
    });

    test('findings require concrete provenance and summary', () {
      expect(() => sampleFinding(summary: ' '), throwsA(isA<InvalidQaFinding>()));
      expect(
        () => sampleFinding(ruleRef: ''),
        throwsA(isA<InvalidQaFinding>()),
      );
      expect(
        () => sampleFinding(screenshotRef: ''),
        throwsA(isA<InvalidQaFinding>()),
      );
      expect(
        () => sampleFinding(sourceCommitSha: ''),
        throwsA(isA<InvalidQaFinding>()),
      );
    });

    test('surface identity must be well formed', () {
      expect(
        () => sampleFinding(surface: QaSurface.prototype, screen: null),
        throwsA(isA<InvalidQaFinding>()),
      );
      expect(
        () => sampleFinding(
          surface: QaSurface.prototype,
          screen: 'commerce.home',
          story: 'AgencyButton.Primary',
        ),
        throwsA(isA<InvalidQaFinding>()),
      );
      expect(
        () => sampleFinding(
          surface: QaSurface.widgetbook,
          screen: null,
          story: null,
        ),
        throwsA(isA<InvalidQaFinding>()),
      );
      expect(
        () => sampleFinding(
          surface: QaSurface.widgetbook,
          screen: 'commerce.home',
          story: 'AgencyButton.Primary',
        ),
        throwsA(isA<InvalidQaFinding>()),
      );
      final story = sampleFinding(
        surface: QaSurface.widgetbook,
        screen: null,
        story: 'AgencyButton.Primary',
      );
      expect(story.story, 'AgencyButton.Primary');
      expect(story.screen, isNull);
    });
  });

  group('deduplication identity', () {
    test('the same issue rediscovered keeps the same dedupe key', () {
      final first = sampleFinding(confidence: 0.5);
      final second = sampleFinding(
        confidence: 0.99,
        evidence: [QaEvidence(note: 're-observed')],
      );
      expect(first.dedupeKey, second.dedupeKey);
    });

    test('a different region produces a different dedupe key', () {
      final one = sampleFinding(
        region: QaRegion(x: 0, y: 0, width: 0.2, height: 0.2),
      );
      final two = sampleFinding(
        region: QaRegion(x: 0.5, y: 0.5, width: 0.2, height: 0.2),
      );
      expect(one.dedupeKey, isNot(two.dedupeKey));
    });

    test('a different rule, category, or baseline produces a different key', () {
      final base = sampleFinding();
      expect(sampleFinding(ruleRef: 'spacing.section.gap').dedupeKey,
          isNot(base.dedupeKey));
      expect(sampleFinding(category: 'clipping').dedupeKey, isNot(base.dedupeKey));
      expect(sampleFinding(baselineRef: 'baseline-9').dedupeKey,
          isNot(base.dedupeKey));
    });

    test('dedupe key is stable across serialization', () {
      final finding = sampleFinding();
      final restored = QaFinding.fromJson(finding.toJson());
      expect(restored.dedupeKey, finding.dedupeKey);
    });

    test('dedupe key matches the python contract formula', () {
      expect(
        sampleFinding().dedupeKey,
        'qa-dedupe:v1|prototype-demo|prototype|commerce.home|'
        'design_contract|spacing.card.gap|spacing|home.product-grid||',
      );
    });

    test('padded identity fields normalize to the same dedupe key', () {
      final clean = sampleFinding();
      final padded = QaFinding.detected(
        id: 'qa-padded',
        clientId: ' prototype-demo ',
        severity: QaSeverity.major,
        category: '  spacing  ',
        surface: QaSurface.prototype,
        screen: ' commerce.home ',
        state: 'default',
        direction: 'b',
        section: ' home.product-grid ',
        screenshotRef: 'sha256:capture-1',
        sourceCommitSha: 'abc123',
        ruleSource: QaRuleSource.designContract,
        ruleRef: ' spacing.card.gap ',
        summary: 'x',
        actorId: 'visual-qa',
        at: at(0),
      );
      expect(padded.dedupeKey, clean.dedupeKey);
    });
  });

  group('recurrence and no-longer-reproducible', () {
    test('a recheck can mark a finding no longer reproducible', () {
      final rechecked = sampleFinding().markNoLongerReproducible(
        actorId: 'qa-runner',
        at: at(5),
        runId: 'run-1',
      );
      expect(rechecked.isNoLongerReproducible, isTrue);
      expect(rechecked.status, QaFindingStatus.detected);
    });

    test('a promoted finding may be marked no longer reproducible', () {
      final promoted = sampleFinding()
          .triage(actorId: reviewerId, at: at(1))
          .promote(actorId: reviewerId, at: at(2), feedbackId: 'feedback-1')
          .markNoLongerReproducible(actorId: 'qa-runner', at: at(3), runId: 'run-1');
      expect(promoted.isNoLongerReproducible, isTrue);
      expect(promoted.feedbackId, 'feedback-1');
      expect(promoted.status, QaFindingStatus.promoted);
    });

    test('a recurrence clears the no-longer-reproducible flag', () {
      final finding = sampleFinding()
          .markNoLongerReproducible(actorId: 'qa-runner', at: at(1), runId: 'run-1')
          .recordRecurrence(actorId: 'qa-runner', at: at(2), runId: 'run-2');
      expect(finding.isNoLongerReproducible, isFalse);
      expect(finding.recurrences, 1);
      expect(finding.history.map((event) => event.event), [
        QaFindingEventType.detected,
        QaFindingEventType.noLongerReproducible,
        QaFindingEventType.recurrence,
      ]);
    });

    test('evidence can be linked without changing status', () {
      final linked = sampleFinding().linkEvidence(
        actorId: 'qa-runner',
        at: at(1),
        evidence: [QaEvidence(ref: 'diff-run-2.png')],
        runId: 'run-2',
      );
      expect(linked.status, QaFindingStatus.detected);
      expect(linked.evidence, hasLength(1));
      expect(linked.history.last.event, QaFindingEventType.evidenceLinked);
      expect(linked.history.last.runId, 'run-2');
    });

    test('evidence cannot be linked without content', () {
      expect(
        () => sampleFinding().linkEvidence(
          actorId: 'qa-runner',
          at: at(1),
          evidence: [],
        ),
        throwsA(isA<QaEvidenceMissing>()),
      );
    });
  });

  group('serialization', () {
    test('round-trips through canonical json', () {
      final finding = sampleFinding(
        region: QaRegion(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
        evidence: [
          QaEvidence(region: QaRegion(x: 0, y: 0, width: 1, height: 1), note: 'grid'),
        ],
        confidence: 0.5,
      );
      final restored = QaFinding.fromJson(finding.toJson());
      expect(restored, finding);
      expect(restored.toJson(), finding.toJson());
    });

    test('always emits every canonical key', () {
      final json = sampleFinding().toJson();
      expect(json.keys.toSet(), {
        'id',
        'client_id',
        'status',
        'severity',
        'category',
        'surface',
        'screen',
        'story',
        'state',
        'direction',
        'mix_ref',
        'section',
        'region',
        'screenshot_ref',
        'source_commit_sha',
        'rule_source',
        'rule_ref',
        'baseline_ref',
        'summary',
        'evidence',
        'confidence',
        'dedupe_key',
        'feedback_id',
        'no_longer_reproducible',
        'recurrences',
        'history',
      });
    });

    test('malformed payloads fail with typed QA errors', () {
      expect(
        () => QaFinding.fromJson(sampleFinding().toJson()..['status'] = 'approved'),
        throwsA(isA<InvalidQaFinding>()),
      );
      expect(
        () => QaFinding.fromJson(sampleFinding().toJson()..remove('id')),
        throwsA(isA<InvalidQaFinding>()),
      );
      expect(
        () => QaFinding.fromJson(sampleFinding().toJson()..['history'] = 'nope'),
        throwsA(isA<InvalidQaFinding>()),
      );
      expect(
        () => QaFinding.fromJson(sampleFinding().toJson()..['region'] = 'nope'),
        throwsA(isA<InvalidQaFinding>()),
      );
    });

    test('a promoted payload must carry its feedback id', () {
      final promoted = sampleFinding()
          .triage(actorId: reviewerId, at: at(1))
          .promote(actorId: reviewerId, at: at(2), feedbackId: 'feedback-1');
      final json = promoted.toJson()..['feedback_id'] = null;
      expect(() => QaFinding.fromJson(json), throwsA(isA<InvalidQaFinding>()));
    });

    test('history must start with the detected event', () {
      final json = sampleFinding().toJson();
      json['history'] = [
        {
          'event': 'triaged',
          'actor_id': reviewerId,
          'at': at(1).toIso8601String(),
        },
      ];
      expect(() => QaFinding.fromJson(json), throwsA(isA<InvalidQaFinding>()));
    });

    test('unknown payload keys are rejected', () {
      final json = sampleFinding().toJson()..['notes'] = 'free-form';
      expect(() => QaFinding.fromJson(json), throwsA(isA<InvalidQaFinding>()));
    });

    test('the canonical key set matches the emitted payload', () {
      expect(sampleFinding().toJson().keys.toSet(), QaFinding.canonicalKeys);
    });
  });
}
