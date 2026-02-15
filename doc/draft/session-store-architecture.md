# Session & Store Architecture — Swappable Persistence

## The Core Principle

Aggregates **always** mutate through domain events, regardless of how they are persisted. The workflow code never changes — only the store wiring does.

```dart
// This code is IDENTICAL whether backed by local ES, backend API, or anything else
await runner.runAsync(() async {
  final session = TransactionalRunner.currentSession;
  final user = await session.applyAsync<User>(userId, EmailChanged(newEmail: 'new@example.com'));
  // session.saveChangesAsync() is called automatically by the runner
});
```

Three invariants:

1. **The Session is the unit of work** — it tracks pending events, not the aggregate.
2. **The Store is the swappable strategy** — EventStore, backend API, or anything else.
3. **The TransactionalRunner is the lifecycle boundary** — it opens, commits, and publishes.

---

## Design Decision: Events Belong to the Session, Not the Aggregate

### The Problem with `AggregateRoot._events`

The `bounded` package's `AggregateRoot` maintains an internal `List<DomainEvent> _events` buffer with `recordEvent()`, `pullEvents()`, and `clearEvents()`. This creates several problems:

1. **Dual tracking**: The session already tracks pending events per stream in `_StreamState.pendingEvents`. Having a second event list on the aggregate is redundant and creates synchronization risk.
2. **Unclear ownership**: Who is responsible for clearing the events? The session? The aggregate? The workflow? This ambiguity invites bugs.
3. **Leaky abstraction**: The aggregate exposes persistence concerns (`pullEvents`, `clearEvents`) that have nothing to do with domain logic.
4. **Incompatible with state-based persistence**: When hydrating an aggregate from a backend snapshot, there is no event stream to replay. The aggregate's internal event buffer is meaningless in this mode.

### The Solution

**The session is the single owner of pending events.** The aggregate is a pure domain object — it holds state, enforces invariants, and exposes mutation methods (the generated `apply*` handlers). It does **not** track, record, or expose events.

What this means in practice:

| Concern | Before (AggregateRoot) | After (Session-owned) |
|---|---|---|
| **Who records events?** | Aggregate via `recordEvent()` | Session via `applyAsync()` / internal `_append()` |
| **Who stores pending events?** | Aggregate's `_events` list | Session's `_StreamState.pendingEvents` |
| **Who clears events after save?** | Ambiguous (caller? session?) | Session — automatically on successful save |
| **Aggregate's responsibility** | State + events + domain logic | State + domain logic only |
| **Works with state-based mode?** | No — events buffer is meaningless | Yes — session tracks events regardless of persistence strategy |

The `bounded` package's `AggregateRoot` remains usable as a base class for identity and entity semantics. Its event buffer (`recordEvent`/`pullEvents`/`clearEvents`) is simply **not used** by continuum. Users should not call those methods — the session handles everything.

> **Note**: Continuum's runtime already ignores `AggregateRoot._events` today. The `SessionImpl` tracks events via `_StreamState.pendingEvents`, and the generated `EventApplierRegistry` calls `apply*` handlers directly without involving `recordEvent()`. This design decision formalizes what is already the case.

---

## Unified Mutation API: `applyAsync`

### The Problem with `startStream` + `append`

The current `ContinuumSession` forces the user to distinguish between creating a new aggregate and mutating an existing one:

```dart
// Creation — user must know this is a new stream
final user = session.startStream<User>(userId, UserRegistered(name: 'Alice'));

// Mutation — user must know this stream already exists
session.append(userId, EmailChanged(newEmail: 'new@example.com'));
```

This creates friction:

1. **Cognitive load**: The user must always know whether a stream exists or not before choosing the right method.
2. **Fragile workflows**: If a workflow sometimes creates and sometimes mutates (e.g., "ensure aggregate exists, then apply change"), the branching logic leaks into every call site.
3. **Unnecessary coupling**: The distinction between "first event" and "subsequent event" is a persistence concern, not a domain concern. The domain just says "this happened."

### The Solution: Single `applyAsync` Method

```dart
abstract interface class ContinuumSession {
  /// Applies a domain event to the aggregate identified by [streamId].
  ///
  /// If the stream is already tracked in this session, the event is applied
  /// directly to the in-memory aggregate.
  ///
  /// If the stream is not yet tracked, the method inspects the event:
  /// - **Creation event** (registered in `AggregateFactoryRegistry`): creates
  ///   a new aggregate from the event and begins tracking a new stream.
  /// - **Mutation event** (not a creation event): loads the aggregate from
  ///   the store, then applies the event on top.
  ///
  /// Returns the aggregate in its post-event state.
  Future<TAggregate> applyAsync<TAggregate>(
    StreamId streamId,
    ContinuumEvent event,
  );

  /// Loads an aggregate without applying any event.
  ///
  /// Useful when the workflow needs to read aggregate state before deciding
  /// what event to apply, or when no mutation is needed at all.
  Future<TAggregate> loadAsync<TAggregate>(StreamId streamId);

  /// Persists all pending events across all tracked streams.
  ///
  /// Returns the list of committed events (in order) so that the caller
  /// (typically the [TransactionalRunner]) can publish them.
  Future<List<ContinuumEvent>> saveChangesAsync({int maxRetries = 1});

  /// Discards pending events for a specific stream.
  void discardStream(StreamId streamId);

  /// Discards all pending events across all tracked streams.
  void discardAll();
}
```

### How `applyAsync` Works Internally

```dart
Future<TAggregate> applyAsync<TAggregate>(
  StreamId streamId,
  ContinuumEvent event,
) async {
  // 1. Already tracked? Apply directly.
  final existingState = _streams[streamId];
  if (existingState != null) {
    _append(streamId, event);
    return existingState.aggregate as TAggregate;
  }

  // 2. Is this a creation event? Check the factory registry.
  final factory = _aggregateFactories.getFactory<TAggregate>(
    TAggregate,
    event.runtimeType,
  );

  if (factory != null) {
    // Creation path — new aggregate from this event.
    final aggregate = factory(event);
    _streams[streamId] = _StreamState(
      aggregate: aggregate as Object,
      aggregateType: TAggregate,
      loadedVersion: -1,
      pendingEvents: [event],
    );
    return aggregate;
  }

  // 3. Mutation path — load from store, then apply.
  await loadAsync<TAggregate>(streamId);
  _append(streamId, event);
  return _streams[streamId]!.aggregate as TAggregate;
}
```

**Key insight**: The method auto-detects the intent by probing the `AggregateFactoryRegistry`. If the event has a registered creation factory, it's a creation event. Otherwise, it's a mutation event that requires an existing aggregate. No ambiguity, no branching for the user.

### `startStream` and `append` Become Internal

The old `startStream()` and `append()` methods are no longer part of `ContinuumSession`. Their logic is folded into `applyAsync()` and into the private `_append()` method. This reduces the public API surface from three mutation methods to one.

### What About Loading Without Mutating?

`loadAsync<TAggregate>(StreamId)` remains on the session for read-only access. Workflows that need to inspect aggregate state before deciding what event to apply still call `loadAsync` first:

```dart
final user = await session.loadAsync<User>(userId);
if (user.isActive) {
  await session.applyAsync<User>(userId, UserDeactivated());
}
```

If `loadAsync` was called first, `applyAsync` hits the "already tracked" fast path — no redundant store access.

---

## Eager vs. Deferred Event Application

### The Question

When the user calls `applyAsync`, should the event mutate the aggregate **immediately** (in-memory), or should the mutation be **deferred** until `saveChangesAsync` succeeds?

### Two Strategies

#### Eager Application (apply-on-call)

The event is applied to the aggregate immediately when `applyAsync` is called. The workflow sees the post-event state right away.

```dart
await runner.runAsync(() async {
  final session = TransactionalRunner.currentSession;
  final user = await session.applyAsync<User>(userId, EmailChanged(newEmail: 'new@example.com'));
  print(user.email); // → 'new@example.com' — already mutated
});
```

**When this is useful**:
- The workflow needs to read updated state to decide what to do next (e.g., check invariants, compute derived values, conditionally apply further events).
- The aggregate enforces business rules in its `apply*` handlers — the workflow needs immediate feedback.
- Most event-sourcing workflows expect this behavior.

#### Deferred Application (apply-on-save)

The event is recorded but **not** applied to the aggregate until `saveChangesAsync` succeeds. The workflow sees the pre-event state throughout the transaction.

```dart
await runner.runAsync(() async {
  final session = TransactionalRunner.currentSession;
  final user = await session.applyAsync<User>(userId, EmailChanged(newEmail: 'new@example.com'));
  print(user.email); // → 'old@example.com' — NOT yet mutated
  // Mutation happens inside saveChangesAsync, after persistence succeeds
});
```

**When this is useful**:
- The workflow should not act on uncommitted state. If the save fails (concurrency, network), the aggregate was never actually in the post-event state — reading it as if it were could lead to incorrect decisions.
- "Fire-and-forget" event patterns where the workflow applies events but doesn't inspect the resulting state.
- State-based mode where the backend is the authority — the client should not assume a state that the backend hasn't confirmed.

### The User Decides

This is a **store-level or session-level configuration**, not a per-event decision. The user chooses the strategy when setting up the store:

```dart
// Eager (default) — events mutate the aggregate immediately
final store = EventSourcingStore(
  eventStore: SembastEventStore(database),
  aggregates: [$User, $Playlist],
  applicationMode: EventApplicationMode.eager,
);

// Deferred — events are recorded but applied only on successful save
final store = EventSourcingStore(
  eventStore: SembastEventStore(database),
  aggregates: [$User, $Playlist],
  applicationMode: EventApplicationMode.deferred,
);
```

```dart
/// Controls when domain events mutate the in-memory aggregate.
enum EventApplicationMode {
  /// Events are applied to the aggregate immediately when
  /// [ContinuumSession.applyAsync] is called. The workflow sees
  /// the post-event state right away.
  eager,

  /// Events are recorded but not applied to the aggregate until
  /// [ContinuumSession.saveChangesAsync] succeeds. The workflow
  /// sees the pre-event state throughout the transaction.
  deferred,
}
```

### How Each Mode Affects Session Internals

| Concern | Eager | Deferred |
|---|---|---|
| **`applyAsync` behavior** | Calls `apply*` handler immediately | Records event in `pendingEvents` only |
| **Aggregate state during transaction** | Post-event (mutated) | Pre-event (unchanged) |
| **`loadAsync` after `applyAsync`** | Returns mutated aggregate | Returns original aggregate |
| **`saveChangesAsync` behavior** | Serialize + persist | Apply all pending events, then serialize + persist |
| **Concurrency retry** | Reload → re-apply all pending | Reload → apply all pending (same as initial) |
| **Failed save (no retry)** | In-memory aggregate is in uncommitted state | In-memory aggregate is clean |

### Impact on `applyAsync` Implementation

The difference is small — a single branch in the internal `_append` method:

```dart
void _append(StreamId streamId, ContinuumEvent event) {
  final state = _streams[streamId]!;
  state.pendingEvents.add(event);

  if (_applicationMode == EventApplicationMode.eager) {
    // Mutate the aggregate now — workflow sees updated state
    _applyEventToAggregate(state, event);
  }
  // Deferred: event is only recorded. Applied later in saveChangesAsync.
}
```

In deferred mode, `saveChangesAsync` applies all pending events to the aggregate **before** serializing and persisting:

```dart
Future<List<ContinuumEvent>> saveChangesAsync({int maxRetries = 1}) async {
  if (_applicationMode == EventApplicationMode.deferred) {
    // Apply all pending events now, just before persistence
    for (final entry in _streams.entries) {
      for (final event in entry.value.pendingEvents) {
        _applyEventToAggregate(entry.value, event);
      }
    }
  }

  // ... proceed with serialization and persistence
}
```

### Recommendation

**Default to eager.** Most event-sourcing workflows need to read post-event state. Deferred mode is an opt-in for users who want stricter separation between "intent" and "committed state" — particularly useful in state-based mode where the backend is the authority.

Both modes produce the same persisted result. The only difference is **when** the in-memory aggregate reflects the change.

---

## The TransactionalRunner — Zone-Based Unit of Work

### The Problem

Today, session lifecycle management is entirely manual:

```dart
final session = store.openSession();
try {
  final user = await session.loadAsync<User>(userId);
  session.append(userId, EmailChanged(newEmail: 'new@example.com'));
  await session.saveChangesAsync();
  // Now what? Publish events? How? Where?
} catch (e) {
  // Discard? The session doesn't clean up automatically.
}
```

This has several problems:

1. **No ambient session**: Every workflow must receive the session as a parameter or create its own. Composing workflows that share a unit of work requires explicit plumbing.
2. **No automatic commit**: The user must remember to call `saveChangesAsync()`. Forgetting means silent data loss.
3. **No event publishing**: After a successful save, committed events should be published to interested listeners (projections, notifications, analytics). There's no hook for this.
4. **Parallel workflows risk**: Two workflows running concurrently in the same Dart isolate can accidentally share a session or create conflicting sessions.

### The Solution: `TransactionalRunner`

The `TransactionalRunner` manages the full lifecycle: open session → execute action → commit → publish events.

```dart
/// Manages the transactional lifecycle of a [ContinuumSession].
///
/// Opens a session, makes it available as an ambient value via [Zone],
/// executes the user's action, commits pending events, and publishes
/// committed events through the configured [CommitHandler].
final class TransactionalRunner {
  final ContinuumStore _store;
  final CommitHandler? _commitHandler;

  static final Object _key = Object();

  /// Creates a runner backed by the given [store].
  ///
  /// If [commitHandler] is provided, it is called with the list of
  /// committed events after every successful [saveChangesAsync].
  TransactionalRunner(this._store, {CommitHandler? commitHandler})
      : _commitHandler = commitHandler;

  /// Returns the ambient session, or `null` if not inside [runAsync].
  static ContinuumSession? get currentSessionOrNull =>
      Zone.current[_key] as ContinuumSession?;

  /// Returns the ambient session.
  ///
  /// Throws [StateError] if called outside of [runAsync].
  static ContinuumSession get currentSession {
    final session = currentSessionOrNull;
    if (session == null) {
      throw StateError(
        'No ambient session. Wrap the call in TransactionalRunner.runAsync().',
      );
    }
    return session;
  }

  /// Runs [action] inside a transactional scope.
  ///
  /// A fresh [ContinuumSession] is created and placed into the current
  /// [Zone] so that any code inside [action] can access it via
  /// [currentSession]. After [action] completes, all pending events
  /// are committed via [ContinuumSession.saveChangesAsync]. If a
  /// [CommitHandler] was registered, it receives the list of committed
  /// events after a successful save.
  ///
  /// If [action] throws, the session is abandoned — no events are saved.
  Future<T> runAsync<T>(Future<T> Function() action) async {
    final session = _store.openSession();
    return runZoned(
      () async {
        final result = await action();
        final committedEvents = await session.saveChangesAsync();

        if (_commitHandler != null && committedEvents.isNotEmpty) {
          await _commitHandler.onCommitAsync(committedEvents);
        }

        return result;
      },
      zoneValues: {_key: session},
    );
  }
}
```

### Why Zones?

Dart's `Zone` class provides **ambient scoping** — a value can be attached to the current execution context and retrieved anywhere within it without explicit parameter passing. This is the same mechanism used by `Zone.current[key]` in Flutter's test framework and in logging libraries.

Benefits for the Unit of Work pattern:

1. **Implicit propagation**: Nested async calls, helper functions, and composed workflows all see the same session without it being threaded through every function signature.
2. **Isolation**: Each `runAsync` call creates a new Zone with its own session. Two concurrent `runAsync` calls on the same isolate get **separate sessions** — no cross-contamination.
3. **Composability**: A workflow can call sub-workflows that access `TransactionalRunner.currentSession` without knowing they're inside a transaction. The sub-workflow doesn't need a session parameter.

```dart
// Workflow A — doesn't need to know about sessions
class DeactivateUserWorkflow {
  Future<void> call(StreamId userId) async {
    final session = TransactionalRunner.currentSession;
    await session.applyAsync<User>(userId, UserDeactivated());
    // No save — the runner handles it
  }
}

// Workflow B — composes A, shares the same session
class DeactivateAndNotifyWorkflow {
  final DeactivateUserWorkflow _deactivate;
  final TransactionalRunner _runner;

  Future<void> call(StreamId userId) async {
    await _runner.runAsync(() async {
      await _deactivate.call(userId);
      // Both workflows share the same session and commit atomically
    });
  }
}
```

### Concurrent Workflows — Zone Isolation

```
Isolate (single Dart thread)
│
├─ runAsync (Zone A)
│   └─ session A (independent)
│       ├─ applyAsync(User, EmailChanged)
│       └─ saveChangesAsync → commit A's events
│
├─ runAsync (Zone B)  ← runs concurrently via async scheduling
│   └─ session B (independent)
│       ├─ applyAsync(User, NameChanged)
│       └─ saveChangesAsync → commit B's events
│
└─ No shared state between A and B
```

Each `runAsync` creates its own session. If both touch the same aggregate, OCC at the store level handles the conflict (reload + retry). The runner doesn't need to coordinate between zones — the store does.

---

## Pluggable Event Publishing: `CommitHandler`

### The Problem

After a successful save, committed events often need to be published — to an event bus, a message queue, analytics, push notifications, or any number of downstream consumers. But continuum is a persistence library, not a messaging library. It cannot prescribe a specific publish mechanism.

### The Solution: `CommitHandler` Interface

```dart
/// Called by [TransactionalRunner] after a successful commit.
///
/// The handler receives the complete list of committed events and
/// can publish them to any downstream system — event bus, message
/// queue, logging, analytics, or nothing at all.
abstract interface class CommitHandler {
  /// Called after all pending events have been successfully persisted.
  ///
  /// [events] contains the committed events in the order they were applied.
  /// This method is called **after** persistence succeeds, so the events
  /// are guaranteed to be durable.
  ///
  /// If this method throws, the committed events are still persisted —
  /// the save is not rolled back. The exception propagates to the caller
  /// of [TransactionalRunner.runAsync].
  Future<void> onCommitAsync(List<ContinuumEvent> events);
}
```

### Why This Design

1. **Continuum doesn't dictate the pub mechanism.** The user injects whatever they use — `StreamController`, `EventBus`, Firebase, or their own abstraction.
2. **The handler receives events, not the aggregate.** This is intentional — publishing should not depend on aggregate state, only on what happened.
3. **After-persist semantics.** Events are published **only after** they are durably persisted. If `saveChangesAsync()` fails, the handler is never called. This prevents publishing events that were never saved.
4. **Fire-and-forget is an option.** The handler can be async, but the runner awaits it. If the user wants fire-and-forget, the handler can spawn the work and return immediately.
5. **No handler is fine.** If no `CommitHandler` is provided, events are persisted and nothing is published. This is the minimal default.

### Example Implementations

```dart
// Simple: Forward to a StreamController
class StreamCommitHandler implements CommitHandler {
  final StreamController<ContinuumEvent> _controller;

  StreamCommitHandler(this._controller);

  @override
  Future<void> onCommitAsync(List<ContinuumEvent> events) async {
    for (final event in events) {
      _controller.add(event);
    }
  }
}
```

```dart
// Composite: Multiple downstream consumers
class CompositeCommitHandler implements CommitHandler {
  final List<CommitHandler> _handlers;

  CompositeCommitHandler(this._handlers);

  @override
  Future<void> onCommitAsync(List<ContinuumEvent> events) async {
    for (final handler in _handlers) {
      await handler.onCommitAsync(events);
    }
  }
}
```

```dart
// Projection-based: Feed into the existing inline projection system
class ProjectionCommitHandler implements CommitHandler {
  final InlineProjectionExecutor _executor;

  ProjectionCommitHandler(this._executor);

  @override
  Future<void> onCommitAsync(List<ContinuumEvent> events) async {
    // Convert to StoredEvents for the projection executor
    // (the session can provide these instead of raw ContinuumEvents)
    await _executor.executeAsync(storedEvents);
  }
}
```

### Where Projections Fit

Inline projections are a specific form of post-commit processing. Instead of the session calling `InlineProjectionExecutor` directly (as it does today), the projection executor becomes a `CommitHandler` registered on the runner. This cleanly separates persistence (session) from reactions (commit handlers).

```
Before (current):
  session.saveChangesAsync()
    → persist events
    → run InlineProjectionExecutor  ← coupled inside session

After (with CommitHandler):
  runner.runAsync()
    → session.saveChangesAsync()
      → persist events
      → return committed events
    → commitHandler.onCommitAsync(events)
      → InlineProjectionExecutor  ← decoupled, user-configured
      → EventBus.publish           ← optional
      → Analytics.track            ← optional
```

This decoupling means:
- The session is responsible **only** for persistence and concurrency.
- Post-commit side effects are configured at the runner level.
- Different runners can have different commit handlers (e.g., test runner with no publishing, production runner with full publishing).

---

## `saveChangesAsync` Returns Committed Events

### The Change

The current `saveChangesAsync()` returns `Future<void>`. With the new design, it returns `Future<List<ContinuumEvent>>` — the list of events that were successfully persisted, in application order.

```dart
Future<List<ContinuumEvent>> saveChangesAsync({int maxRetries = 1});
```

### Why

1. **The runner needs them.** The `TransactionalRunner` must pass committed events to the `CommitHandler`. Without a return value, the runner would need to inspect the session's internal state — which breaks encapsulation.
2. **The user may need them.** Even without a runner, a manual save might want to know what was committed (for logging, analytics, or conditional logic).
3. **Consistent with the "session owns events" principle.** The session collected the events, persisted them, and now reports what was committed. Clean ownership.

### What Gets Returned

The list contains **all events from all streams** that were successfully persisted in this save call, ordered by stream (matching the persistence order). After the return, all streams' `pendingEvents` are cleared.

On concurrency retry, the returned list contains the same logical events (possibly re-applied on a fresher aggregate state). The events are the user's original events — the retry is transparent.

---

## Two Persistence Modes

### Mode 1: Event-Sourced (Local)

The event stream is the source of truth. Aggregate state is derived by replaying events.

```
┌──────────────────────────────────────────────┐
│          TransactionalRunner.runAsync()       │
│   session.applyAsync() → auto-commit → pub   │
└──────────────┬───────────────────────────────┘
               │
     ┌─────────▼──────────┐
     │  EventSourcingStore  │  ← current implementation
     │  .openSession()     │
     └─────────┬──────────┘
               │
     ┌─────────▼──────────┐
     │    EventStore       │  ← Hive / Sembast / InMemory
     │  stores raw events  │
     └────────────────────┘

Load:  events → create(first) → apply(rest) → aggregate
Save:  pending events → append to event stream
Truth: the event stream
```

### Mode 2: State-Based (Backend)

The backend is the source of truth. It stores state, not events. The client still mutates the aggregate through domain events locally — that's the fundamental principle of the package — but **the events themselves are never sent to or stored by the backend**. Instead, the adapter uses the pending events to construct whatever the backend expects: a REST call, a command, a full state update, or any combination.

This is the core insight: **domain events are a local mutation mechanism, not a persistence format.** The same `applyAsync` / `saveChangesAsync` workflow works regardless of what happens on the wire.

```
┌──────────────────────────────────────────────┐
│          TransactionalRunner.runAsync()       │
│   session.applyAsync() → auto-commit → pub   │
│   (IDENTICAL code — no changes)              │
└──────────────┬───────────────────────────────┘
               │
     ┌─────────▼──────────┐
     │   StateBasedStore   │  ← new concept
     │   .openSession()    │
     └─────────┬──────────┘
               │
     ┌─────────▼──────────┐
     │   Backend / API     │
     │  stores state       │
     │  (no events)        │
     └────────────────────┘

Load:  GET /users/{id} → JSON → hydrate aggregate
Save:  adapter inspects pending events → constructs API call(s)
       e.g., EmailChanged + NameChanged → PATCH /users/{id}
Truth: whatever the backend says
```

---

## What Changes Between Modes

| Concern | Event-Sourced (Local) | State-Based (Backend) |
|---|---|---|
| **Aggregate reconstruction** | Replay all events from stream | Hydrate from snapshot (JSON state) |
| **Saving** | Append events to local EventStore | Adapter constructs API call(s) from pending events |
| **Source of truth** | Local event stream | Backend |
| **Concurrency control** | Local version check (`ExpectedVersion`) | Adapter's concern — or none at all |
| **Event storage** | Client stores all events | Client may not store events at all |
| **Session interface** | `ContinuumSession` | `ContinuumSession` (identical) |
| **Workflow code** | Unchanged | Unchanged |
| **TransactionalRunner** | Unchanged | Unchanged |
| **CommitHandler** | Unchanged | Unchanged |

---

## What the Aggregate Needs

The aggregate is a **pure domain object**. It holds state and exposes mutation methods (generated `apply*` handlers). It does not track events — the session does that.

For the swappable store to work, the aggregate needs **two reconstruction paths**:

### Path 1: From Events (Event-Sourced Mode)

Used by EventSourcedStore. The creation factory + apply handlers that continuum already generates.

```dart
// Generated: creation factory
static User createFromUserRegistered(UserRegistered event) => User(
  name: event.name,
  email: event.email,
);

// Generated: apply handlers
void applyEmailChanged(EmailChanged event) {
  _email = event.newEmail;
}
```

### Path 2: From Backend Response (State-Based Mode)

Handled entirely by the user's `AggregatePersistenceAdapter`. The adapter fetches from the backend and constructs the aggregate however it wants — `fromJson`, a constructor, a builder, anything. The session never needs to know how hydration works because the adapter returns a fully constructed instance.

No codegen changes needed for this path.

---

## The Store Hierarchy

```
                    ┌─────────────────────────┐
                    │   ContinuumStore        │  ← abstract / interface
                    │   openSession()          │
                    └────────┬────────────────┘
                             │
              ┌──────────────┼──────────────────┐
              │              │                   │
   ┌──────────▼─────┐  ┌────▼──────────┐  ┌────▼────────────┐
   │ EventSourcingStore│ │ StateBasedStore│ │ HybridStore?    │
   │ (current)        │ │ (new)          │ │ (future: local  │
   │                  │ │                │ │  first + sync)  │
   └──────────────────┘ └────────────────┘ └─────────────────┘
```

Both produce `ContinuumSession` instances. The session implementations differ internally but expose the same interface. The `TransactionalRunner` accepts any `ContinuumStore` — it doesn't know or care which implementation is behind it.

---

## Session Implementations

### EventSourcedSession (current: `SessionImpl`, updated)

```
applyAsync(streamId, event):
  1. Already tracked? → apply event, add to pendingEvents, return aggregate
  2. Creation event? (factory exists) → create aggregate, track, return
  3. Mutation event? → loadAsync(streamId), apply, return

loadAsync(streamId):
  1. Check identity map — return cached aggregate if already loaded
  2. Load StoredEvents from EventStore
  3. Deserialize first event → AggregateFactoryRegistry.create()
  4. Deserialize remaining events → EventApplierRegistry.apply() each
  5. Track (aggregate, loadedVersion) in identity map
  6. Return aggregate

saveChangesAsync():
  1. Serialize pending events
  2. Append to EventStore with ExpectedVersion (OCC)
  3. On conflict → reload, re-apply pending, retry
  4. Return committed events list
```

### StateBasedSession (new concept)

```
applyAsync(streamId, event):
  1. Already tracked? → apply event, add to pendingEvents, return aggregate
  2. Creation event? (factory exists) → create aggregate, track, return
  3. Mutation event? → loadAsync(streamId), apply, return
  (IDENTICAL logic — shared base or shared method)

loadAsync(streamId):
  1. Check identity map — return cached aggregate if already loaded
  2. Call adapter.fetchAsync(streamId)
     → adapter calls backend API, hydrates aggregate
  3. Track aggregate in identity map
  4. Return aggregate

saveChangesAsync():
  1. For each stream with pending events:
     call adapter.persistAsync(streamId, aggregate, events)
     → adapter inspects events, constructs appropriate API call(s)
  2. Return committed events list
```

**Key insight**: `applyAsync()` is **identical** in both sessions. The domain event application logic is the same — only load and save differ. This suggests a shared base class or mixin for the common `applyAsync` logic.

---

## The Full Lifecycle — From Workflow to Persistence

```
┌────────────────────────────────────────────────────────────────┐
│  User's Workflow Code                                          │
│                                                                │
│  await runner.runAsync(() async {                              │
│    final session = TransactionalRunner.currentSession;         │
│    await session.applyAsync<User>(id, UserRegistered(...));    │
│    await session.applyAsync<User>(id, EmailChanged(...));      │
│    // runner calls session.saveChangesAsync() automatically    │
│    // runner calls commitHandler.onCommitAsync(events)         │
│  });                                                           │
└───────────────────────────────┬────────────────────────────────┘
                                │
                    ┌───────────▼───────────────┐
                    │  TransactionalRunner       │
                    │  1. openSession()          │
                    │  2. runZoned(action)       │
                    │  3. saveChangesAsync()     │
                    │  4. commitHandler.onCommit │
                    └───────────┬───────────────┘
                                │
                    ┌───────────▼───────────────┐
                    │  ContinuumSession          │
                    │  - applyAsync (apply event)│
                    │  - loadAsync (read-only)   │
                    │  - tracks _StreamState     │
                    │  - pending events per strm │
                    │  - saveChangesAsync (OCC)  │
                    └───────────┬───────────────┘
                                │
                    ┌───────────▼───────────────┐
                    │  ContinuumStore             │
                    │  (EventSourcingStore or     │
                    │   StateBasedStore)          │
                    └───────────────────────────┘
```

---

## How the Session Communicates with the Backend

### The Problem

Most backends don't expose a generic "apply these domain events" endpoint. Real-world backends have specific REST endpoints:

```
POST   /users                    → CreateUser
PATCH  /users/{id}/email         → ChangeEmail
POST   /users/{id}/deactivate    → SetInactive
```

Continuum cannot know or prescribe these endpoints. The session collects pending domain events, but `saveChangesAsync()` needs to somehow translate them into the correct backend calls. This raises two fundamental questions:

1. **Who decides what API call to make?** The user — they know their backend.
2. **How many calls per save?** It depends on the backend. Could be one call per event, one call for everything, or something in between.

### The Adapter Model

The user provides a **persistence adapter per aggregate type**. When `saveChangesAsync()` is called, the session hands the adapter everything it needs — and the adapter decides what to do.

```dart
/// User implements this per aggregate type.
///
/// The session calls [fetchAsync] to load the current state and
/// [persistAsync] to save changes. The adapter translates both
/// into whatever the backend expects.
///
/// Domain events are **not** sent to the backend as events. They
/// are a local mutation mechanism. The adapter receives them in
/// [persistAsync] so it can inspect what changed and construct
/// the appropriate API call(s) — a PATCH, a PUT, a batch command,
/// or whatever the backend's API requires.
abstract interface class AggregatePersistenceAdapter<TAggregate> {
  /// Fetches the current aggregate state from the backend.
  ///
  /// Returns the hydrated aggregate instance. The adapter calls
  /// the backend (e.g., `GET /users/{id}`), receives the response,
  /// and constructs the aggregate from it.
  Future<TAggregate> fetchAsync(StreamId streamId);

  /// Persists the changes that happened in this session.
  ///
  /// The adapter receives:
  /// - [streamId]: which aggregate stream
  /// - [aggregate]: the aggregate after all events have been applied
  /// - [pendingEvents]: the domain events that were applied locally
  ///
  /// The events are **not sent to the backend as events**. The
  /// adapter uses them to understand what changed and construct
  /// the appropriate backend call(s). For example:
  /// - `EmailChanged` + `NameChanged` → `PATCH /users/{id}`
  /// - `UserRegistered` (a creation event) → `POST /users`
  /// - Or send the full `aggregate.toJson()` and ignore events
  ///
  /// The adapter knows its own event types. If the first event is
  /// a creation event (e.g., `UserRegistered`), the adapter knows
  /// to call a create endpoint. No framework flag needed.
  ///
  /// **Atomicity contract**: This method must be all-or-nothing.
  /// Either all changes are persisted, or an exception is thrown
  /// and NO changes are committed.
  Future<void> persistAsync(
    StreamId streamId,
    TAggregate aggregate,
    List<ContinuumEvent> pendingEvents,
  );
}
```

### Why the Adapter Gets Both State AND Events

By providing both `aggregate` (final state) and `pendingEvents` (what changed), the adapter has full flexibility:

```dart
// Strategy A: Map each event to a separate API call
class UserApiAdapter implements AggregatePersistenceAdapter<User> {
  @override
  Future<User> fetchAsync(StreamId streamId) async {
    final response = await _api.getUser(streamId.value);
    return User.fromJson(response.body);
  }

  @override
  Future<void> persistAsync(
    StreamId streamId,
    User aggregate,
    List<ContinuumEvent> pendingEvents,
  ) async {
    for (final event in pendingEvents) {
      switch (event) {
        case UserRegistered():
          await _api.createUser(aggregate.toJson());
        case EmailChanged(:final newEmail):
          await _api.changeEmail(streamId.value, newEmail);
        case UserDeactivated():
          await _api.deactivate(streamId.value);
      }
    }
  }
}
```

```dart
// Strategy B: Ignore events, send the whole updated state
class UserApiAdapter implements AggregatePersistenceAdapter<User> {
  @override
  Future<User> fetchAsync(StreamId streamId) async {
    final response = await _api.getUser(streamId.value);
    return User.fromJson(response.body);
  }

  @override
  Future<void> persistAsync(
    StreamId streamId,
    User aggregate,
    List<ContinuumEvent> pendingEvents,
  ) async {
    if (pendingEvents.first is UserRegistered) {
      await _api.createUser(aggregate.toJson());
    } else {
      await _api.updateUser(streamId.value, aggregate.toJson());
    }
  }
}
```

```dart
// Strategy C: Combine events into a single update command
class UserApiAdapter implements AggregatePersistenceAdapter<User> {
  @override
  Future<User> fetchAsync(StreamId streamId) async {
    final response = await _api.getUser(streamId.value);
    return User.fromJson(response.body);
  }

  @override
  Future<void> persistAsync(
    StreamId streamId,
    User aggregate,
    List<ContinuumEvent> pendingEvents,
  ) async {
    // Construct a single update payload from multiple events:
    // EmailChanged + NameChanged → { "email": "...", "name": "..." }
    final changes = <String, dynamic>{};
    for (final event in pendingEvents) {
      switch (event) {
        case EmailChanged(:final newEmail):
          changes['email'] = newEmail;
        case NameChanged(:final newName):
          changes['name'] = newName;
      }
    }
    await _api.patchUser(streamId.value, changes);
  }
}
```

**Continuum doesn't care which strategy the user picks.** The session just calls `persistAsync()` and either it succeeds or it throws.

### What About Atomicity Across Multiple Streams?

In event-sourced mode, `AtomicEventStore` allows multi-stream atomic saves. In state-based mode, the backend decides atomicity. The adapter could:

- Call multiple endpoints (no atomicity guarantee — accept eventual consistency)
- Call a single batch endpoint (if the backend provides one)
- Use a saga/compensation pattern for cross-aggregate consistency

This is the user's domain — continuum shouldn't pretend to solve distributed transactions.

---

## Aggregate Hydration — Snapshot Reconstruction

### The Question

How does the state-based session reconstruct an aggregate from backend data?

### The Answer: User-Provided Factory

The session needs to construct an aggregate from backend response data. The simplest approach: the user provides the factory function. No special `fromSnapshot` — just use what the aggregate already has (`fromJson`, a constructor, whatever fits).

```dart
/// Registered per aggregate type in the StateBasedStore.
///
/// The user provides:
/// - how to fetch + hydrate (the adapter)
/// - how to apply events (already in EventApplierRegistry from codegen)
```

The `AggregatePersistenceAdapter.fetchAsync()` returns just the aggregate — meaning the adapter handles hydration. The adapter knows the backend's response shape and how to construct the aggregate from it:

```dart
class UserApiAdapter implements AggregatePersistenceAdapter<User> {
  @override
  Future<User> fetchAsync(StreamId streamId) async {
    final response = await _api.getUser(streamId.value);
    return User.fromJson(response.body);
  }
}
```

No codegen changes needed. No `fromSnapshot`. No forced version field. The adapter encapsulates transport and hydration — because only the user knows their backend's response format.

---

## Read Models / Projections — Post-Commit Side Effects

### Local Read Models Still Matter

Even when the backend is the source of truth, the client often needs local derived state:

- Table view sort/filter state derived from aggregate changes
- Notification badges counting unseen items
- Search indexes for offline-capable search
- Cached computed values (e.g., "waveform generation progress")

These are **client-side projections** — they react to domain events and update local read models.

### How It Works (Updated)

Projections are now a **commit handler**, not session-internal logic. After `saveChangesAsync()` returns committed events, the `TransactionalRunner` hands them to the `CommitHandler`, which can include a projection executor:

```
TransactionalRunner.runAsync()
  1. action() — user applies events via session
  2. session.saveChangesAsync() → persist events → return committed list
  3. commitHandler.onCommitAsync(committedEvents)
     → ProjectionCommitHandler → InlineProjectionExecutor
     → EventBusCommitHandler → publish to listeners
     → AnalyticsCommitHandler → track events
```

This means projections work identically in both modes. The event flow is:

```
Event-Sourced:  applyAsync → save to EventStore    → commitHandler → project
State-Based:    applyAsync → save to Backend        → commitHandler → project
```

**Projections are a post-commit concern, independent of the persistence strategy, and independent of the session.**

---

## The Swapping Experience (User's Perspective)

### Step 1: Start with Local Event Sourcing

```dart
// main.dart
final store = EventSourcingStore(
  eventStore: SembastEventStore(database),
  aggregates: [$AudioFile, $Playlist],
);

final runner = TransactionalRunner(
  store,
  commitHandler: CompositeCommitHandler([
    ProjectionCommitHandler(projectionExecutor),
    StreamCommitHandler(eventStreamController),
  ]),
);

// Inject `runner` into your DI container
```

### Step 2: Switch to Backend

```dart
// main.dart — ONLY the store changes
final store = StateBasedStore(
  adapters: {
    AudioFile: AudioFileApiAdapter(httpClient),
    Playlist: PlaylistApiAdapter(httpClient),
  },
  eventAppliers: [$AudioFile, $Playlist],  // still needed for applyAsync()
);

final runner = TransactionalRunner(
  store,
  commitHandler: CompositeCommitHandler([
    ProjectionCommitHandler(projectionExecutor),  // still works
    StreamCommitHandler(eventStreamController),   // still works
  ]),
);

// Inject `runner` — same type, same runAsync() method
```

### Workflows — Zero Changes

```dart
// execute_waveform_generation_workflow.dart — UNTOUCHED
class ExecuteWaveformGenerationWorkflow {
  final TransactionalRunner _runner;

  Future<void> call({required StreamId audioFileId, ...}) async {
    await _runner.runAsync(() async {
      final session = TransactionalRunner.currentSession;
      await session.applyAsync<AudioFile>(
        audioFileId,
        WaveformGenerationStarted(...),
      );
      // ... generate waveform ...
      await session.applyAsync<AudioFile>(
        audioFileId,
        WaveformGenerated(...),
      );
      // No manual save — runner handles it
      // No manual publish — commitHandler handles it
    });
  }
}
```

---

## Concurrency Control — A Layered Analysis

### The Core Problem

Multiple parallel workflows can load and mutate the same aggregate concurrently. Without protection, the second save silently overwrites the first (last-write-wins).

### How Zone-Based Sessions Solve Same-Isolate Concurrency

Each `TransactionalRunner.runAsync()` creates a new Zone with its own session. Two concurrent async workflows on the same isolate get separate sessions with separate `_StreamState` maps. There is no shared mutable state between them.

```
Workflow A (Zone A, Session A)      Workflow B (Zone B, Session B)
──────────────────────────          ──────────────────────────
applyAsync(User, EmailChanged)
  → loads User (version 3)
  → applies event in-memory
                                    applyAsync(User, NameChanged)
                                      → loads User (version 3)
                                      → applies event in-memory
saveChangesAsync (expect v3) → v4 ✓
                                    saveChangesAsync (expect v3) → CONFLICT
                                      → reload User (version 4)
                                      → re-apply NameChanged
                                      → retry (expect v4) → v5 ✓
```

The conflict is detected at the store level (OCC). The retry is handled inside the session. The runner and the user's workflow never see the retry — it's transparent.

### How Event-Sourced Mode Solves This Today

Each session tracks a `loadedVersion` per stream. On save, the `EventStore` checks: "is the stream still at the version I expect?" If someone else appended events in between, `ConcurrencyException` is thrown. The session then reloads, re-applies pending events on the fresh state, and retries.

The conflict detection happens at the **store level** (the EventStore rejects the write). The retry logic happens at the **session level** (reload + re-apply). This is a clean separation.

### State-Based Mode: No Event-Sourced Concurrency

In state-based mode, there is no local event stream — so there is no `ExpectedVersion` to check. The backend owns the state. Concurrency control, if any, is entirely the adapter's concern.

The adapter may choose to:
- Use ETags or version fields if the backend supports them
- Implement optimistic locking internally
- Do nothing and accept last-write-wins

This is a private implementation detail of the adapter. The session doesn't know or care. It just calls `persistAsync()` — if the adapter throws, the session handles the exception. If it succeeds, the events are considered committed.

### What If the Backend Doesn't Support OCC?

If the backend has no version/ETag mechanism, the adapter can't detect conflicts. Two options:

1. **Accept last-write-wins** — the adapter never throws `ConcurrencyException`, both saves succeed, and the last one overwrites. This is a conscious trade-off the user makes.
2. **Client-side guard** — continuum provides an optional mechanism to prevent concurrent access to the same stream on the client side.

### Client-Side Stream Guard (Optional Layer)

Even when the backend supports OCC, unnecessary conflicts are wasteful — each conflict means a failed HTTP round-trip, a reload, and a retry. When you know multiple workflows on the **same client** are hitting the same aggregate, you can avoid the conflict entirely.

**Approach: Per-stream semaphore at the store level.**

The guard serializes the `persistAsync()` call per stream. Loading and applying events are **not** locked — those are read operations or in-memory mutations that don't affect other sessions. The lock is acquired only when `saveChangesAsync()` begins persisting a stream, and released after it completes (or fails).

```dart
// Inside StateBasedStore (or any ContinuumStore)
class StateBasedStore implements ContinuumStore {
  final Map<StreamId, Completer<void>> _streamLocks = {};

  /// Serializes persistAsync calls per stream.
  /// Multiple sessions can load the same aggregate concurrently,
  /// but only one can persist at a time.
  Future<void> withStreamLock(StreamId streamId, Future<void> Function() action) async {
    // Wait for any in-flight persist to complete
    while (_streamLocks.containsKey(streamId)) {
      await _streamLocks[streamId]!.future;
    }
    final completer = Completer<void>();
    _streamLocks[streamId] = completer;
    try {
      await action();
    } finally {
      _streamLocks.remove(streamId);
      completer.complete();
    }
  }
}
```

Two sessions can both load and apply events to the same aggregate concurrently. When they both try to save, the second one waits until the first persist completes. This serializes the write path without blocking reads.

### Trade-Offs of Client-Side Locking

| Aspect | Without Lock (OCC Only) | With Stream Guard |
|---|---|---|
| **Wasted round-trips** | Conflict → fail → reload → retry | No conflicts on same client |
| **Latency** | Parallel, but retry adds latency on conflict | Sequential saves for same stream |
| **Read parallelism** | Parallel | Parallel (lock is save-only) |
| **Cross-device conflicts** | Handled by backend OCC | NOT handled — still need backend OCC |
| **Deadlocks** | Impossible | Not possible — lock is per-stream, acquired only during save |
| **Complexity** | Simple | Lock management, timeout, cleanup on error |
| **Backend without OCC** | Last-write-wins (silent data loss) | Safe on same client, still unsafe cross-device |

### Why Lock-on-Save Avoids Deadlocks

Because the lock is only held during `persistAsync()` (not during load or apply), the classic cross-stream deadlock cannot occur:

```
Session A: applyAsync(User1) ✓, applyAsync(User2) ✓    ← no locks held yet
Session B: applyAsync(User2) ✓, applyAsync(User1) ✓    ← no locks held yet

Session A: saveChangesAsync() → lock User1 → persist → lock User2 → persist → release all
Session B: saveChangesAsync() → lock User2 → WAITS (held by A) → ... → proceeds after A releases
```

Each session acquires all its stream locks at the start of `saveChangesAsync()`, persists, and releases. If two sessions need the same streams, one waits for the other's full save to complete. No interleaved lock acquisition → no deadlock.

**Note**: If saves are per-stream (each stream locked and persisted independently), there is still a theoretical interleaving risk. Mitigate by acquiring all needed stream locks at the start of `saveChangesAsync()` in a deterministic order (e.g., sorted by `StreamId`) before persisting any of them.

### Recommendation: Three Levels of Concurrency Control

```
Level 0: No protection
  → Last-write-wins. User accepts data loss risk.
  → Suitable for single-workflow apps or idempotent operations.

Level 1: Server-side OCC (default)
  → Adapter throws ConcurrencyException on version mismatch.
  → Session retries automatically (reload + re-apply).
  → Works for both local EventStore and backend APIs.
  → Handles cross-device conflicts.
  → This is what EventSourcingStore does today.

Level 2: Client-side stream guard + server-side OCC
  → Optional per-stream semaphore prevents same-client conflicts.
  → Serializes saves (not loads) for the same stream.
  → Reduces wasted round-trips when parallel workflows are common.
  → Server-side OCC remains the safety net for cross-device.
  → Adds complexity (lock management, timeouts).
  → Should be opt-in, not default.
```

**Level 1 should be the baseline for `StateBasedStore`.** The adapter contract should require throwing `ConcurrencyException` on version mismatch — it's the adapter's job to detect it (via HTTP 409, ETag mismatch, version field comparison, etc.).

**Level 2 can be added later** as an optional wrapper or store decorator:

```dart
// Future API — opt-in
final store = GuardedStore(
  inner: StateBasedStore(adapters: {...}),
  lockTimeout: Duration(seconds: 5),
);
```

This keeps the core simple and lets users who need client-side guards add them without changing the session interface or workflow code.

---

## What Needs to Happen in the Package

### Phase 1: Core Refactoring

1. **Session owns events exclusively.** Ensure no code path relies on `AggregateRoot.recordEvent()` / `pullEvents()` / `clearEvents()`. (Already the case — formalize it.)
2. **Replace `startStream` + `append` with `applyAsync` on `ContinuumSession`.** The unified method auto-detects creation vs. mutation by probing the factory registry.
3. **`saveChangesAsync` returns `List<ContinuumEvent>`.** The committed events list enables the runner and commit handlers.
4. **Extract `ContinuumStore` interface** from `EventSourcingStore` with a single method: `ContinuumSession openSession()`.

### Phase 2: TransactionalRunner + CommitHandler

5. **Create `TransactionalRunner`** — Zone-based ambient session management with auto-commit.
6. **Define `CommitHandler` interface** — pluggable post-commit event processing.
7. **Move `InlineProjectionExecutor` out of the session** — it becomes a `CommitHandler` implementation, no longer session-internal.

### Phase 3: State-Based Store (Future)

8. **Define `AggregatePersistenceAdapter<T>`** — the user-implemented interface for backend fetch + persist per aggregate type. The adapter inspects pending domain events to construct whatever API call(s) the backend expects.
9. **Create `StateBasedStore`** that implements `ContinuumStore`, takes adapters per aggregate, and produces `StateBasedSession` instances.
10. **Keep `EventApplierRegistry` shared** — both session types use it for `applyAsync()`.
11. **Keep concurrency retry logic shared** — the retry loop (reload → re-apply → retry) is the same for both session types; only the reload/persist mechanisms differ.

---

## Open Questions — Proposed Solutions

### 1. Creation Detection in `applyAsync` — What If No Factory Exists?

**The problem**: `applyAsync` probes the `AggregateFactoryRegistry` to decide whether the event is a creation event. If no factory is found, it assumes mutation and calls `loadAsync`. But what if the stream doesn't exist either? The user passed a mutation event for a non-existent stream.

**Answer**: `loadAsync` throws `StreamNotFoundException`. This is correct — the user made a programming error (applying a mutation event to a stream that doesn't exist). The exception is clear and actionable.

**Edge case — creation event for an already-existing stream**: If the user calls `applyAsync` with a creation event but the stream is already tracked (loaded earlier in the same session), the event hits the "already tracked" fast path and is applied as a normal mutation. This might be unexpected. Two options:

- **Option A (strict)**: If the event is a creation event AND the stream is already tracked, throw an `InvalidOperationException`. Creation events are only valid for new streams.
- **Option B (lenient)**: Treat it like any other event — if the aggregate has an `apply*` handler for it, apply it. If not, throw `UnsupportedEventException`.

**Recommendation: Option A (strict).** Creation events have semantic meaning — they create a new aggregate. Applying a creation event to an existing aggregate is almost certainly a bug. Failing loudly prevents subtle state corruption.

```dart
// Inside applyAsync, before the "already tracked" fast path:
if (existingState != null) {
  final isCreationEvent = _aggregateFactories.getFactory<TAggregate>(
    TAggregate, event.runtimeType,
  ) != null;

  if (isCreationEvent) {
    throw InvalidOperationException(
      'Cannot apply creation event ${event.runtimeType} to already-tracked '
      'stream ${streamId.value}. Creation events are only valid for new streams.',
    );
  }

  _append(streamId, event);
  return existingState.aggregate as TAggregate;
}
```

---

### 2. `applyAsync` in State-Based Mode — Creation Without Events

**The problem**: In state-based mode, the backend stores state, not events. When creating a new aggregate, the creation event goes through the factory locally to build the aggregate, but on save there is no event stream to append to — the adapter needs to call the backend's create endpoint.

**Solution**: Identical to event-sourced mode on the session side. `applyAsync` creates the aggregate locally via the creation factory, records the creation event as pending. On `saveChangesAsync()`, the adapter receives the aggregate and the pending events. The adapter sees a creation event (e.g., `UserRegistered`) in the events list and knows to call a create endpoint.

```dart
class UserApiAdapter implements AggregatePersistenceAdapter<User> {
  @override
  Future<User> fetchAsync(StreamId streamId) async {
    final response = await _api.getUser(streamId.value);
    return User.fromJson(response.body);
  }

  @override
  Future<void> persistAsync(
    StreamId streamId,
    User aggregate,
    List<ContinuumEvent> pendingEvents,
  ) async {
    if (pendingEvents.first is UserRegistered) {
      await _api.createUser(aggregate.toJson());
    } else {
      await _api.updateUser(streamId.value, aggregate.toJson());
    }
  }
}
```

No changes to `ContinuumSession` interface needed. The adapter distinguishes create vs. update by inspecting the events it already receives.

---

### 3. Error Mapping — The Adapter Exception Contract

**The problem**: The adapter talks to a backend that can fail in many ways. The session needs to know what to do with each kind of failure.

**Proposed exception hierarchy**:

```dart
/// Base for all adapter-originated failures.
/// The session catches these and handles them distinctly.
sealed class AdapterException implements Exception {}

/// The backend reported a version/ETag mismatch.
/// Session response: reload + re-apply + retry (up to maxRetries).
final class ConcurrencyException extends AdapterException {
  final StreamId streamId;
  ConcurrencyException({required this.streamId});
}

/// The requested stream does not exist on the backend.
/// Session response: rethrow to caller (cannot retry).
final class StreamNotFoundException extends AdapterException {
  final StreamId streamId;
  StreamNotFoundException({required this.streamId});
}

/// A transient error (network timeout, 503, rate limit).
/// Session response: rethrow to caller. The caller decides whether
/// to retry the entire workflow.
final class TransientAdapterException extends AdapterException {
  final String message;
  final Object? cause;
  TransientAdapterException(this.message, {this.cause});
}
```

**Why sealed**: The session can exhaustively switch on error types. No surprise subclasses slip through.

**What the session does with each**:

| Exception | Session Behavior |
|---|---|
| `ConcurrencyException` | Re-fetch via adapter → re-apply pending → retry (same as event-sourced mode) |
| `StreamNotFoundException` | Rethrow immediately — caller handles |
| `TransientAdapterException` | Rethrow immediately — caller can retry the whole workflow |
| `PermanentAdapterException` | Rethrow immediately — something is fundamentally wrong |

**Note**: `ConcurrencyException` and `StreamNotFoundException` already exist in continuum today. The new ones are `TransientAdapterException` and `PermanentAdapterException` for backend-specific failures. Alternatively, these could be a single `AdapterException` with a `retryable` flag, but explicit types are clearer.

**What about unknown exceptions?** If the adapter throws something outside this hierarchy (e.g., a raw `HttpException`), the session lets it propagate unchanged. The session only catches what it knows how to handle. This follows the principle: don't catch what you can't act on.

---

### 4. Multi-Aggregate Saves — No Cross-Aggregate Atomicity in State-Based Mode

**The problem**: A session might have pending events for `User` and `Playlist`. In event-sourced mode, `AtomicEventStore` saves both atomically. In state-based mode, these are separate API calls — what if one succeeds and the other fails?

**Option A: Accept non-atomicity (recommended for v1)**

In state-based mode, `saveChangesAsync()` persists each stream independently via its adapter. If stream A succeeds and stream B fails, stream A's changes are committed.

This matches how most REST APIs work in practice. Cross-resource atomicity over HTTP is rare. Backends that need it implement sagas/compensation internally.

**What the caller gets on partial failure**: The exception should include information about which streams succeeded. This lets the caller decide how to compensate.

```dart
/// Thrown when some streams saved but others failed.
final class PartialSaveException implements Exception {
  final List<StreamId> savedStreams;
  final List<StreamId> failedStreams;
  final Object cause;
}
```

**Verdict: Option A for v1. Accept non-atomicity, report partial failures clearly.**

---

### 5. Does `saveChangesAsync()` Send One Call or Many?

**This is already resolved by the adapter design, but worth documenting explicitly.**

The session calls `adapter.persistAsync()` once per stream per save attempt. Within that single call, the adapter receives ALL pending events for that stream and decides the wire strategy:

```
Session perspective (per stream):
  1 call to persistAsync(streamId, aggregate, events) → adapter decides

Adapter can:
  A) Send 1 API call with final state
  B) Send 1 API call with all N events as batch
  C) Send N API calls (one per event)
  D) Any combination
```

The adapter contract says: `persistAsync` either succeeds completely or throws. If it throws, the session assumes nothing was committed for that stream. If the adapter uses multiple API calls internally, it's responsible for rollback/compensation if one fails mid-way.

---

### 6. Nesting `runAsync` — Nested Transactions

**The problem**: What if a workflow calls `runAsync` inside another `runAsync`?

```dart
await runner.runAsync(() async {
  // Session A is ambient
  await runner.runAsync(() async {
    // Session B is ambient — different session!
    // Changes in B are committed independently of A
  });
  // Session A is ambient again
});
```

**Answer**: Each `runAsync` creates a new Zone with a new session. Nested calls get independent sessions. This is **not** a nested transaction — it's two independent transactions.

**Why this is correct**: Dart Zones nest naturally. The inner `runZoned` creates a child Zone that shadows the parent's session with a new one. When the inner Zone completes, the parent's session is restored. There is no shared state between the two sessions.

**If the user wants a shared session**: They should pass the session explicitly or access `TransactionalRunner.currentSession` from within the same `runAsync` scope. Composing workflows within a single transaction is done by calling them inside the same `runAsync`:

```dart
await runner.runAsync(() async {
  final session = TransactionalRunner.currentSession;
  await workflowA(session);  // shares the session
  await workflowB(session);  // shares the session
  // One commit at the end
});
```

**Recommendation**: Document that `runAsync` always creates an independent transaction. Nesting creates separate transactions. If atomicity across workflows is needed, compose them within a single `runAsync`.

---

### 7. Manual Session Usage — Opt-Out of the Runner

**The problem**: Some users may not want the `TransactionalRunner` pattern. They want to manage sessions manually (e.g., in tests, or in simple scripts).

**Answer**: The `ContinuumStore.openSession()` method is still public. Users can always do:

```dart
final session = store.openSession();
await session.applyAsync<User>(userId, EmailChanged(newEmail: '...'));
final committedEvents = await session.saveChangesAsync();
// Manually handle committedEvents
```

The `TransactionalRunner` is a convenience, not a requirement. The session is self-contained — it doesn't depend on the runner. The runner just automates the open → commit → publish lifecycle.

This is important for testability: tests can create sessions directly without needing a runner or commit handler.
