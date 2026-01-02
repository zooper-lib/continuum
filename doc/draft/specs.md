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
- All persistence is done through the Session and an `EventStore` abstraction.

The target is to mirror Marten’s conceptual model as closely as possible in Dart, within language constraints.

---

## 1. Core Concepts

### 1.1 DomainEvent

All events implement a common base type.

Minimal fields:

- `eventId` (string, for deduplication)
- `occurredOn` (DateTime)
- Optional metadata (correlation, causation, user id, etc)

```dart
abstract class DomainEvent {
  String get eventId;
  DateTime get occurredOn;
}
```

Events themselves are plain immutable value objects.

Each event declares the aggregate it belongs to, for example with an annotation:

```dart
@Event(ofAggregate: UserAggregate)
class UserCreatedEvent implements DomainEvent {
  final String eventId;
  final DateTime occurredOn;
  final String name;
  final String email;

  const UserCreatedEvent({
    required this.eventId,
    required this.occurredOn,
    required this.name,
    required this.email,
  });
}
```

The generator uses `@Event(ofAggregate: ...)` to know which events to wire into which aggregate.

---

### 1.2 AggregateRoot

Aggregates are passive:

- They contain state.
- They define how to apply events.
- They may define static `create` methods that construct new instances from initial events.
- They do not know anything about persistence, sessions, or event stores.
- They do not contain a list of pending or uncommitted events.

Base contract:

```dart
abstract class AggregateRoot {
  final String id;
  int version;

  AggregateRoot(this.id, {this.version = 0});
}
```

Concrete example (only showing the signatures that matter conceptually):

```dart
class UserAggregate extends AggregateRoot {
  String? name;
  String? email;

  UserAggregate(String id) : super(id);

  // Static factory for creation from the initial event
  static UserAggregate create(String id, UserCreatedEvent event) {
    final aggregate = UserAggregate(id);
    aggregate.applyUserCreatedEvent(event);
    return aggregate;
  }

  // Apply handlers for events (bodies written by developer)
  void applyUserCreatedEvent(UserCreatedEvent event) {
    name = event.name;
    email = event.email;
  }

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
- The aggregate only knows how to apply events and how to construct itself from an initial event.

---

## 2. Code Generation for Apply and Create

Because Dart does not have reflection suitable for this use case, a generator is used to enforce type safety and reduce boilerplate.

### 2.1 Event Ownership

Events declare their aggregate:

```dart
@Event(ofAggregate: UserAggregate)
class NameChangedEvent implements DomainEvent { ... }
```

The generator scans all `DomainEvent` implementations and builds a mapping:

```
UserAggregate => [UserCreatedEvent, NameChangedEvent, EmailChangedEvent, ...]
```

### 2.2 Generated Contracts

For each aggregate, the generator produces:

- A mixin that defines required `apply` method signatures for each event.
- Optionally, a helper for replaying events.

Example:

```dart
mixin _$UserAggregateEventHandlers {
  void applyUserCreatedEvent(UserCreatedEvent event);
  void applyNameChangedEvent(NameChangedEvent event);
  void applyEmailChangedEvent(EmailChangedEvent event);
}
```

The aggregate must implement this mixin:

```dart
class UserAggregate extends AggregateRoot with _$UserAggregateEventHandlers {
  // Developer implements all apply methods. If one is missing, compile fails.
}
```

Additionally, the generator creates a dispatcher:

```dart
extension UserAggregateReplay on UserAggregate {
  void applyEvent(DomainEvent event) {
    if (event is UserCreatedEvent) {
      applyUserCreatedEvent(event);
    } else if (event is NameChangedEvent) {
      applyNameChangedEvent(event);
    } else if (event is EmailChangedEvent) {
      applyEmailChangedEvent(event);
    } else {
      throw UnsupportedError('Unknown event type: ${event.runtimeType}');
    }
  }

  void replayEvents(Iterable<DomainEvent> events) {
    for (final event in events) {
      applyEvent(event);
      version++;
    }
  }
}
```

For creation, a convention is used:

- There is exactly one “creation event” per aggregate type (for example, `UserCreatedEvent`).
- The developer implements a static `create(String id, CreationEvent event)` method on the aggregate.
- The generator may validate that a suitable creation event exists if desired, but does not need to generate the `create` body itself.

---

## 3. Session

The `Session` is the unit of work. It is responsible for:

- Tracking which aggregates and event streams are being changed.
- Holding pending (not yet persisted) events.
- Applying new events to in-memory aggregates immediately when they are added.
- Persisting all pending events atomically on `saveChanges()`.

### 3.1 Session Interface

```dart
abstract class EventSourcingSession {
  // Load and rebuild an aggregate from its event stream
  Future<TAggregate> load<TAggregate extends AggregateRoot>(String streamId);

  // Start a new event stream for an aggregate type with initial event(s)
  void startStream<TAggregate extends AggregateRoot>(
    String streamId,
    DomainEvent initialEvent,
  );

  // Append a new event to an existing stream
  void append(String streamId, DomainEvent event);

  // Persist all pending events in a single atomic operation
  Future<void> saveChanges();
}
```

### 3.2 Session Behavior

- `load<TAggregate>(streamId)`:
  - loads all events for the given stream from the `EventStore`
  - constructs the aggregate by:
    - creating a new instance (for example with a constructor that takes `id`)
    - calling `replayEvents(events)` extension generated for that aggregate

- `startStream<TAggregate>(streamId, initialEvent)`:
  - marks a new stream as starting
  - records the initial event in the session’s pending list
  - immediately applies the event to an in-memory aggregate instance if one is kept in a cache

- `append(streamId, event)`:
  - records the event in the session’s pending list for that stream
  - immediately applies the event to the cached aggregate instance, if loaded

- `saveChanges()`:
  - for each stream with pending events:
    - reads current version from the event store
    - appends pending events with optimistic concurrency (`expectedVersion`)
  - clears the pending events on success

Pending events are stored **inside the session**, not in the aggregate.

---

## 4. Event Store

The `EventStore` is the infrastructure abstraction used by the `EventSourcingSession` to persist events.

```dart
abstract class EventStore {
  Future<List<StoredEvent>> loadStream(String streamId);

  Future<void> appendEvents(
    String streamId,
    int expectedVersion,
    List<DomainEvent> events,
  );
}
```

Where `StoredEvent` includes at least:

```dart
class StoredEvent {
  final String eventId;
  final String streamId;
  final int version;
  final String eventType;
  final String data;       // serialized JSON
  final DateTime occurredOn;
  // plus metadata if needed

  StoredEvent({
    required this.eventId,
    required this.streamId,
    required this.version,
    required this.eventType,
    required this.data,
    required this.occurredOn,
  });
}
```

Different implementations:

- In memory (for tests)
- SQLite (for offline or local persistence)
- Hive/Sembast for local non-sql persistence

The `EventStore` is responsible for:

- returning the complete list of events for a stream
- appending a batch of events with version checking

---

## 5. Serialization

Events must be serialized to and from JSON for storage and transport.

```dart
abstract class EventSerializer {
  String serialize(DomainEvent event);
  DomainEvent deserialize(String eventType, String json);
}
```

The mapping of `eventType` string to actual Dart class is generated from the same information used for event ownership:

- For each `@Event(ofAggregate: SomeAggregate)` the generator registers:
  - a type discriminator (for example the event class name)
  - a constructor from JSON

The generator can build a registry class, for example:

```dart
typedef EventFactory = DomainEvent Function(Map<String, dynamic> json);

class EventRegistry {
  static final Map<String, EventFactory> _factories = {
    'UserCreatedEvent': (json) => UserCreatedEvent.fromJson(json),
    'NameChangedEvent': (json) => NameChangedEvent.fromJson(json),
    // ...
  };

  static DomainEvent fromStored(String eventType, String data) {
    final factory = _factories[eventType];
    if (factory == null) {
      throw UnsupportedError('Unknown event type: $eventType');
    }
    return factory(Map<String, dynamic>.from(jsonDecode(data)));
  }
}
```

The `EventStore` uses this registry via an `EventSerializer` implementation.

---

## 6. Aggregate Lifecycle Example

End to end example of typical usage.

### 6.1 Creating a new aggregate

Command handler decides that a `UserCreatedEvent` should be emitted:

```dart
final session = eventSourcing.openSession();

const streamId = 'user-123';
final createdEvent = UserCreatedEvent(
  eventId: uuid(),
  occurredOn: DateTime.now().toUtc(),
  name: 'Daniel',
  email: 'test@example.com',
);

// Persist creation
session.startStream<UserAggregate>(streamId, createdEvent);

// Optionally, build an in-memory instance now
final userAggregate = UserAggregate.create(streamId, createdEvent);

// More events can be appended before saving
session.append(streamId, NameChangedEvent(
  eventId: uuid(),
  occurredOn: DateTime.now().toUtc(),
  newName: 'Dan',
));

await session.saveChanges();
```

### 6.2 Loading and using an aggregate

```dart
final session = eventSourcing.openSession();

final user = await session.load<UserAggregate>('user-123');
// `load` internally:
// - reads all events from EventStore
// - constructs a new UserAggregate(id)
// - calls user.replayEvents(events)

// After load, `user` has correct, current state.
```

If there is a new event to append later:

```dart
session.append('user-123', EmailChangedEvent(
  eventId: uuid(),
  occurredOn: DateTime.now().toUtc(),
  newEmail: 'new@example.com',
));

await session.saveChanges();
```

The session will:

- apply the new event immediately to `user` if it keeps a cached instance
- append the new event to the event store with correct `expectedVersion`

---

## 7. Out of Scope for Initial Version

The following can be added later but are intentionally excluded from the first iteration:

- Snapshots
- Projections (read models)
- Automatic event publication to message buses
- Multi device synchronization logic
- Command bus and pipeline behaviors

---

## 8. Summary of Responsibilities

- **DomainEvent**
  - pure value object
  - declares its aggregate via annotation or interface
- **AggregateRoot**
  - domain state
  - `applyXxxEvent` methods
  - static `create(id, initialEvent)` methods for initial events
  - no persistence concerns
- **Code Generator**
  - derives event ownership from annotations
  - generates apply method contracts and replay helpers
  - generates event type registry for serialization
- **EventSourcingSession**
  - tracks pending events per stream
  - applies new events immediately to in-memory aggregates
  - loads aggregates by replaying events
  - persists events on `saveChanges()`
- **EventStore**
  - persists and loads event streams
  - enforces optimistic concurrency
- **EventSerializer / Registry**
  - converts between stored JSON and DomainEvent instances

This specification is intended to be handed to an AI coding agent to implement the package skeleton, code generator, and initial infrastructure.
