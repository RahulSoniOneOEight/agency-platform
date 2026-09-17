import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Architecture guards for the automated QA subsystem (`lib/qa`).
///
/// These pin the D.2 authority boundaries so a later change cannot quietly move
/// QA authority into the review subsystem or let QA mutate review/runtime state:
/// - only `lib/qa/persistence/` may perform file I/O;
/// - the QA domain never references runtime bundles, `approved-experience`, or
///   refinement-notes artifacts;
/// - QA never mutates review state except through the validated
///   `ReviewCoordinator.createFeedback` promotion seam;
/// - no QA file approves, resolves, or reclassifies feedback.
List<File> _qaSourceFiles() {
  final directory = Directory('lib/qa');
  expect(
    directory.existsSync(),
    isTrue,
    reason: 'Expected to run from apps/prototype_app (lib/qa not found).',
  );
  final files = directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();
  expect(files, isNotEmpty, reason: 'Expected the QA subsystem to have sources.');
  return files;
}

bool _isPersistenceFile(File file) =>
    file.path.replaceAll('\\', '/').contains('/persistence/');

List<File> _domainFiles() =>
    _qaSourceFiles().where((file) => !_isPersistenceFile(file)).toList();

void main() {
  group('QA persistence boundary (RD3)', () {
    test('only persistence/ performs file I/O', () {
      for (final file in _domainFiles()) {
        final source = file.readAsStringSync();
        expect(source.contains('dart:io'), isFalse,
            reason: '${file.path} performs file I/O');
        expect(source.contains('File('), isFalse,
            reason: '${file.path} opens files');
        expect(source.contains('writeAsString'), isFalse,
            reason: '${file.path} writes files');
        expect(source.contains('writeAsBytes'), isFalse,
            reason: '${file.path} writes files');
      }
    });

    test('persistence adapters exist and never write runtime artifacts', () {
      final persistenceFiles =
          _qaSourceFiles().where(_isPersistenceFile).toList();
      expect(persistenceFiles, isNotEmpty,
          reason: 'Expected the file-backed QA persistence layer.');
      for (final file in persistenceFiles) {
        final lower = file.readAsStringSync().toLowerCase();
        expect(lower.contains('assets/generated'), isFalse,
            reason: '${file.path} writes a runtime bundle');
        expect(lower.contains('runtime_bundle'), isFalse,
            reason: '${file.path} writes a runtime bundle');
      }
    });
  });

  group('QA authority boundaries', () {
    test('no QA domain file references approved-experience or runtime artifacts',
        () {
      for (final file in _domainFiles()) {
        final lower = file.readAsStringSync().toLowerCase();
        // `approved_experience` (underscore) is the legitimate authority-layer
        // name; the hyphenated artifact path must never appear.
        expect(lower.contains('approved-experience'), isFalse,
            reason: '${file.path} references the approved-experience artifact');
        expect(lower.contains('refinement-notes'), isFalse,
            reason: '${file.path} references refinement-notes');
        expect(lower.contains('refinement_notes'), isFalse,
            reason: '${file.path} references refinement_notes');
      }
    });

    test('QA never resolves, reopens, or reclassifies feedback', () {
      for (final file in _qaSourceFiles()) {
        final source = file.readAsStringSync();
        for (final forbidden in const [
          'resolveFeedback',
          'reopenFeedback',
          'setBlocking',
          'closeCurrentRound',
          'startNextRound',
          'createApproval',
          'createDraftBatch',
          'completeBatch',
        ]) {
          expect(source.contains(forbidden), isFalse,
              reason: '${file.path} calls $forbidden');
        }
      }
    });

    test('the QA provider seam never references feedback or review state', () {
      final source = File('lib/qa/visual_qa_provider.dart').readAsStringSync();
      for (final forbidden in const [
        'FeedbackRecord',
        'feedback_record',
        'ReviewState',
        'review_state',
        'ReviewCoordinator',
        'review_coordinator',
      ]) {
        expect(source.contains(forbidden), isFalse,
            reason: 'visual_qa_provider.dart references $forbidden');
      }
    });

    test('promotion is the only review dependency in the QA coordinator', () {
      final source = File('lib/qa/qa_coordinator.dart').readAsStringSync();
      // The coordinator may delegate feedback creation and read feedback, but
      // must not own any feedback lifecycle transition.
      expect(source.contains('createFeedback'), isTrue);
      expect(source.contains('resolveFeedback'), isFalse);
      expect(source.contains('setBlocking'), isFalse);
    });

    test('ReviewState carries no parallel QA state model', () {
      final source = File('lib/review/review_state.dart').readAsStringSync();
      for (final forbidden in const [
        'QaFinding',
        'qa_finding',
        'qaFindings',
        'qa_finding_ids',
      ]) {
        expect(source.contains(forbidden), isFalse,
            reason: 'review_state.dart references $forbidden');
      }
    });
  });
}
