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

  /// Applies an event to update the read model.
  ///
  /// Routes the event to the appropriate typed handler method.
  /// Throws [UnsupportedEventException] for unknown event types.
  UserProfile apply(UserProfile current, StoredEvent event) {
    final domainEvent = event.domainEvent;
    if (domainEvent == null) {
      throw StateError(
        'StoredEvent.domainEvent is null. '
        'Projections require deserialized domain events.',
      );
    }
    return switch (domainEvent) {
      UserRegistered() => applyUserRegistered(current, domainEvent),
      EmailChanged() => applyEmailChanged(current, domainEvent),
      UserDeactivated() => applyUserDeactivated(current, domainEvent),
      _ => throw UnsupportedEventException(
        eventType: domainEvent.runtimeType,
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
  /// Routes a domain event to the appropriate apply method.
  ///
  /// This is a convenience method for applying events directly without
  /// wrapping in [StoredEvent]. For normal projection processing, use [apply].
  ///
  /// Throws [UnsupportedEventException] for unknown event types.
  UserProfile applyEvent(UserProfile current, ContinuumEvent event) {
    return switch (event) {
      UserRegistered() => applyUserRegistered(current, event),
      EmailChanged() => applyEmailChanged(current, event),
      UserDeactivated() => applyUserDeactivated(current, event),
      _ => throw UnsupportedEventException(
        eventType: event.runtimeType,
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
