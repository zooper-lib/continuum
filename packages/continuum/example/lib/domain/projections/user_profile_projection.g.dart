// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_profile_projection.dart';

// **************************************************************************
// ContinuumGenerator
// **************************************************************************

/// Generated mixin providing event handling for UserProfileProjection.
///
/// This mixin provides the [handledEventTypes], [projectionName], and [apply]
/// implementations. Implement the abstract `apply<EventName>` methods.
mixin _$UserProfileProjectionHandlers {
  /// The set of event types this projection handles.
  Set<Type> get handledEventTypes => const {
    UserRegistered,
    EmailChanged,
    UserDeactivated,
  };

  /// The unique name identifying this projection.
  String get projectionName => 'user-profile';

  /// Applies an operation to update the read model.
  ///
  /// Routes the operation to the appropriate typed handler method.
  /// Throws [UnsupportedProjectionOperationException] for unknown operation types.
  UserProfile apply(UserProfile current, Operation operation) {
    return switch (operation) {
      UserRegistered() => applyUserRegistered(current, operation),
      EmailChanged() => applyEmailChanged(current, operation),
      UserDeactivated() => applyUserDeactivated(current, operation),
      _ => throw UnsupportedProjectionOperationException(
        operationType: operation.runtimeType,
        projectionType: UserProfileProjection,
      ),
    };
  }

  /// Applies a UserRegistered event to the read model.
  UserProfile applyUserRegistered(UserProfile current, UserRegistered event);

  /// Applies a EmailChanged event to the read model.
  UserProfile applyEmailChanged(UserProfile current, EmailChanged event);

  /// Applies a UserDeactivated event to the read model.
  UserProfile applyUserDeactivated(UserProfile current, UserDeactivated event);
}

/// Generated extension providing additional event dispatch for UserProfileProjection.
extension $UserProfileProjectionEventDispatch on UserProfileProjection {
  /// Routes an operation to the appropriate apply method.
  ///
  /// This is a convenience method for applying operations directly.
  ///
  /// Throws [UnsupportedProjectionOperationException] for unknown operation types.
  UserProfile applyEvent(UserProfile current, Operation operation) {
    return switch (operation) {
      UserRegistered() => applyUserRegistered(current, operation),
      EmailChanged() => applyEmailChanged(current, operation),
      UserDeactivated() => applyUserDeactivated(current, operation),
      _ => throw UnsupportedProjectionOperationException(
        operationType: operation.runtimeType,
        projectionType: UserProfileProjection,
      ),
    };
  }
}

/// Generated projection bundle for UserProfileProjection.
///
/// Contains metadata for registry configuration.
/// Add to the `projections` list when creating a [ProjectionRegistry].
final $UserProfileProjection = GeneratedProjection(
  projectionName: 'user-profile',
  schemaHash: 'd916e035',
  handledEventTypes: {UserRegistered, EmailChanged, UserDeactivated},
);
