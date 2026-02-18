# Continuum

An event sourcing and domain event modeling framework for Dart with code generation support.

## Overview

Continuum provides a comprehensive event sourcing framework for Dart applications, organized into a four-layer architecture:

| Layer | Package | Purpose |
|-------|---------|---------|
| 0 | **`continuum`** | Core types: annotations, events, identity, dispatch registries |
| 0 | **`continuum_generator`** | Code generator for aggregate and event boilerplate |
| 1 | **`continuum_uow`** | Unit of Work session engine: sessions, transactional runner, commit handler |
| 2 | **`continuum_event_sourcing`** | Event sourcing persistence: event stores, serialization, projections |
| 2 | **`continuum_state`** | State-based persistence: REST/DB adapter-driven aggregate persistence |
| 3 | **`continuum_store_memory`** | In-memory EventStore for testing |
| 3 | **`continuum_store_hive`** | Hive-backed EventStore for local persistence |
| 3 | **`continuum_store_sembast`** | Sembast-backed EventStore for cross-platform persistence |

Additional tooling:

- **`continuum_lints`** — Custom lint rules for aggregates and projections

## Quick Start

### 1. Add dependencies

Choose the packages for your use case:

**Event sourcing (local persistence):**

```yaml
dependencies:
  continuum: latest
  continuum_event_sourcing: latest
  continuum_store_memory: latest  # or continuum_store_hive / continuum_store_sembast

dev_dependencies:
  build_runner: ^2.4.0
  continuum_generator: latest
```

**State-based (backend-authoritative):**

```yaml
dependencies:
  continuum: latest
  continuum_state: latest

dev_dependencies:
  build_runner: ^2.4.0
  continuum_generator: latest
```

**Event-driven mutation only (no persistence):**

```yaml
dependencies:
  continuum: latest

dev_dependencies:
  build_runner: ^2.4.0
  continuum_generator: latest
```

### 2. Define your aggregate and events

```dart
import 'package:continuum/continuum.dart';

part 'shopping_cart.g.dart';

class ShoppingCart extends AggregateRoot<String> with _$ShoppingCartEventHandlers {
  List<String> items;

  ShoppingCart._({required super.id, required this.items});
  static ShoppingCart createFromCartCreated(CartCreated event) {
    return ShoppingCart._(id: event.cartId, items: []);
  }

  @override
  void applyItemAdded(ItemAdded event) {
    items.add(event.productId);
  }
}

@AggregateEvent(of: ShoppingCart, type: 'cart.created', creation: true)
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
}
```

### 3. Run the generator

```bash
dart run build_runner build
```

### 4. Use the event sourcing store

```dart
import 'package:continuum_event_sourcing/continuum_event_sourcing.dart';
import 'package:continuum_store_memory/continuum_store_memory.dart';
import 'continuum.g.dart';

final store = EventSourcingStore(
  eventStore: InMemoryEventStore(),
  aggregates: $aggregateList,
);

final session = store.openSession();
await session.applyAsync<ShoppingCart>(
  StreamId('cart-123'),
  CartCreated(cartId: 'cart-123'),
);
await session.applyAsync<ShoppingCart>(
  StreamId('cart-123'),
  ItemAdded(productId: 'product-abc'),
);
await session.saveChangesAsync();
```

### Or use the state-based store

```dart
import 'package:continuum_state/continuum_state.dart';
import 'continuum.g.dart';

final store = StateBasedStore(
  adapters: {ShoppingCart: CartApiAdapter(httpClient)},
  aggregates: $aggregateList,
);

final session = store.openSession();
await session.applyAsync<ShoppingCart>(
  StreamId('cart-123'),
  CartCreated(cartId: 'cart-123'),
);
await session.saveChangesAsync(); // Adapter persists to backend
```

## Packages

### continuum

Core library providing annotations (`@Aggregate`, `@AggregateEvent`, `@Projection`), event contracts (`ContinuumEvent`), identity types (`EventId`, `StreamId`), dispatch registries, `EventApplicationMode`, and core exceptions.

### continuum_generator

Code generator that produces event handling mixins, factory dispatchers, serialization registries, and the auto-discovered `$aggregateList`.

### continuum_uow

Unit of Work session engine: `Session`, `SessionBase`, `SessionStore`, `TransactionalRunner`, `CommitHandler`, `TrackedEntity`, and UoW exceptions. Shared by both event sourcing and state-based persistence.

### continuum_event_sourcing

Event sourcing persistence: `EventSourcingStore`, `EventStore`, `AtomicEventStore`, JSON serialization, projections (single-stream, multi-stream, inline, async), and the event-sourcing `SessionImpl`.

### continuum_state

State-based persistence: `StateBasedStore`, `StateBasedSession`, `AggregatePersistenceAdapter` for REST APIs, databases, and GraphQL backends. Same session contract as event sourcing.

### continuum_store_memory

In-memory `EventStore` implementation for testing and development.

### continuum_store_hive

Hive-backed `EventStore` implementation for local persistence.

### continuum_store_sembast

Sembast-backed `EventStore` implementation for cross-platform local persistence.

### continuum_lints

Custom lint rules for `@Aggregate` and `@Projection` classes.

## License

MIT
