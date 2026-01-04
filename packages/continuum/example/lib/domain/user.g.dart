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

/// Generated serializer registry for automatic event serialization.
///
/// Maps Dart types to their toJson/fromJson factories and type discriminators.
/// Pass this to [JsonEventSerializer] for zero-configuration serialization.
final $generatedSerializerRegistry = EventSerializerRegistry({
  UserRegistered: EventSerializerEntry(
    eventType: 'user.registered',
    toJson: (event) => (event as UserRegistered).toJson(),
    fromJson: UserRegistered.fromJson,
  ),
  EmailChanged: EventSerializerEntry(
    eventType: 'user.email_changed',
    toJson: (event) => (event as EmailChanged).toJson(),
    fromJson: EmailChanged.fromJson,
  ),
  UserDeactivated: EventSerializerEntry(
    eventType: 'user.deactivated',
    toJson: (event) => (event as UserDeactivated).toJson(),
    fromJson: UserDeactivated.fromJson,
  ),
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
