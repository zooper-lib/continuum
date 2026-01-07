import 'package:continuum/continuum.dart';

import 'events/email_changed.dart';
import 'events/user_deactivated.dart';
import 'events/user_registered.dart';

export 'events/email_changed.dart';
export 'events/user_deactivated.dart';
export 'events/user_registered.dart';

part 'user.g.dart';

/// A User aggregate demonstrating event sourcing with in-memory persistence.
@Aggregate()
class User with _$UserEventHandlers {
  final String id;
  String email;
  String name;
  bool isActive;
  DateTime? deactivatedAt;

  User._({required this.id, required this.email, required this.name, required this.isActive, required this.deactivatedAt});

  static User createFromUserRegistered(UserRegistered event) {
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
}
