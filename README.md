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
  continuum: ^0.1.0
  continuum_store_memory: ^0.1.0  # or continuum_store_hive

dev_dependencies:
  build_runner: ^2.4.0
  continuum_generator: ^0.1.0
```

### 2. Define your aggregate and events

```dart
import 'package:continuum/continuum.dart';

part 'shopping_cart.g.dart';

// Define the aggregate
@Aggregate()
class ShoppingCart with _$ShoppingCartEventHandlers {
  String id;
  List<String> items;

  ShoppingCart._({required this.id, required this.items});

  // Creation factory for CartCreated events
  static ShoppingCart createCartCreated(CartCreated event) {
    return ShoppingCart._(id: event.cartId, items: []);
  }

  // Apply method for mutation events
  @override
  void applyItemAdded(ItemAdded event) {
    items.add(event.productId);
  }
}

// Creation event (first event in stream)
@Event(ofAggregate: ShoppingCart, type: 'cart.created')
class CartCreated extends DomainEvent {
  final String cartId;

  CartCreated({
    required super.eventId,
    required this.cartId,
    super.occurredOn,
    super.metadata,
  });

  factory CartCreated.fromJson(Map<String, dynamic> json) {
    return CartCreated(
      eventId: EventId(json['eventId'] as String),
      cartId: json['cartId'] as String,
    );
  }
}

// Mutation event
@Event(ofAggregate: ShoppingCart, type: 'item.added')
class ItemAdded extends DomainEvent {
  final String productId;

  ItemAdded({
    required super.eventId,
    required this.productId,
    super.occurredOn,
    super.metadata,
  });

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

// Create the store
final store = EventSourcingStore(
  eventStore: InMemoryEventStore(),
  serializer: mySerializer,
  registry: $generatedEventRegistry,
  aggregateFactories: $generatedAggregateFactories,
  eventAppliers: $generatedEventAppliers,
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
- `@Aggregate()` and `@Event()` annotations
- `DomainEvent` base class
- `EventId` and `StreamId` strong types
- `Session`, `EventStore`, `EventSourcingStore` abstractions
- Exception types for error handling

### continuum_generator

Code generator that produces:
- `_$<Aggregate>EventHandlers` mixin for mutation events
- `applyEvent()` dispatcher and `replayEvents()` helper
- `createFromEvent()` factory dispatcher
- `$generatedEventRegistry` for deserialization
- Aggregate factory and applier registries

### continuum_store_memory

In-memory `EventStore` implementation suitable for testing and development.

### continuum_store_hive

Hive-backed `EventStore` implementation for local persistence.

## License

MIT
