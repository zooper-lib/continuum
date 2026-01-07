import 'package:continuum/continuum.dart';

import 'events/email_changed.dart';
import 'events/user_deactivated.dart';
import 'events/user_registered.dart';

part 'user.g.dart';

/// A User aggregate demonstrating event sourcing.
///
/// Users are created via registration, can update their email,
/// and can be deactivated. Each state change is an event.
@Aggregate()
class User with _$UserEventHandlers {
  final String id;
  String email;
  String name;
  bool isActive;
  DateTime? deactivatedAt;

  User._({required this.id, required this.email, required this.name, required this.isActive, required this.deactivatedAt});

  /// Creates a user from the registration event.
  static User createUserRegistered(UserRegistered event) {
    return User._(id: event.userId, email: event.email, name: event.name, isActive: true, deactivatedAt: null);
  }

  @override
  void applyEmailChanged(EmailChanged event) {
    email = event.newEmail;
  }

  @override
  void applyUserDeactivated(UserDeactivated event) {
    isActive = false;
    deactivatedAt = event.deactivatedAt;
  }

  @override
  String toString() {
    return 'User(id: $id, name: $name, email: $email, isActive: $isActive, deactivatedAt: $deactivatedAt)';
  }
}
