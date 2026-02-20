# Continuum Event Sourcing

Event sourcing persistence strategy for [Continuum](https://github.com/zooper-lib/continuum). Provides event store abstractions, JSON serialization, projection system, and the event-sourcing-specific session that extends the Unit of Work session engine.

## Installation

```yaml
dependencies:
  continuum: latest
  continuum_event_sourcing: latest
  continuum_store_memory: latest  # or continuum_store_hive / continuum_store_sembast

dev_dependencies:
  build_runner: ^2.4.0
  continuum_generator: latest
```

## Key Concepts

### EventSourcingStore

The configuration root for event-sourced persistence. Aggregates are reconstructed by replaying stored events.

```dart
import 'package:continuum_event_sourcing/continuum_event_sourcing.dart';
import 'package:continuum_store_memory/continuum_store_memory.dart';
import 'continuum.g.dart';

final store = EventSourcingStore(
  eventStore: InMemoryEventStore(),
  targets: $aggregateList,
);

final session = store.openSession();
await session.applyAsync<User>(userId, UserRegistered(...));
await session.saveChangesAsync();
```

### EventStore & AtomicEventStore

`EventStore` is the persistence interface for reading and writing event streams. `AtomicEventStore` adds optimistic concurrency via expected-version checks. Store implementations (`continuum_store_memory`, `continuum_store_hive`, `continuum_store_sembast`) implement these interfaces.

### Serialization

Events are serialized to JSON via `JsonEventSerializer`. Implement `toJson()` / `fromJson()` on your events and register them through `@OperationFor(type: YourTarget, key: '...')`.

### Projections

Maintain read models automatically updated when events occur. Supports single-stream and multi-stream projections with inline (strongly consistent) or async (eventually consistent) execution.

## Architecture

This package sits at **Layer 2** of the Continuum architecture. It depends on `continuum` (core types) and `continuum_uow` (session engine).

## License

MIT
