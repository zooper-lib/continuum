import 'package:bounded/bounded.dart';
import 'package:continuum/continuum.dart';

import 'events/email_changed.dart';
import 'events/user_deactivated.dart';
import 'events/user_registered.dart';

export 'events/email_changed.dart';
export 'events/user_deactivated.dart';
export 'events/user_registered.dart';

part 'user.g.dart';

/// A strongly-typed user identifier.
final class UserId extends TypedIdentity<String> {
  /// Creates a user identifier from a stable string value.
  const UserId(super.value);
}

/// A User aggregate demonstrating event sourcing with Hive persistence.
class User extends AggregateRoot<UserId> with _$UserEventHandlers {
  String email;
  String name;
  bool isActive;
  DateTime? deactivatedAt;

  User._({
    required UserId id,
    required this.email,
    required this.name,
    required this.isActive,
    required this.deactivatedAt,
  }) : super(id);

  static User createFromUserRegistered(UserRegistered event) {
    // WHY: Creation events define initial state for replay.
    return User._(
      id: event.userId,
      email: event.email,
      name: event.name,
      isActive: true,
      deactivatedAt: null,
    );
  }

  @override
  void applyEmailChanged(EmailChanged event) {
    // WHY: Mutation events update state during replay and live operations.
    email = event.newEmail;
  }

  @override
  void applyUserDeactivated(UserDeactivated event) {
    // WHY: Deactivation is a state transition derived from events.
    isActive = false;
    deactivatedAt = event.deactivatedAt;
  }
}
