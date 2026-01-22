import 'package:continuum/continuum.dart';

import '../events/email_changed.dart';
import '../events/user_deactivated.dart';
import '../events/user_registered.dart';

part 'user_profile_projection.g.dart';

/// Read model for a user's profile information.
///
/// This is a denormalized view optimized for querying user profile data
/// without reconstructing the full aggregate.
class UserProfile {
  final String name;
  final String email;
  final bool isActive;
  final DateTime lastUpdated;

  const UserProfile({
    required this.name,
    required this.email,
    required this.isActive,
    required this.lastUpdated,
  });

  UserProfile copyWith({
    String? name,
    String? email,
    bool? isActive,
    DateTime? lastUpdated,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      isActive: isActive ?? this.isActive,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  @override
  String toString() => 'UserProfile(name: $name, email: $email, isActive: $isActive, lastUpdated: $lastUpdated)';
}

/// Projection that maintains UserProfile read models.
///
/// Uses the `@Projection` annotation and generated mixin for type-safe
/// event handling. The generator creates:
/// - `_$UserProfileProjectionHandlers` mixin with abstract apply methods
/// - `$UserProfileProjectionEventDispatch` extension with `applyEvent()`
/// - `$UserProfileProjection` bundle constant for registration
@Projection(
  name: 'user-profile',
  events: [UserRegistered, EmailChanged, UserDeactivated],
)
class UserProfileProjection extends SingleStreamProjection<UserProfile> with _$UserProfileProjectionHandlers {
  @override
  UserProfile createInitial(StreamId streamId) => UserProfile(
    name: '',
    email: '',
    isActive: true,
    lastUpdated: DateTime.utc(1970),
  );

  @override
  UserProfile applyUserRegistered(UserProfile current, UserRegistered event) {
    return UserProfile(
      name: event.name,
      email: event.email,
      isActive: true,
      lastUpdated: event.occurredOn,
    );
  }

  @override
  UserProfile applyEmailChanged(UserProfile current, EmailChanged event) {
    return current.copyWith(
      email: event.newEmail,
      lastUpdated: event.occurredOn,
    );
  }

  @override
  UserProfile applyUserDeactivated(UserProfile current, UserDeactivated event) {
    return current.copyWith(
      isActive: false,
      lastUpdated: event.occurredOn,
    );
  }
}
