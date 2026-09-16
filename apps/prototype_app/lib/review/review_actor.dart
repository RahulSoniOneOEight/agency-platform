/// The review authority a participant holds.
///
/// Reviewer and approver are distinct roles even when the same person performs
/// both; an agent is the OpenCode implementation actor. Cross-domain operations
/// in `ReviewCoordinator` enforce these roles.
enum ReviewRole { reviewer, approver, agent }

/// A named review participant acting on feedback or review rounds.
final class ReviewActor {
  const ReviewActor({
    required this.id,
    required this.name,
    required this.role,
  });

  final String id;
  final String name;
  final ReviewRole role;

  bool get isReviewer => role == ReviewRole.reviewer;

  bool get isAgent => role == ReviewRole.agent;

  bool get isApprover => role == ReviewRole.approver;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReviewActor &&
        other.id == id &&
        other.name == name &&
        other.role == role;
  }

  @override
  int get hashCode => Object.hash(id, name, role);

  @override
  String toString() => 'ReviewActor(id: $id, role: $role)';
}
