import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/qa/memory_qa_run_repository.dart';
import 'package:prototype_app/qa/persistence/file_qa_run_repository.dart';
import 'package:prototype_app/qa/persistence/qa_persistence_layout.dart';
import 'package:prototype_app/qa/qa_run.dart';

QaCaptureJob job({
  String captureId = 'sha256:capture-1',
  String? screen = 'commerce.home',
  String? story,
  String state = 'default',
  String? direction = 'b',
  int width = 390,
  int height = 844,
}) {
  return QaCaptureJob(
    captureId: captureId,
    clientId: 'prototype-demo',
    surface: screen == null ? QaSurfaceRef.widgetbook : QaSurfaceRef.prototype,
    screen: screen,
    story: story,
    state: state,
    direction: direction,
    viewportWidth: width,
    viewportHeight: height,
    fixtureVersion: 'demo-v1',
  );
}

QaRun run({bool passed = true, String id = 'run-1'}) {
  return QaRun(
    id: id,
    clientId: 'prototype-demo',
    sourceCommitSha: 'abc123',
    actorId: 'qa-runner',
    startedAt: DateTime.utc(2026, 9, 17, 12),
    completedAt: DateTime.utc(2026, 9, 17, 12, 1),
    captureIds: const ['sha256:capture-1'],
    baselineIds: const ['baseline:aaa'],
    checks: [
      QaCheckResult(
        name: 'golden:commerce.home',
        kind: QaCheckKind.golden,
        passed: passed,
        detail: passed ? 'matches baseline' : 'differs from baseline',
      ),
      QaCheckResult(
        name: 'visual-ai:commerce.home',
        kind: QaCheckKind.visualAi,
        passed: true,
        detail: 'no new findings',
      ),
    ],
    findingIds: const ['qa-001'],
  );
}

void main() {
  group('QaRun record', () {
    test('derives pass/fail from its checks deterministically', () {
      expect(run().passed, isTrue);
      expect(run(passed: false).passed, isFalse);
    });

    test('round-trips through canonical json', () {
      final original = run();
      expect(QaRun.fromJson(original.toJson()), original);
      expect(original.toJson().keys.toSet(), {
        'id',
        'client_id',
        'source_commit_sha',
        'actor_id',
        'started_at',
        'completed_at',
        'refinement_batch_id',
        'capture_ids',
        'baseline_ids',
        'checks',
        'finding_ids',
      });
    });

    test('rejects malformed payloads', () {
      expect(
        () => QaRun.fromJson(run().toJson()..['checks'] = 'nope'),
        throwsFormatException,
      );
      expect(
        () => QaRun.fromJson(run().toJson()..remove('source_commit_sha')),
        throwsFormatException,
      );
    });

    test('serializes checks with their kind and result', () {
      final json = run().toJson();
      final checks = json['checks'] as List<dynamic>;
      expect((checks.first as Map)['kind'], 'golden');
      expect((checks.first as Map)['passed'], isTrue);
    });
  });

  group('targeted affected-job selection', () {
    test('selects only jobs on the changed governed screens', () {
      final jobs = [
        job(captureId: 'sha256:a', screen: 'commerce.home'),
        job(captureId: 'sha256:b', screen: 'commerce.plp'),
        job(captureId: 'sha256:c', screen: 'commerce.pdp'),
      ];
      final affected = affectedCaptureJobs(
        jobs: jobs,
        changedScreens: {'commerce.plp'},
      );
      expect(affected.map((item) => item.captureId), ['sha256:b']);
    });

    test('selects widgetbook jobs by story', () {
      final jobs = [
        job(captureId: 'sha256:a', screen: null, story: 'AgencyButton.Primary'),
        job(captureId: 'sha256:b', screen: 'commerce.home'),
      ];
      final affected = affectedCaptureJobs(
        jobs: jobs,
        changedScreens: {'AgencyButton.Primary'},
      );
      expect(affected.map((item) => item.captureId), ['sha256:a']);
    });

    test('never recaptures every permutation when nothing changed', () {
      final jobs = [job(captureId: 'sha256:a'), job(captureId: 'sha256:b')];
      expect(affectedCaptureJobs(jobs: jobs, changedScreens: const {}), isEmpty);
    });

    test('keeps deterministic job order', () {
      final jobs = [
        job(captureId: 'sha256:a', screen: 'commerce.home'),
        job(captureId: 'sha256:b', screen: 'commerce.home'),
      ];
      final affected = affectedCaptureJobs(
        jobs: jobs,
        changedScreens: {'commerce.home'},
      );
      expect(affected.map((item) => item.captureId), ['sha256:a', 'sha256:b']);
    });
  });

  group('run repositories', () {
    test('memory repository round-trips and lists by id', () async {
      final repository = MemoryQaRunRepository();
      await repository.save('prototype-demo', run(id: 'run-2'));
      await repository.save('prototype-demo', run(id: 'run-1'));
      expect((await repository.list('prototype-demo')).map((item) => item.id),
          ['run-1', 'run-2']);
      expect((await repository.load('prototype-demo', 'run-1'))!.id, 'run-1');
      expect(await repository.load('prototype-demo', 'missing'), isNull);
    });

    test('file repository writes under prototype/qa/runs', () async {
      final tempRoot = await Directory.systemTemp.createTemp('qa-runs-');
      addTearDown(() => tempRoot.delete(recursive: true));
      final layout = QaPersistenceLayout(clientProjectsDirectory: tempRoot);
      final repository = FileQaRunRepository(layout: layout);

      await repository.save('prototype-demo', run());
      final file = layout.runFile('prototype-demo', 'run-1');
      expect(file.existsSync(), isTrue);
      final raw = file.readAsStringSync();
      expect(raw.endsWith('\n'), isTrue);
      expect(json.decode(raw), run().toJson());
      expect((await repository.list('prototype-demo')), hasLength(1));
    });
  });
}
