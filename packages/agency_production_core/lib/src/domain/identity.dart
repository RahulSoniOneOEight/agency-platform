import 'models.dart';

enum UserRole { consumer, b2bBuyer, b2bManager, admin }

final class AppIdentity {
  AppIdentity({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    List<AccountMembership> memberships = const [],
  }) : memberships = List.unmodifiable(memberships) {
    _requireNonEmpty(id, 'id');
  }

  final String id;
  final String email;
  final String displayName;
  final UserRole role;
  final List<AccountMembership> memberships;
}

void _requireNonEmpty(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}
