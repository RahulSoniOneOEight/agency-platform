import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/qa/memory_qa_finding_repository.dart';
import 'package:prototype_app/qa/persistence/file_qa_finding_repository.dart';
import 'package:prototype_app/qa/persistence/qa_persistence_layout.dart';
import 'package:prototype_app/qa/qa_domain_error.dart';
import 'package:prototype_app/qa/qa_finding.dart';
import 'package:prototype_app/qa/qa_finding_repository.dart';

import 'support/qa_fixtures.dart';

const clientId = 'prototype-demo';

void main() {
  group('memory repository', () {
    late MemoryQaFindingRepository repository;

    setUp(() {
      repository = MemoryQaFindingRepository();
    });

    test('create, load, and list round-trip', () async {
      final finding = sampleQaFinding();
      await repository.create(clientId, finding);

      expect(await repository.load(clientId, 'qa-001'), finding);
      expect(await repository.list(clientId), [finding]);
      expect(await repository.load(clientId, 'missing'), isNull);
      expect(await repository.list('other-client'), isEmpty);
    });

    test('list is ordered by finding id', () async {
      await repository.create(clientId, sampleQaFinding(id: 'qa-003'));
      await repository.create(clientId, sampleQaFinding(id: 'qa-001'));
      await repository.create(clientId, sampleQaFinding(id: 'qa-002'));

      expect(
        (await repository.list(clientId)).map((finding) => finding.id),
        ['qa-001', 'qa-002', 'qa-003'],
      );
    });

    test('duplicate creation is rejected', () async {
      await repository.create(clientId, sampleQaFinding());
      await expectLater(
        repository.create(clientId, sampleQaFinding()),
        throwsA(isA<DuplicateQaFindingId>()),
      );
    });

    test('replace uses expected-current semantics', () async {
      final current = sampleQaFinding();
      await repository.create(clientId, current);
      final next = current.triage(
        actorId: 'reviewer-1',
        at: DateTime.utc(2026, 9, 17, 11),
      );

      await repository.replace(clientId, current, next);
      expect((await repository.load(clientId, 'qa-001'))!.status,
          QaFindingStatus.triaged);

      await expectLater(
        repository.replace(clientId, current, next),
        throwsA(isA<QaFindingChangedSinceRead>()),
      );
    });

    test('replace of an unknown finding is rejected', () async {
      final current = sampleQaFinding();
      final next = current.triage(
        actorId: 'reviewer-1',
        at: DateTime.utc(2026, 9, 17, 11),
      );
      await expectLater(
        repository.replace(clientId, current, next),
        throwsA(isA<QaFindingNotFound>()),
      );
    });

    test('replace with a mismatched id is rejected', () async {
      final current = sampleQaFinding();
      await repository.create(clientId, current);
      final other = sampleQaFinding(id: 'qa-002').triage(
        actorId: 'reviewer-1',
        at: DateTime.utc(2026, 9, 17, 11),
      );
      await expectLater(
        repository.replace(clientId, current, other),
        throwsA(isA<QaFindingChangedSinceRead>()),
      );
    });
  });

  group('persistence layout', () {
    test('locates findings under prototype/qa/findings', () {
      final layout = QaPersistenceLayout(
        clientProjectsDirectory: Directory('/tmp/client-projects'),
      );
      expect(
        layout
            .findingFile('prototype-demo', 'qa-001')
            .path
            .replaceAll('\\', '/'),
        '/tmp/client-projects/prototype-demo/prototype/qa/findings/qa-001.json',
      );
      expect(
        layout.findingsDirectory('prototype-demo').path.replaceAll('\\', '/'),
        '/tmp/client-projects/prototype-demo/prototype/qa/findings',
      );
    });
  });

  group('file repository', () {
    late Directory tempRoot;
    late QaPersistenceLayout layout;
    late FileQaFindingRepository repository;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('qa-findings-');
      layout = QaPersistenceLayout(clientProjectsDirectory: tempRoot);
      repository = FileQaFindingRepository(layout: layout);
    });

    tearDown(() async {
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('create writes a governed findings artifact', () async {
      final finding = sampleQaFinding();
      await repository.create(clientId, finding);

      final file = layout.findingFile(clientId, 'qa-001');
      expect(file.existsSync(), isTrue);
      final raw = file.readAsStringSync();
      expect(raw.endsWith('\n'), isTrue);
      expect(
        json.decode(raw),
        finding.toJson(),
      );
    });

    test('load and list round-trip through disk', () async {
      final first = sampleQaFinding(id: 'qa-001');
      final second = sampleQaFinding(id: 'qa-002', category: 'clipping');
      await repository.create(clientId, first);
      await repository.create(clientId, second);

      expect(await repository.load(clientId, 'qa-001'), first);
      expect((await repository.list(clientId)).map((f) => f.id), ['qa-001', 'qa-002']);
      expect(await repository.load(clientId, 'missing'), isNull);
    });

    test('duplicate creation is rejected', () async {
      await repository.create(clientId, sampleQaFinding());
      await expectLater(
        repository.create(clientId, sampleQaFinding()),
        throwsA(isA<DuplicateQaFindingId>()),
      );
    });

    test('replace enforces expected-current semantics', () async {
      final current = sampleQaFinding();
      await repository.create(clientId, current);
      final next = current.triage(
        actorId: 'reviewer-1',
        at: DateTime.utc(2026, 9, 17, 11),
      );
      await repository.replace(clientId, current, next);
      expect((await repository.load(clientId, 'qa-001'))!.status,
          QaFindingStatus.triaged);
      await expectLater(
        repository.replace(clientId, current, next),
        throwsA(isA<QaFindingChangedSinceRead>()),
      );
    });

    test('a malformed artifact fails with a typed QA error', () async {
      final file = layout.findingFile(clientId, 'qa-001');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('{not json');
      await expectLater(
        repository.load(clientId, 'qa-001'),
        throwsA(isA<InvalidQaFinding>()),
      );
    });

    test('list ignores unrelated files', () async {
      await repository.create(clientId, sampleQaFinding());
      final dir = layout.findingsDirectory(clientId);
      File('${dir.path}/README.md').writeAsStringSync('notes');
      expect((await repository.list(clientId)).map((f) => f.id), ['qa-001']);
    });

    test('the repository interface is implemented by both adapters', () {
      expect(repository, isA<QaFindingRepository>());
      expect(MemoryQaFindingRepository(), isA<QaFindingRepository>());
    });
  });
}
