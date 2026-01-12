# Continuum

An event sourcing library for Dart with code generation support.

## Overview

Continuum provides a comprehensive event sourcing framework for Dart applications. It includes:

- **continuum**: Core library with annotations, types, and persistence abstractions
- **continuum_generator**: Code generator for aggregate and event boilerplate
- **continuum_store_memory**: In-memory EventStore for testing
- **continuum_store_hive**: Hive-backed EventStore for local persistence

## Quick Start

### 1. Add dependencies

```yaml
dependencies:
  continuum: latest
  continuum_store_memory: latest  # or continuum_store_hive

dev_dependencies:
  build_runner: ^2.4.0
  continuum_generator: latest
```

### 2. Define your aggregate and events

```dart
import 'package:continuum/continuum.dart';
import 'package:zooper_flutter_core/zooper_flutter_core.dart';

part 'shopping_cart.g.dart';

// Define the aggregate
@Aggregate()
class ShoppingCart with _$ShoppingCartEventHandlers {
  String id;
  List<String> items;

  ShoppingCart._({required this.id, required this.items});

  // Creation factory for CartCreated events
  static ShoppingCart createFromCartCreated(CartCreated event) {
    return ShoppingCart._(id: event.cartId, items: []);
  }

  // Apply method for mutation events
  @override
  void applyItemAdded(ItemAdded event) {
    items.add(event.productId);
  }
}

// Creation event (first event in stream)
@AggregateEvent(of: ShoppingCart, type: 'cart.created')
class CartCreated implements ContinuumEvent {
  final String cartId;

  CartCreated({
    required this.cartId,
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  factory CartCreated.fromJson(Map<String, dynamic> json) {
    return CartCreated(
      eventId: EventId(json['eventId'] as String),
      cartId: json['cartId'] as String,
    );
  }
}

// Mutation event
@AggregateEvent(of: ShoppingCart, type: 'item.added')
class ItemAdded implements ContinuumEvent {
  final String productId;

  ItemAdded({
    required this.productId,
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  factory ItemAdded.fromJson(Map<String, dynamic> json) {
    return ItemAdded(
      eventId: EventId(json['eventId'] as String),
      productId: json['productId'] as String,
    );
  }
}
```

### 3. Run the generator

```bash
dart run build_runner build
```

### 4. Use the event sourcing store

```dart
import 'package:continuum/continuum.dart';
import 'package:continuum_store_memory/continuum_store_memory.dart';
import 'continuum.g.dart'; // Generated

// Create the store
final store = EventSourcingStore(
  eventStore: InMemoryEventStore(),
  aggregates: $aggregateList,
);

// Open a session
final session = store.openSession();

// Start a new stream
final cart = session.startStream<ShoppingCart>(
  StreamId('cart-123'),
  CartCreated(eventId: EventId('evt-1'), cartId: 'cart-123'),
);

// Append mutation events
session.append(
  StreamId('cart-123'),
  ItemAdded(eventId: EventId('evt-2'), productId: 'product-abc'),
);

// Persist changes
await session.saveChangesAsync();
```

## Packages

### continuum

Core library providing:
- `@Aggregate()` and `@AggregateEvent()` annotations
- `ContinuumEvent` base contract
- `EventId` and `StreamId` strong types
- `ContinuumSession`, `EventStore`, `EventSourcingStore` abstractions
- Exception types for error handling

### continuum_generator

Code generator that produces:
- `_$<Aggregate>EventHandlers` mixin for mutation events
- `applyEvent()` dispatcher and `replayEvents()` helper
- `createFromEvent()` factory dispatcher
- Aggregate factory and applier registries

### continuum_store_memory

In-memory `EventStore` implementation suitable for testing and development.

### continuum_store_hive

Hive-backed `EventStore` implementation for local persistence.

## License

MIT
