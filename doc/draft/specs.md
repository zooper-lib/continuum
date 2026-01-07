# Continuum – Design Specification

This document describes the architecture for **Continuum**, a domain event modeling and event sourcing framework for Dart.

---

## Philosophy

Continuum is not designed around a single interpretation of "event sourcing". Instead, it is built around **domain events as a modeling tool** that can be applied in different contexts, depending on where the source of truth lives.

The central idea is that **domain events describe meaningful state transitions**, and **aggregates define how those transitions affect domain state**. Whether events are persisted, transmitted, or discarded depends on the usage mode.

### Supported Usage Modes

**1. Event-Driven Aggregate Mutation (No Persistence)**

Events are used as typed, explicit state transitions. Aggregates apply events and enforce invariants. Only the final aggregate state is stored (CRUD persistence). Events are not persisted or replayed.

Suitable for:
- Clean Architecture domain layers
- Applications that want strong domain modeling
- Systems that benefit from explicit mutations but do not require event sourcing

**2. Frontend-Only Event Sourcing**

The frontend is the sole source of truth. Domain events are persisted locally (e.g., SQLite, Hive, file). Aggregates are reconstructed by replaying events.

Suitable for:
- Offline-first applications
- Single-user tools
- Desktop applications
- Scenarios where no backend exists

**3. Hybrid Mode (Backend Source of Truth, Frontend Optimistic)**

The backend is the authoritative source of truth, while the frontend uses Continuum for optimistic state modeling. Frontend events are transient. The frontend eventually sends a command to the backend, which validates and persists its own events.

Suitable for:
- Optimistic UI patterns
- Undo/cancel before commit
- Conflict-aware UX

### Key Conceptual Distinctions

- **Events are not APIs.** Domain events are internal modeling constructs, not public contracts.
- **Frontend and backend events have different roles.** Frontend events are optimistic and disposable; backend events are authoritative and durable.
- **Aggregates are disposable on the frontend.** In hybrid mode, frontend aggregates are temporary and may be replaced by backend state after successful command execution.

---

## Architecture Overview

Continuum is organized into two conceptual layers and multiple packages.

### Layer 1: Core (Event Application)

The foundation. Provides domain event modeling and aggregate state transitions without any persistence concerns.

**The `continuum` package provides:**
- `@Aggregate()` annotation
- `@Event()` annotation (with optional `type` for serialization)
- `DomainEvent` base class
- `EventId`, `StreamId` strong types
- Exception types

**The `continuum_generator` package generates (into user's project):**
- `_$<Aggregate>EventHandlers` mixin (apply method contracts)
- `applyEvent()` dispatcher extension
- `replayEvents()` helper extension
- `createFromEvent()` factory for aggregate construction
- `EventRegistry` for deserialization (when using persistence)

**Layer 1 does NOT include:**
- Session
- EventStore
- Version tracking
- Pending event lists

### Layer 2: Persistence (Event Sourcing)

Builds on Layer 1. Adds event stream persistence, version tracking, and session management.

**The `continuum` package also provides (for persistence):**
- `Session` interface (pending events, version tracking, atomic save)
- `EventStore` interface
- `EventSourcingStore` (configured root)
- `EventSerializer` interface
- `StoredEvent`, `ExpectedVersion`, concurrency types
- `@Event(type: '...')` becomes **required** for serialization

**EventStore implementations (separate packages):**
- `continuum_store_memory` – In-memory EventStore (for testing)
- `continuum_store_hive` – Hive persistence
- Future: additional storage backends

Users may also implement the `EventStore` interface for custom persistence.

---

## Part I: Core Layer

---

## 1. DomainEvent

All events extend a common abstract base class.

Required fields:

- `eventId` – strong type (`EventId`) using ULID, auto-generated
- `occurredOn` – `DateTime`, auto-generated as `DateTime.now().toUtc()`
- `metadata` – `Map<String, dynamic>`, optional (may return empty map)

```dart
/// Strong type for event identifiers using ULID.
class EventId {
  final String value;
  const EventId(this.value);
}

abstract class DomainEvent {
  EventId get eventId;
  DateTime get occurredOn;
  Map<String, dynamic> get metadata;
}
```

Events are plain immutable value objects.

Each event declares its aggregate via annotation. The `type` discriminator is **optional in the core layer** (only required when using persistence):

```dart
@Event(ofAggregate: UserAggregate)
class UserCreatedEvent extends DomainEvent {
  @override
  final EventId eventId;
  
  @override
  final DateTime occurredOn;
  
  @override
  Map<String, dynamic> get metadata => {};
  
  final String name;
  final String email;

  UserCreatedEvent({
    required this.name,
    required this.email,
    EventId? eventId,
    DateTime? occurredOn,
  })  : eventId = eventId ?? EventId(Ulid().toString()),
        occurredOn = occurredOn ?? DateTime.now().toUtc();
}
```

The generator uses `@Event(ofAggregate: ...)` to know which events to wire into which aggregate.

---

## 2. Aggregate

Aggregates are passive plain Dart classes:

- They contain state.
- They define how to apply non-creation events via `apply<EventName>` methods.
- They define static `create*` methods that construct new instances from creation events.
- They do **not** extend a base class.
- They do **not** have a version field (version is infrastructure metadata in the persistence layer).
- They do **not** know anything about persistence, sessions, or event stores.
- They do **not** contain a list of pending or uncommitted events.

Aggregates are discovered via the `@Aggregate()` annotation:

```dart
@Aggregate()
class UserAggregate {
  String? name;
  String? email;

  UserAggregate({this.name, this.email});

  // Static factory for creation – does NOT call any apply method
  static UserAggregate create(UserCreatedEvent event) {
    return UserAggregate(
      name: event.name,
      email: event.email,
    );
  }

  // Apply handlers for non-creation events (bodies written by developer)
  void applyNameChangedEvent(NameChangedEvent event) {
    name = event.newName;
  }

  void applyEmailChangedEvent(EmailChangedEvent event) {
    email = event.newEmail;
  }
}
```

Important:

- There are no `changeName`, `changeEmail` methods on the aggregate.
- All domain changes are expressed as events created outside the aggregate.
- The aggregate only knows how to apply events and how to construct itself from creation events.
- **Creation events** are handled by `create*` methods – no `apply` method exists for them.
- **Non-creation events** are handled by `apply<EventName>` methods.
- The stream ID is external to the aggregate (used by the persistence layer, not stored in aggregate).

---

## 3. Code Generation (Core)

Because Dart does not have reflection suitable for this use case, a generator is used to enforce type safety and reduce boilerplate.

### 3.1 Aggregate and Event Discovery

Aggregates are discovered via `@Aggregate()` annotation:

```dart
@Aggregate()
class UserAggregate { ... }
```

Events declare their aggregate:

```dart
@Event(ofAggregate: UserAggregate)
class NameChangedEvent extends DomainEvent { ... }
```

The generator scans all annotations and builds mappings:

```
UserAggregate => {
  creationEvents: [UserCreatedEvent],
  mutationEvents: [NameChangedEvent, EmailChangedEvent],
}
```

### 3.2 Generated Contracts

For each aggregate, the generator produces:

- A mixin that defines required `apply` method signatures for **non-creation events only**.
- A dispatcher for applying events.
- A creation dispatcher for constructing aggregates from creation events.

Example mixin (**excludes creation events**):

```dart
mixin _$UserAggregateEventHandlers {
  // No applyUserCreatedEvent – creation events use create* methods
  void applyNameChangedEvent(NameChangedEvent event);
  void applyEmailChangedEvent(EmailChangedEvent event);
}
```

The aggregate must implement this mixin:

```dart
@Aggregate()
class UserAggregate with _$UserAggregateEventHandlers {
  // Developer implements all apply methods for non-creation events.
  // If one is missing, compile fails.
}
```

### 3.3 Generated Dispatchers

The generator creates an apply dispatcher for non-creation events:

```dart
extension _$UserAggregateApply on UserAggregate {
  void applyEvent(DomainEvent event) {
    switch (event) {
      case NameChangedEvent e:
        applyNameChangedEvent(e);
      case EmailChangedEvent e:
        applyEmailChangedEvent(e);
      default:
        throw UnsupportedEventException(event.runtimeType);
    }
  }

  void replayEvents(Iterable<DomainEvent> events) {
    for (final event in events) {
      applyEvent(event);
    }
  }
}
```

The generator also creates a creation dispatcher:

```dart
extension _$UserAggregateFactory on Never {
  static UserAggregate createFromEvent(DomainEvent event) {
    return switch (event) {
      UserCreatedEvent e => UserAggregate.create(e),
      _ => throw InvalidCreationEventException(event.runtimeType),
    };
  }
}
```

### 3.4 Creation Event Convention

- Creation events are identified via static `create*` method signatures on the aggregate.
- Each `create*` method takes exactly one parameter: the creation event type.
- The return type is the aggregate type.
- The body of the `create*` method is implemented by the programmer and must **not** call any apply method.
- Multiple `create*` overloads are allowed for schema evolution (e.g., `create`, `createV2`).
- Each creation event type must map to exactly one `create*` method (duplicates = generator error).
- No `apply<CreationEvent>` method is generated for creation events.

Example with schema evolution:

```dart
@Aggregate()
class UserAggregate {
  static UserAggregate create(UserCreatedEventV1 event) {
    return UserAggregate(name: event.name);
  }

  static UserAggregate createV2(UserCreatedEventV2 event) {
    return UserAggregate(
      firstName: event.firstName,
      lastName: event.lastName,
    );
  }
}
```

---

## 4. Core Layer Usage Example

Using the core layer without persistence (Mode 1: Event-Driven Mutation):

```dart
// Create an aggregate from a creation event
final user = UserAggregate.create(UserCreatedEvent(
  name: 'Daniel',
  email: 'test@example.com',
));

// Apply subsequent events
user.applyEvent(NameChangedEvent(newName: 'Dan'));
user.applyEvent(EmailChangedEvent(newEmail: 'new@example.com'));

// User now has current state
expect(user.name, equals('Dan'));
expect(user.email, equals('new@example.com'));

// Save aggregate state via your own CRUD mechanism
await repository.save(user);
// Events are discarded – only final state persists
```

This pattern provides:
- Strong domain modeling with explicit state transitions
- Type-safe event handling
- Testable aggregates without infrastructure

---

## Part II: Persistence Layer

The persistence layer builds on top of the core layer to provide full event sourcing capabilities.

---

## 5. Session

The `Session` is the unit of work. It is responsible for:

- Tracking which aggregates and event streams are being changed.
- Holding pending (not yet persisted) events.
- Applying new events to in-memory aggregates immediately when they are added.
- **Tracking stream versions internally** (aggregates don't have version).
- Persisting all pending events atomically on `saveChanges()`.

### 5.1 Session Interface

```dart
/// Strong type for stream identifiers.
class StreamId {
  final String value;
  const StreamId(this.value);
}

abstract class Session {
  /// Load and rebuild an aggregate from its event stream.
  Future<TAggregate> load<TAggregate>(StreamId streamId);

  /// Start a new event stream for an aggregate type with a creation event.
  void startStream<TAggregate>(StreamId streamId, DomainEvent creationEvent);

  /// Append a new event to an existing stream.
  void append(StreamId streamId, DomainEvent event);

  /// Persist all pending events in a single atomic operation.
  Future<void> saveChanges();

  /// Discard all pending events for a stream without persisting.
  /// Useful for hybrid mode when backend returns authoritative state.
  void discardStream(StreamId streamId);

  /// Discard all pending events across all streams.
  void discardAll();
}
```

### 5.2 Session Behavior

**`load<TAggregate>(streamId)`:**
1. Load all events for the stream from `EventStore`, ordered by version.
2. Take the first event – it must be a valid creation event for `TAggregate`.
3. Call the matching static `create*` method to construct the aggregate.
4. Replay remaining events using the generated `applyEvent` dispatcher (non-creation events only).
5. If the first event is not a valid creation event, throw `InvalidStreamCreationEventException`.
6. Track the stream version internally (count of loaded events).

**`startStream<TAggregate>(streamId, creationEvent)`:**
1. Validate `creationEvent` is a creation event for `TAggregate`.
2. Construct the aggregate via the matching `T.create*(creationEvent)` method.
3. Record the event as pending.
4. Cache the aggregate instance.
5. Do **not** call any apply method.

**`append(streamId, event)`:**
1. Record the event in the session's pending list for that stream.
2. If an aggregate is cached for that stream, immediately apply the event via `applyEvent`.
3. Validate the event type matches the aggregate type for this stream.

**`saveChanges()`:**
1. For each stream with pending events:
   - Use expected version for optimistic concurrency check.
   - Append pending events to EventStore.
2. On success: clear pending events, update internal version tracking.
3. On failure: throw `ConcurrencyException` (or other typed exception), session remains usable.
4. All streams are saved atomically.

**`discardStream(streamId)`:**
1. Remove all pending events for the given stream.
2. Remove the cached aggregate for the stream (if any).
3. Does not affect persisted data.

**`discardAll()`:**
1. Remove all pending events for all streams.
2. Clear all cached aggregates.
3. Session becomes empty but remains usable.

**Version tracking:**
- Version lives only inside Session and EventStore.
- Aggregates never see or store version.
- Session uses `_streamVersions[streamId]` to track current persisted version.

Pending events are stored **inside the session**, not in the aggregate.

---

## 6. Event Store

The `EventStore` is the infrastructure abstraction used by the `Session` to persist events. This is defined in the core package as an **interface only**. Implementations are provided by separate packages.

```dart
abstract class EventStore {
  /// Load all events for a stream, ordered by version.
  /// Returns empty list if stream does not exist (not an exception).
  Future<List<StoredEvent>> loadStream(StreamId streamId);

  /// Append events to a stream with optimistic concurrency.
  /// Use ExpectedVersion.noStream (-1) for new streams.
  Future<void> appendEvents(
    StreamId streamId,
    int expectedVersion,
    List<DomainEvent> events,
  );
}

/// Constants for expected version.
abstract class ExpectedVersion {
  static const int noStream = -1;
}
```

Where `StoredEvent` includes:

```dart
class StoredEvent {
  final EventId eventId;
  final StreamId streamId;
  final int version;              // per-stream position, sequential, no gaps
  final String eventType;         // stable type discriminator from @Event annotation
  final String data;              // serialized JSON
  final DateTime occurredOn;
  final Map<String, dynamic> metadata;
  final int? globalSequence;      // optional, for future projection support

  StoredEvent({
    required this.eventId,
    required this.streamId,
    required this.version,
    required this.eventType,
    required this.data,
    required this.occurredOn,
    required this.metadata,
    this.globalSequence,
  });
}
```

**Concurrency:**
- If `expectedVersion` doesn't match current stream version, throw `ConcurrencyException`.
- Event versions are strictly sequential (0, 1, 2, ...) with no gaps.

**Implementation packages (separate from core):**

| Package | Description | Status |
|---------|-------------|--------|
| `continuum_store_memory` | In-memory store for testing | v1 |
| `continuum_store_hive` | Hive persistence | v1 |
| `continuum_store_sqlite` | SQLite persistence | Future |
| `continuum_store_sembast` | Sembast persistence | Future |

Users may also implement the `EventStore` interface for custom persistence backends.

The `EventStore` is responsible for:

- Returning the complete list of events for a stream (empty if not found).
- Appending a batch of events with version checking.
- Guaranteeing strictly sequential version numbers.

---

## 7. Serialization

Events must be serialized to and from JSON for storage. Serialization is **only required when using the persistence layer**.

```dart
abstract class EventSerializer {
  SerializedEvent serialize(DomainEvent event);
  DomainEvent deserialize(SerializedEvent event);
}

class SerializedEvent {
  final String type;              // stable type discriminator
  final int schemaVersion;        // for future upcasting
  final Object payload;           // Map for JSON, bytes for binary later
}
```

### 7.1 Type Discriminator

When using persistence, the `type` parameter in `@Event` becomes **required**:

```dart
@Event(
  ofAggregate: UserAggregate,
  type: 'user.created.v1',  // required for persistence
)
class UserCreatedEvent extends DomainEvent { ... }
```

Rules for type discriminator:
- Custom, explicit string (not derived from class name).
- Must be globally unique across all events.
- Must be stable forever (survives refactors, package renames).
- Should be readable/debuggable.
- Missing `type` when using persistence = generator error.

### 7.2 Event Registry

The generator builds a registry for deserialization:

```dart
typedef EventFactory = DomainEvent Function(Map<String, dynamic> json);

class EventRegistry {
  static final Map<String, EventFactory> _factories = {
    'user.created.v1': (json) => UserCreatedEvent.fromJson(json),
    'user.name_changed': (json) => NameChangedEvent.fromJson(json),
    // ...
  };

  static DomainEvent fromStored(String eventType, String data) {
    final factory = _factories[eventType];
    if (factory == null) {
      throw UnknownEventTypeException(eventType);
    }
    return factory(Map<String, dynamic>.from(jsonDecode(data)));
  }
}
```

### 7.3 JSON Contract

Events using persistence must implement:
- `Map<String, dynamic> toJson()` – for serialization
- `static T fromJson(Map<String, dynamic> json)` – for deserialization

The framework does not mandate how these are implemented. Developers may use:
- `json_serializable`
- Manual mapping
- Any other tool

**Note:** Events used only with the core layer (no persistence) do not need `toJson`/`fromJson`.

---

## 8. Persistence Layer Usage Examples

### 8.1 Mode 2: Full Event Sourcing (Frontend as Source of Truth)

```dart
final store = EventSourcingStore(
  eventStore: sqliteEventStore,  // from continuum_store_sqlite
  serializer: jsonEventSerializer,
  registry: eventRegistry,
);

final session = store.openSession();

// Create a new aggregate
final streamId = StreamId('user-123');
session.startStream<UserAggregate>(streamId, UserCreatedEvent(
  name: 'Daniel',
  email: 'test@example.com',
));

// Append more events
session.append(streamId, NameChangedEvent(newName: 'Dan'));

// Persist all events atomically
await session.saveChanges();
```

Loading an existing aggregate:

```dart
final session = store.openSession();

final user = await session.load<UserAggregate>(StreamId('user-123'));
// `load` internally:
// - reads all events from EventStore
// - calls UserAggregate.create(firstEvent) to construct
// - calls applyEvent for remaining events

// User now has current state from replayed events
```

### 8.2 Mode 3: Hybrid Mode (Backend Source of Truth)

```dart
final session = store.openSession();

// Optimistically apply events locally
final streamId = StreamId('user-123');
session.startStream<UserAggregate>(streamId, UserCreatedEvent(...));
session.append(streamId, NameChangedEvent(newName: 'Dan'));

// User sees optimistic UI state immediately...

// Send command to backend (NOT Continuum's concern)
final result = await api.createUser(CreateUserCommand(...));

if (result.isSuccess) {
  // Option A: Discard local, reload from backend events
  session.discardStream(streamId);
  // Reload if backend returns events...
  
  // Option B: Discard local, replace with backend state
  session.discardAll();
  // Use backend-returned state directly...
  
  // Option C: Just discard and start fresh next time
  session.discardAll();
} else {
  // Handle error, session still has pending events for retry/undo
}
```

The user is responsible for:
- Calling the backend
- Deciding how to handle the response (reload, replace, discard)
- Managing the transition from optimistic to authoritative state

---

## 9. EventSourcingStore

The `EventSourcingStore` is the configured root object for the persistence layer (similar to Marten's `DocumentStore`):

```dart
class EventSourcingStore {
  final EventStore eventStore;
  final EventSerializer serializer;
  final EventRegistry registry;

  EventSourcingStore({
    required this.eventStore,
    required this.serializer,
    required this.registry,
  });

  Session openSession() {
    return Session(
      eventStore: eventStore,
      serializer: serializer,
      registry: registry,
    );
  }
}
```

- Long-lived, typically one per application.
- Injected via constructor (DI-friendly but DI-agnostic).
- Creates short-lived `Session` instances for each unit of work.

---

## 10. Testing

### 10.1 Core Layer Testing

Aggregates can be tested in isolation without any infrastructure:

```dart
test('UserAggregate applies name change', () {
  final user = UserAggregate.create(UserCreatedEvent(name: 'Dan', email: 'x@y.com'));
  user.applyEvent(NameChangedEvent(newName: 'Daniel'));
  
  expect(user.name, equals('Daniel'));
});
```

This works for all usage modes and requires no persistence setup.

### 10.2 Persistence Layer Testing

For testing with the persistence layer, use `InMemoryEventStore` (from `continuum_store_memory`):

```dart
import 'package:continuum_store_memory/continuum_store_memory.dart';

test('Session persists and reloads aggregate', () async {
  final eventStore = InMemoryEventStore();
  final store = EventSourcingStore(
    eventStore: eventStore,
    serializer: jsonEventSerializer,
    registry: eventRegistry,
  );

  // Create and save
  final session1 = store.openSession();
  session1.startStream<UserAggregate>(StreamId('user-1'), UserCreatedEvent(...));
  await session1.saveChanges();

  // Reload in new session
  final session2 = store.openSession();
  final user = await session2.load<UserAggregate>(StreamId('user-1'));
  
  expect(user.name, equals('Dan'));
});
```

---

## 11. Package Structure

Continuum is organized as multiple packages to keep the core clean and allow users to pick only what they need.

### Packages

**`continuum`** – Core package (includes annotations)
```
continuum/
├── lib/
│   ├── continuum.dart              # Main export
│   └── src/
│       ├── annotations/
│       │   ├── aggregate.dart      # @Aggregate annotation
│       │   └── event.dart          # @Event annotation
│       ├── core/
│       │   ├── domain_event.dart   # DomainEvent base class
│       │   ├── event_id.dart       # EventId strong type
│       │   └── stream_id.dart      # StreamId strong type
│       ├── persistence/
│       │   ├── session.dart        # Session interface
│       │   ├── event_store.dart    # EventStore interface
│       │   ├── stored_event.dart   # StoredEvent, ExpectedVersion
│       │   └── serialization.dart  # EventSerializer interface
│       └── exceptions.dart         # Exception types
```

**`continuum_generator`** – Code generator
```
continuum_generator/
├── lib/
│   ├── builder.dart               # build_runner entry point
│   └── src/
│       ├── aggregate_generator.dart
│       ├── registry_generator.dart
│       └── ...
```

**`continuum_store_memory`** – In-memory EventStore (v1)
```
continuum_store_memory/
├── lib/
│   └── src/
│       └── in_memory_event_store.dart
```

**`continuum_store_hive`** – Hive EventStore (v1)
```
continuum_store_hive/
├── lib/
│   └── src/
│       └── hive_event_store.dart
```

### Generated Code (in user's project)

The generator produces `*.g.dart` part files in the user's project:

```
user_project/
├── lib/
│   └── domain/
│       ├── user_aggregate.dart     # User's aggregate
│       ├── user_aggregate.g.dart   # Generated: mixin, dispatcher, factory
│       ├── events/
│       │   ├── user_created.dart
│       │   └── ...
│       └── event_registry.g.dart   # Generated: type → factory mapping
```

### Dependency Flow

```
continuum (core + annotations)
    ↑
    ├── continuum_generator (dev dependency)
    │       depends on: build_runner, source_gen, analyzer
    │
    ├── continuum_store_memory
    │       depends on: continuum
    │
    └── continuum_store_hive
            depends on: continuum, hive
```

### User Dependencies by Usage Mode

| Mode | `dependencies` | `dev_dependencies` |
|------|----------------|--------------------|
| Mode 1 (no persistence) | `continuum` | `continuum_generator`, `build_runner` |
| Mode 2 (full ES) | `continuum`, `continuum_store_*` | `continuum_generator`, `build_runner` |
| Mode 3 (hybrid) | `continuum`, `continuum_store_*` | `continuum_generator`, `build_runner` |

---

## 12. Out of Scope for Initial Version

The following can be added later but are intentionally excluded from the first iteration:

- Snapshots (design hooks exist in EventStore/Session)
- Projections/read models (optional `globalSequence` included in StoredEvent)
- Automatic event publication to message buses
- Multi-device synchronization logic
- Command bus and pipeline behaviors
- Aggregate caching in Session
- Upcasters for schema evolution (v1 uses new event types strategy)

---

## 13. Summary of Responsibilities

### Core Package (`continuum`)

| Component | Responsibilities |
|-----------|------------------|
| **Annotations** | `@Aggregate()`, `@Event()` – markers for code generation |
| **DomainEvent** | Base class for events; provides `eventId`, `occurredOn`, `metadata` |
| **Strong Types** | `EventId`, `StreamId` – type-safe identifiers |
| **Persistence Interfaces** | `Session`, `EventStore`, `EventSerializer` – contracts for persistence layer |

### Generator Package (`continuum_generator`)

| Output | Responsibilities |
|--------|------------------|
| **`_$<Aggregate>EventHandlers` mixin** | Enforces apply method signatures for non-creation events |
| **`applyEvent()` extension** | Dispatcher that routes events to correct apply methods |
| **`replayEvents()` extension** | Convenience method for applying multiple events |
| **`createFromEvent()` factory** | Constructs aggregate from creation event |
| **`EventRegistry`** | Maps event type strings to `fromJson` factories (for persistence) |

### Persistence Layer

| Component | Responsibilities |
|-----------|------------------|
| **Session** | Tracks pending events per stream; tracks version internally; applies events to cached aggregates; loads aggregates by replay; persists atomically on `saveChanges()`; supports discard for hybrid mode |
| **EventStore** | Interface for persistence; implementations in separate packages |
| **EventSourcingStore** | Configured root object; creates sessions; holds dependencies |
| **EventSerializer / Registry** | Converts between stored JSON and DomainEvent instances; uses stable type discriminators |

---

This specification is intended to be handed to an AI coding agent to implement the package skeleton, code generator, and initial infrastructure.
