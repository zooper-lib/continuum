# Dart Event Sourcing – Design Specification

This document describes the architecture for a **Marten‑style event sourcing system** in Dart, following these key principles:

- Aggregates are **passive**: they only have state and `apply`/`create` methods for events.
- Commands or application services create **DomainEvent** instances.
- A **Session** object is responsible for:
  - starting streams
  - appending events
  - tracking pending events
  - applying events to aggregates
  - persisting changes on `saveChanges()`
- Aggregates do **not** hold lists of pending events.
- Aggregates do **not** have a version field – version is infrastructure metadata.
- All persistence is done through the Session and an `EventStore` abstraction.

The target is to mirror Marten's conceptual model as closely as possible in Dart, within language constraints.

---

## 1. Core Concepts

### 1.1 DomainEvent

All events extend a common abstract base class.

Required fields:

- `eventId` – strong type (`EventId`) using ULID, auto-generated
- `occurredOn` – `DateTime`, auto-generated as `DateTime.now().toUtc()`
- `metadata` – `Map<String, dynamic>`, optional (may return empty map)

```dart
/// Strong type for event identifiers using ULID (conceptual). 
class EventId {
  final String value;
  const EventId(this.value);
}

abstract class DomainEvent {
  EventId get eventId;
  DateTime get occurredOn;
  Map<String, dynamic> get metadata;
  
  Map<String, dynamic> toJson();
}
```

Events themselves are plain immutable value objects.

Each event declares its aggregate and a stable type discriminator via annotation:

```dart
@Event(
  ofAggregate: UserAggregate,
  type: 'user.created.v1',  // stable, explicit, globally unique
)
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

  @override
  Map<String, dynamic> toJson() => {
    'eventId': eventId.value,
    'occurredOn': occurredOn.toIso8601String(),
    'name': name,
    'email': email,
  };
  
  factory UserCreatedEvent.fromJson(Map<String, dynamic> json) => UserCreatedEvent(
    eventId: EventId(json['eventId'] as String),
    occurredOn: DateTime.parse(json['occurredOn'] as String),
    name: json['name'] as String,
    email: json['email'] as String,
  );
}
```

The generator uses `@Event(ofAggregate: ..., type: ...)` to:
- Know which events to wire into which aggregate
- Build the event type registry for serialization

---

### 1.2 Aggregate

Aggregates are passive plain Dart classes:

- They contain state.
- They define how to apply non-creation events via `apply<EventName>` methods.
- They define static `create*` methods that construct new instances from creation events.
- They do **not** extend a base class.
- They do **not** have a version field (version is managed by Session/EventStore).
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
- The stream ID is external to the aggregate (passed to Session methods, not stored in aggregate).

---

## 2. Code Generation for Apply and Create

Because Dart does not have reflection suitable for this use case, a generator is used to enforce type safety and reduce boilerplate.

### 2.1 Aggregate and Event Discovery

Aggregates are discovered via `@Aggregate()` annotation:

```dart
@Aggregate()
class UserAggregate { ... }
```

Events declare their aggregate and type discriminator:

```dart
@Event(ofAggregate: UserAggregate, type: 'user.name_changed')
class NameChangedEvent extends DomainEvent { ... }
```

The generator scans all annotations and builds mappings:

```
UserAggregate => {
  creationEvents: [UserCreatedEvent],
  mutationEvents: [NameChangedEvent, EmailChangedEvent],
}
```

### 2.2 Generated Contracts

For each aggregate, the generator produces:

- A mixin that defines required `apply` method signatures for **non-creation events only**.
- A dispatcher for applying events during replay.
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

### 2.3 Generated Dispatchers

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
      // Note: NO version increment – aggregates don't track version
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

### 2.4 Creation Event Convention

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

## 3. Session

The `Session` is the unit of work. It is responsible for:

- Tracking which aggregates and event streams are being changed.
- Holding pending (not yet persisted) events.
- Applying new events to in-memory aggregates immediately when they are added.
- **Tracking stream versions internally** (aggregates don't have version).
- Persisting all pending events atomically on `saveChanges()`.

### 3.1 Session Interface

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
}
```

### 3.2 Session Behavior

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

**Version tracking:**
- Version lives only inside Session and EventStore.
- Aggregates never see or store version.
- Session uses `_streamVersions[streamId]` to track current persisted version.

Pending events are stored **inside the session**, not in the aggregate.

---

## 4. Event Store

The `EventStore` is the infrastructure abstraction used by the `Session` to persist events.

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

Different implementations:

- In memory (for tests)
- SQLite (for offline or local persistence)
- Hive/Sembast for local non-sql persistence

The `EventStore` is responsible for:

- Returning the complete list of events for a stream (empty if not found).
- Appending a batch of events with version checking.
- Guaranteeing strictly sequential version numbers.

---

## 5. Serialization

Events must be serialized to and from JSON for storage and transport.

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

### 5.1 Type Discriminator

The event type discriminator comes from the `@Event` annotation:

```dart
@Event(ofAggregate: UserAggregate, type: 'user.created.v1')
class UserCreatedEvent extends DomainEvent { ... }
```

Rules for type discriminator:
- Custom, explicit string (not derived from class name).
- Must be globally unique across all events.
- Must be stable forever (survives refactors, package renames).
- Should be readable/debuggable.
- Missing annotation = generator warning (event ignored).

### 5.2 Event Registry

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

### 5.3 JSON Contract

Events must implement:
- `Map<String, dynamic> toJson()` – for serialization
- `static T fromJson(Map<String, dynamic> json)` – for deserialization

The framework does not mandate how these are implemented. Developers may use:
- `json_serializable`
- Manual mapping
- Any other tool

---

## 6. Aggregate Lifecycle Example

End to end example of typical usage.

### 6.1 Creating a new aggregate

Command handler decides that a `UserCreatedEvent` should be emitted:

```dart
final session = store.openSession();

final streamId = StreamId('user-123');
final createdEvent = UserCreatedEvent(
  name: 'Daniel',
  email: 'test@example.com',
  // eventId and occurredOn are auto-generated
);

// Start the stream with creation event
session.startStream<UserAggregate>(streamId, createdEvent);

// More events can be appended before saving
session.append(streamId, NameChangedEvent(newName: 'Dan'));

await session.saveChanges();
```

### 6.2 Loading and using an aggregate

```dart
final session = store.openSession();

final user = await session.load<UserAggregate>(StreamId('user-123'));
// `load` internally:
// - reads all events from EventStore
// - calls UserAggregate.create(firstEvent) to construct
// - calls applyEvent for remaining events

// After load, `user` has correct, current state.
```

If there is a new event to append later:

```dart
session.append(StreamId('user-123'), EmailChangedEvent(
  newEmail: 'new@example.com',
));

await session.saveChanges();
```

The session will:
- Apply the new event immediately to cached aggregate via `applyEvent`.
- Append the new event to the event store with correct `expectedVersion`.

---

## 7. EventSourcingStore

The `EventSourcingStore` is the configured root object (similar to Marten's `DocumentStore`):

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

## 8. Testing

For testing, an `InMemoryEventStore` is provided:

```dart
class InMemoryEventStore implements EventStore {
  final Map<StreamId, List<StoredEvent>> _streams = {};
  
  @override
  Future<List<StoredEvent>> loadStream(StreamId streamId) async {
    return _streams[streamId] ?? [];
  }

  @override
  Future<void> appendEvents(
    StreamId streamId,
    int expectedVersion,
    List<DomainEvent> events,
  ) async {
    // Implementation with version checking
  }
}
```

Aggregates can be tested in isolation without any infrastructure:

```dart
test('UserAggregate applies name change', () {
  final user = UserAggregate.create(UserCreatedEvent(name: 'Dan', email: 'x@y.com'));
  user.applyNameChangedEvent(NameChangedEvent(newName: 'Daniel'));
  
  expect(user.name, equals('Daniel'));
});
```

---

## 9. Out of Scope for Initial Version

The following can be added later but are intentionally excluded from the first iteration:

- Snapshots (design hooks exist in EventStore/Session)
- Projections/read models (optional `globalSequence` included in StoredEvent)
- Automatic event publication to message buses
- Multi device synchronization logic
- Command bus and pipeline behaviors
- Aggregate caching in Session
- Upcasters for schema evolution (v1 uses new event types strategy)

---

## 10. Summary of Responsibilities

| Component | Responsibilities |
|-----------|------------------|
| **DomainEvent** | Pure value object; declares aggregate and type via annotation; provides `toJson`/`fromJson` |
| **Aggregate** | Domain state; `apply<Event>` methods for mutations; static `create*` methods for creation; no base class; no version |
| **Code Generator** | Discovers aggregates/events via annotations; generates apply contracts (non-creation only); generates dispatchers and factories; generates event registry |
| **Session** | Tracks pending events per stream; tracks version internally; applies events to cached aggregates; loads aggregates by replay; persists atomically on `saveChanges()` |
| **EventStore** | Persists and loads event streams; enforces optimistic concurrency; guarantees sequential versions |
| **EventSourcingStore** | Configured root object; creates sessions; holds dependencies |
| **EventSerializer / Registry** | Converts between stored JSON and DomainEvent instances; uses stable type discriminators |

This specification is intended to be handed to an AI coding agent to implement the package skeleton, code generator, and initial infrastructure.
