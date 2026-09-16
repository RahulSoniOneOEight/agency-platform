import 'dart:convert';

import '../approval_repository.dart';
import '../approval_snapshot.dart';
import '../review_domain_error.dart';
import 'review_persistence_layout.dart';

/// File-backed, append-only [ApprovalRepository].
///
/// Each snapshot is an immutable `approvals/approval-v<version>.json` artifact.
/// [create] is create-only: an existing version (or a non-monotonic version) is
/// rejected with [ApprovalVersionConflict] and the stored file is never
/// rewritten. Supersession is derived from `supersedes`/version order and is
/// never represented by mutating a prior snapshot.
final class FileApprovalRepository implements ApprovalRepository {
  FileApprovalRepository({required this.layout});

  final ReviewPersistenceLayout layout;

  @override
  Future<List<ApprovalSnapshot>> list(String clientId) async {
    final files = await listRecordFiles(
      layout.approvalsDirectory(clientId),
      'approval-v',
      '.json',
    );
    final snapshots = <ApprovalSnapshot>[];
    for (final file in files) {
      snapshots.add(_decode(await file.readAsString(), file.path));
    }
    snapshots.sort((a, b) => a.version.compareTo(b.version));
    return List<ApprovalSnapshot>.unmodifiable(snapshots);
  }

  @override
  Future<void> create(String clientId, ApprovalSnapshot snapshot) async {
    if (snapshot.clientId != clientId) {
      throw ApprovalVersionConflict(
        'approval ${snapshot.version} belongs to client ${snapshot.clientId}, '
        'not $clientId',
      );
    }
    final file = layout.approvalFile(clientId, snapshot.version);
    if (file.existsSync()) {
      throw ApprovalVersionConflict(
        'approval version ${snapshot.version} already exists for $clientId',
      );
    }
    final existing = await list(clientId);
    if (existing.any((other) => other.version >= snapshot.version)) {
      throw ApprovalVersionConflict(
        'approval version ${snapshot.version} is not monotonic for $clientId',
      );
    }
    await writeFileAtomic(file, _encode(snapshot));
  }

  ApprovalSnapshot _decode(String raw, String path) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded.keys.any((key) => key is! String)) {
      throw FormatException('Invalid approval snapshot at $path');
    }
    return ApprovalSnapshot.fromJson(decoded.cast<String, dynamic>());
  }

  String _encode(ApprovalSnapshot snapshot) =>
      '${const JsonEncoder.withIndent('  ').convert(snapshot.toJson())}\n';
}
