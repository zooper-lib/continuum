// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'continuum_example.dart';

// **************************************************************************
// ContinuumGenerator
// **************************************************************************

/// Generated mixin requiring apply methods for ShoppingCart mutation events.
///
/// Implement this mixin and provide the required apply methods.
mixin _$ShoppingCartEventHandlers {
  /// Applies a ItemAdded event to this aggregate.
  void applyItemAdded(ItemAdded event);

  /// Applies a ItemRemoved event to this aggregate.
  void applyItemRemoved(ItemRemoved event);
}

/// Generated extension providing event dispatch for ShoppingCart.
extension $ShoppingCartEventDispatch on ShoppingCart {
  /// Applies a domain event to this aggregate.
  ///
  /// Routes supported mutation events to the corresponding apply method.
  /// Throws [UnsupportedEventException] for unknown event types.
  void applyEvent(DomainEvent event) {
    switch (event) {
      case ItemAdded():
        applyItemAdded(event);
      case ItemRemoved():
        applyItemRemoved(event);
      default:
        throw UnsupportedEventException(
          eventType: event.runtimeType,
          aggregateType: ShoppingCart,
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

/// Generated extension providing creation dispatch for ShoppingCart.
extension $ShoppingCartCreation on Never {
  /// Creates a ShoppingCart from a creation event.
  ///
  /// Routes to the appropriate static create method.
  /// Throws [InvalidCreationEventException] for unknown event types.
  static ShoppingCart createFromEvent(DomainEvent event) {
    switch (event) {
      case CartCreated():
        return ShoppingCart.createCartCreated(event);
      default:
        throw InvalidCreationEventException(
          eventType: event.runtimeType,
          aggregateType: ShoppingCart,
        );
    }
  }
}

/// Generated event registry for persistence deserialization.
///
/// Maps event type discriminators to fromJson factories.
final $generatedEventRegistry = EventRegistry({
  'cart.created': CartCreated.fromJson,
  'item.added': ItemAdded.fromJson,
  'item.removed': ItemRemoved.fromJson,
});

/// Generated aggregate factory registry for Session creation dispatch.
final $generatedAggregateFactories = AggregateFactoryRegistry({
  ShoppingCart: {
    CartCreated: (event) =>
        ShoppingCart.createCartCreated(event as CartCreated),
  },
});

/// Generated event applier registry for Session mutation dispatch.
final $generatedEventAppliers = EventApplierRegistry({
  ShoppingCart: {
    ItemAdded: (aggregate, event) =>
        (aggregate as ShoppingCart).applyItemAdded(event as ItemAdded),
    ItemRemoved: (aggregate, event) =>
        (aggregate as ShoppingCart).applyItemRemoved(event as ItemRemoved),
  },
});
