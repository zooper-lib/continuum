// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account.dart';

// **************************************************************************
// ContinuumGenerator
// **************************************************************************

/// Generated mixin requiring apply methods for Account mutation events.
///
/// Implement this mixin and provide the required apply methods.
mixin _$AccountEventHandlers {
  /// Applies a FundsDeposited event to this aggregate.
  void applyFundsDeposited(FundsDeposited event);

  /// Applies a FundsWithdrawn event to this aggregate.
  void applyFundsWithdrawn(FundsWithdrawn event);
}

/// Generated extension providing event dispatch for Account.
extension $AccountEventDispatch on Account {
  /// Applies a continuum event to this aggregate.
  ///
  /// Routes supported mutation events to the corresponding apply method.
  /// Throws [UnsupportedEventException] for unknown event types.
  void applyEvent(ContinuumEvent event) {
    switch (event) {
      case FundsDeposited():
        applyFundsDeposited(event);
      case FundsWithdrawn():
        applyFundsWithdrawn(event);
      default:
        throw UnsupportedEventException(
          eventType: event.runtimeType,
          aggregateType: Account,
        );
    }
  }

  /// Replays multiple events in order.
  ///
  /// Applies each event sequentially via [applyEvent].
  void replayEvents(Iterable<ContinuumEvent> events) {
    for (final event in events) {
      applyEvent(event);
    }
  }
}

/// Generated extension providing creation dispatch for Account.
extension $AccountCreation on Never {
  /// Creates a Account from a creation event.
  ///
  /// Routes to the appropriate static create method.
  /// Throws [InvalidCreationEventException] for unknown event types.
  static Account createFromEvent(ContinuumEvent event) {
    switch (event) {
      case AccountOpened():
        return Account.createFromAccountOpened(event);
      default:
        throw InvalidCreationEventException(
          eventType: event.runtimeType,
          aggregateType: Account,
        );
    }
  }
}

/// Generated aggregate bundle for Account.
///
/// Contains all serializers, factories, and appliers for this aggregate.
/// Add to the `aggregates` list when creating an [EventSourcingStore].
final $Account = GeneratedAggregate(
  serializerRegistry: EventSerializerRegistry({
    AccountOpened: EventSerializerEntry(
      eventType: 'account.opened',
      toJson: (event) => (event as AccountOpened).toJson(),
      fromJson: AccountOpened.fromJson,
    ),
    FundsDeposited: EventSerializerEntry(
      eventType: 'account.funds_deposited',
      toJson: (event) => (event as FundsDeposited).toJson(),
      fromJson: FundsDeposited.fromJson,
    ),
    FundsWithdrawn: EventSerializerEntry(
      eventType: 'account.funds_withdrawn',
      toJson: (event) => (event as FundsWithdrawn).toJson(),
      fromJson: FundsWithdrawn.fromJson,
    ),
  }),
  aggregateFactories: AggregateFactoryRegistry({
    Account: {
      AccountOpened: (event) => Account.createFromAccountOpened(event as AccountOpened),
    },
  }),
  eventAppliers: EventApplierRegistry({
    Account: {
      FundsDeposited: (aggregate, event) => (aggregate as Account).applyFundsDeposited(event as FundsDeposited),
      FundsWithdrawn: (aggregate, event) => (aggregate as Account).applyFundsWithdrawn(event as FundsWithdrawn),
    },
  }),
);
