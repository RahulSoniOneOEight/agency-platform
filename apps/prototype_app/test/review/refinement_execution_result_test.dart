import 'package:flutter_test/flutter_test.dart';
import 'package:prototype_app/review/refinement_batch.dart';
import 'package:prototype_app/review/refinement_execution_result.dart';

void main() {
  RefinementExecutionResult result() => RefinementExecutionResult(
        status: RefinementExecutionStatus.passed,
        commitSha: 'abc123',
        filesChanged: const ['lib/review/refinement_batch.dart'],
        checks: const [
          ValidationCheck(name: 'flutter test', passed: true, details: 'ok'),
        ],
        evidence: const ['screenshot-1'],
        notes: 'implemented within frozen scope',
      );

  group('wire values', () {
    test('execution statuses round-trip', () {
      for (final value in RefinementExecutionStatus.values) {
        expect(
          refinementExecutionStatusFromWire(
            refinementExecutionStatusToWire(value),
          ),
          value,
        );
      }
      expect(
        refinementExecutionStatusToWire(RefinementExecutionStatus.passed),
        'passed',
      );
      expect(
        () => refinementExecutionStatusFromWire('unknown'),
        throwsFormatException,
      );
    });
  });

  group('result contract', () {
    test('requires a commit SHA', () {
      expect(
        () => RefinementExecutionResult(
          status: RefinementExecutionStatus.passed,
          commitSha: '  ',
        ),
        throwsFormatException,
      );
    });

    test('derives the domain validation and execution records', () {
      final value = result();
      expect(value.passed, isTrue);
      expect(value.batchValidation.status, BatchValidationStatus.passed);
      expect(value.batchValidation.checks, value.checks);
      expect(value.execution(agent: 'opencode', model: 'deepseek-v4-pro').agent,
          'opencode');
      expect(
        value.execution(agent: 'opencode', model: 'deepseek-v4-pro').commitSha,
        'abc123',
      );
    });

    test('round-trips through deterministic JSON', () {
      final original = result();
      final json = original.toJson();
      expect(json.keys.toSet(), {
        'status',
        'commit_sha',
        'files_changed',
        'checks',
        'evidence',
        'notes',
      });
      expect(RefinementExecutionResult.fromJson(json), original);
    });

    test('rejects malformed payloads', () {
      expect(
        () => RefinementExecutionResult.fromJson(
          result().toJson()..['status'] = 'unknown',
        ),
        throwsFormatException,
      );
      expect(
        () => RefinementExecutionResult.fromJson(
          result().toJson()..['checks'] = 'nope',
        ),
        throwsFormatException,
      );
    });
  });
}
