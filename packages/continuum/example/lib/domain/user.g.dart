// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// ContinuumGenerator
// **************************************************************************

/// Generated mixin requiring apply methods for User mutation events.
///
/// Implement this mixin and provide the required apply methods.
mixin _$UserEventHandlers {
  /// Applies a EmailChanged event to this aggregate.
  void applyEmailChanged(EmailChanged event);

  /// Applies a UserDeactivated event to this aggregate.
  void applyUserDeactivated(UserDeactivated event);
}

/// Generated extension providing event dispatch for User.
extension $UserEventDispatch on User {
  /// Applies a domain event to this aggregate.
  ///
  /// Routes supported mutation events to the corresponding apply method.
  /// Throws [UnsupportedEventException] for unknown event types.
  void applyEvent(DomainEvent event) {
    switch (event) {
      case EmailChanged():
        applyEmailChanged(event);
      case UserDeactivated():
        applyUserDeactivated(event);
      default:
        throw UnsupportedEventException(
          eventType: event.runtimeType,
          aggregateType: User,
        );
    }
  }

  /// Replays multiple events in order.
  ///
  /// Applies each event sequentially via [applyEvent].
  void replayEvents(Iterable<DomainEvent> events) {
    for (final event in events) {
      applyEvent(event);
    }
  }
}

/// Generated extension providing creation dispatch for User.
extension $UserCreation on Never {
  /// Creates a User from a creation event.
  ///
  /// Routes to the appropriate static create method.
  /// Throws [InvalidCreationEventException] for unknown event types.
  static User createFromEvent(DomainEvent event) {
    switch (event) {
      case UserRegistered():
        return User.createUserRegistered(event);
      default:
        throw InvalidCreationEventException(
          eventType: event.runtimeType,
          aggregateType: User,
        );
    }
  }
}

/// Generated event registry for persistence deserialization.
///
/// Maps event type discriminators to fromJson factories.
final $generatedEventRegistry = EventRegistry({
  'user.registered': UserRegistered.fromJson,
  'user.email_changed': EmailChanged.fromJson,
  'user.deactivated': UserDeactivated.fromJson,
});

/// Generated aggregate factory registry for Session creation dispatch.
final $generatedAggregateFactories = AggregateFactoryRegistry({
  User: {
    UserRegistered: (event) =>
        User.createUserRegistered(event as UserRegistered),
  },
});

/// Generated event applier registry for Session mutation dispatch.
final $generatedEventAppliers = EventApplierRegistry({
  User: {
    EmailChanged: (aggregate, event) =>
        (aggregate as User).applyEmailChanged(event as EmailChanged),
    UserDeactivated: (aggregate, event) =>
        (aggregate as User).applyUserDeactivated(event as UserDeactivated),
  },
});
