# Session & Store Architecture — Swappable Persistence

## The Core Principle

Aggregates **always** mutate through domain events, regardless of how they are persisted. The workflow code never changes — only the store wiring does.

```dart
// This code is IDENTICAL whether backed by local ES, backend API, or anything else
final session = store.openSession();
final user = await session.loadAsync<User>(userId);
session.append(userId, EmailChanged(newEmail: 'new@example.com'));
await session.saveChangesAsync();
```

**The Session is the stable contract. The Store is the swappable strategy.**

---

## Two Persistence Modes

### Mode 1: Event-Sourced (Local)

The event stream is the source of truth. Aggregate state is derived by replaying events.

```
┌──────────────────────────────────────────────┐
│               Workflow                        │
│  session.loadAsync() → append() → save()     │
└──────────────┬───────────────────────────────┘
               │
     ┌─────────▼──────────┐
     │  EventSourcedStore  │  ← current implementation
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

The backend is the source of truth. It sends the **current aggregate state** (a snapshot). The client still mutates via events locally, but persistence means "send changes to the backend" — not "store events locally."

```
┌──────────────────────────────────────────────┐
│               Workflow                        │
│  session.loadAsync() → append() → save()     │
│  (IDENTICAL code — no changes)               │
└──────────────┬───────────────────────────────┘
               │
     ┌─────────▼──────────┐
     │   StateBasedStore   │  ← new concept
     │   .openSession()    │
     └─────────┬──────────┘
               │
     ┌─────────▼──────────┐
     │   Backend / API     │
     │  stores state (or   │
     │  its own events)    │
     └────────────────────┘

Load:  GET /aggregates/{id} → JSON snapshot → hydrate aggregate
Save:  POST /aggregates/{id}/events → send pending events to backend
Truth: whatever the backend says
```

---

## What Changes Between Modes

| Concern | Event-Sourced (Local) | State-Based (Backend) |
|---|---|---|
| **Aggregate reconstruction** | Replay all events from stream | Hydrate from snapshot (JSON state) |
| **Saving** | Append events to local EventStore | Send events (or command) to backend API |
| **Source of truth** | Local event stream | Backend |
| **Concurrency control** | Local version check (`ExpectedVersion`) | Backend version check (ETag, version field, etc.) |
| **Event storage** | Client stores all events | Client may not store events at all |
| **Session interface** | `ContinuumSession` | `ContinuumSession` (identical) |
| **Workflow code** | Unchanged | Unchanged |

---

## What the Aggregate Needs

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

Both produce `ContinuumSession` instances. The session implementations differ internally but expose the same interface.

---

## Session Implementations

### EventSourcedSession (current: `SessionImpl`)

```
loadAsync(streamId):
  1. Check identity map — return cached aggregate if already loaded
  2. Load StoredEvents from EventStore
  3. Deserialize first event → AggregateFactoryRegistry.create()
  4. Deserialize remaining events → EventApplierRegistry.apply() each
  5. Track (aggregate, loadedVersion) in identity map
  6. Return aggregate

append(streamId, event):
  1. Apply event to in-memory aggregate via EventApplierRegistry
  2. Add to pendingEvents list

saveChangesAsync():
  1. Serialize pending events
  2. Append to EventStore with ExpectedVersion (OCC)
  3. On conflict → reload, replay pending, retry
  4. Run inline projections
```

### StateBasedSession (new concept)

```
loadAsync(streamId):
  1. Check identity map — return cached aggregate if already loaded
  2. Fetch current state from backend (GET)
  3. Hydrate aggregate from snapshot (fromSnapshot)
  4. Track (aggregate, serverVersion) in identity map
  5. Return aggregate

append(streamId, event):
  1. Apply event to in-memory aggregate via EventApplierRegistry
     (same as event-sourced! domain logic is identical)
  2. Add to pendingEvents list

saveChangesAsync():
  1. Send pending events to backend (POST)
     — backend applies them, returns new version (or new state)
  2. On conflict (409) → re-fetch state, re-apply pending, retry
  3. Update local aggregate with server-confirmed state
```

**Key insight**: `append()` is **identical** in both sessions. The domain event is applied to the in-memory aggregate the same way. Only load and save differ.

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
/// The session calls [persistAsync] with everything it knows:
/// the stream identity, the pending events, and the aggregate
/// in its final state (after all events were applied in-memory).
///
/// The adapter translates this into whatever the backend expects.
abstract interface class AggregatePersistenceAdapter<TAggregate> {
  /// Fetches the current aggregate state from the backend.
  ///
  /// Returns the aggregate instance and its version (for OCC).
  Future<VersionedAggregate<TAggregate>> fetchAsync(StreamId streamId);

  /// Persists the changes that happened in this session.
  ///
  /// The adapter receives:
  /// - [streamId]: which aggregate stream
  /// - [aggregate]: the aggregate after all events have been applied
  /// - [pendingEvents]: the list of domain events that were appended
  /// - [expectedVersion]: the version at load time (for OCC)
  ///
  /// The adapter decides:
  /// - Whether to send one API call or many
  /// - Whether to send events, commands, or the full state
  /// - How to handle errors and map them to ConcurrencyException
  ///
  /// Returns the new version after the backend confirms persistence.
  Future<int> persistAsync(
    StreamId streamId,
    TAggregate aggregate,
    List<ContinuumEvent> pendingEvents,
    ExpectedVersion expectedVersion,
  );
}
```

### Why the Adapter Gets Both State AND Events

By providing both `aggregate` (final state) and `pendingEvents` (what changed), the adapter has full flexibility:

```dart
// Strategy A: Send each event as a separate API call
class UserApiAdapter implements AggregatePersistenceAdapter<User> {
  @override
  Future<int> persistAsync(
    StreamId streamId,
    User aggregate,
    List<ContinuumEvent> pendingEvents,
    ExpectedVersion expectedVersion,
  ) async {
    for (final event in pendingEvents) {
      switch (event) {
        case EmailChanged(:final newEmail):
          await _api.changeEmail(streamId.value, newEmail);
        case UserDeactivated():
          await _api.deactivate(streamId.value);
      }
    }
    return expectedVersion.value + pendingEvents.length;
  }
}
```

```dart
// Strategy B: Send the whole updated state in one call
class UserApiAdapter implements AggregatePersistenceAdapter<User> {
  @override
  Future<int> persistAsync(
    StreamId streamId,
    User aggregate,
    List<ContinuumEvent> pendingEvents,
    ExpectedVersion expectedVersion,
  ) async {
    final response = await _api.updateUser(
      streamId.value,
      aggregate.toJson(),
      ifMatch: expectedVersion.value,
    );
    return response.newVersion;
  }
}
```

```dart
// Strategy C: Send a batch command with all event data
class UserApiAdapter implements AggregatePersistenceAdapter<User> {
  @override
  Future<int> persistAsync(
    StreamId streamId,
    User aggregate,
    List<ContinuumEvent> pendingEvents,
    ExpectedVersion expectedVersion,
  ) async {
    final commands = pendingEvents.map(_toCommand).toList();
    final response = await _api.batch(streamId.value, commands);
    return response.newVersion;
  }
}
```

**Continuum doesn't care which strategy the user picks.** The session just calls `persistAsync()` and either gets a new version back or catches an exception.

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

The `AggregatePersistenceAdapter.fetchAsync()` already returns a `TAggregate` — meaning the adapter itself handles hydration. The adapter knows the backend's response shape and how to construct the aggregate from it:

```dart
class UserApiAdapter implements AggregatePersistenceAdapter<User> {
  @override
  Future<VersionedAggregate<User>> fetchAsync(StreamId streamId) async {
    final response = await _api.getUser(streamId.value);
    final user = User.fromJson(response.body);  // or any construction logic
    return VersionedAggregate(user, version: response.version);
  }
}
```

No codegen changes needed. No `fromSnapshot`. The adapter encapsulates both transport AND hydration — because only the user knows their backend's response format.

---

## Read Models / Projections in State-Based Mode

### Local Read Models Still Matter

Even when the backend is the source of truth, the client often needs local derived state:

- Table view sort/filter state derived from aggregate changes
- Notification badges counting unseen items
- Search indexes for offline-capable search
- Cached computed values (e.g., "waveform generation progress")

These are **client-side projections** — they react to domain events and update local read models.

### How It Works

In both modes, `append()` applies events to the in-memory aggregate. The session knows which events were applied. After `saveChangesAsync()` succeeds, the session can still emit those events to local projections:

```
saveChangesAsync()
  1. Persist via adapter (backend call)
  2. On success → feed events to InlineProjectionExecutor (same as event-sourced mode)
```

This means projections work identically in both modes. The event flow is:

```
Event-Sourced:  append → apply → save to EventStore → project
State-Based:    append → apply → save to Backend    → project (same events, same projections)
```

**Projections are a client-side concern, independent of the persistence strategy.**

---

## The Swapping Experience (User's Perspective)

### Step 1: Start with Local Event Sourcing

```dart
// main.dart
final store = EventSourcingStore(
  eventStore: SembastEventStore(database),
  aggregates: [$AudioFile, $Playlist],
);

// Inject `store` into your DI container
```

### Step 2: Switch to Backend

```dart
// main.dart — ONLY this file changes
final store = StateBasedStore(
  adapters: {
    AudioFile: AudioFileApiAdapter(httpClient),
    Playlist: PlaylistApiAdapter(httpClient),
  },
  eventAppliers: [$AudioFile, $Playlist],  // still needed for append()
  projections: projectionRegistry,          // still works — local read models
);

// Inject `store` — same type (ContinuumStore), same openSession() method
```

### Workflows — Zero Changes

```dart
// execute_waveform_generation_workflow.dart — UNTOUCHED
class ExecuteWaveformGenerationWorkflow {
  final ContinuumStore _store;  // ← works with any store implementation

  Future<Either<Error, void>> call({required StreamId audioFileId, ...}) async {
    final session = _store.openSession();
    final audioFile = await session.loadAsync<AudioFile>(audioFileId);
    session.append(audioFileId, WaveformGenerationStarted(...));
    // ... generate waveform ...
    session.append(audioFileId, WaveformGenerated(...));
    await session.saveChangesAsync();
    return const Right(null);
  }
}
```

---

## Concurrency Control — A Layered Analysis

### The Core Problem

Multiple parallel workflows can load and mutate the same aggregate concurrently. Without protection, the second save silently overwrites the first (last-write-wins).

### How Event-Sourced Mode Solves This Today

Each session tracks a `loadedVersion` per stream. On save, the `EventStore` checks: "is the stream still at the version I expect?" If someone else appended events in between, `ConcurrencyException` is thrown. The session then reloads, re-applies pending events on the fresh state, and retries.

```
Workflow A                          Workflow B
─────────                          ─────────
load User (version 3)
                                   load User (version 3)
append EmailChanged
saveChanges (expect v3) → v4 ✓
                                   append NameChanged
                                   saveChanges (expect v3) → CONFLICT
                                   reload User (version 4)
                                   re-apply NameChanged
                                   saveChanges (expect v4) → v5 ✓
```

The conflict detection happens at the **store level** (the EventStore rejects the write). The retry logic happens at the **session level** (reload + re-apply). This is a clean separation.

### State-Based Mode: Same Pattern, Different Layers

The same OCC pattern works for backends — but the layers shift:

```
Workflow A                          Workflow B
─────────                          ─────────
load User (adapter.fetch → v3)
                                   load User (adapter.fetch → v3)
append EmailChanged
saveChanges
  → adapter.persist(expect v3)
  → backend accepts → v4 ✓
                                   append NameChanged
                                   saveChanges
                                     → adapter.persist(expect v3)
                                     → backend rejects (409) → ConcurrencyException
                                   reload User (adapter.fetch → v4)
                                   re-apply NameChanged
                                   saveChanges
                                     → adapter.persist(expect v4)
                                     → backend accepts → v5 ✓
```

**The session retry logic is identical.** The only difference is who detects the conflict:
- Event-sourced: the local `EventStore` implementation
- State-based: the `AggregatePersistenceAdapter` (which gets a 409 from the backend and throws `ConcurrencyException`)

### But What If the Backend Doesn't Support OCC?

If the backend has no version/ETag mechanism, the adapter can't detect conflicts. Two options:

1. **Accept last-write-wins** — the adapter never throws `ConcurrencyException`, both saves succeed, and the last one overwrites. This is a conscious trade-off the user makes.
2. **Client-side guard** — continuum provides an optional mechanism to prevent concurrent access to the same stream on the client side.

### Client-Side Stream Guard (Optional Layer)

Even when the backend supports OCC, unnecessary conflicts are wasteful — each conflict means a failed HTTP round-trip, a reload, and a retry. When you know multiple workflows on the **same client** are hitting the same aggregate, you can avoid the conflict entirely.

**Approach: Per-stream semaphore at the store level.**

```dart
// Inside StateBasedStore (or any ContinuumStore)
class StateBasedStore implements ContinuumStore {
  final Map<StreamId, Completer<void>> _streamLocks = {};

  @override
  ContinuumSession openSession() {
    return StateBasedSession(
      // ...
      acquireLock: _acquireStreamLock,
      releaseLock: _releaseStreamLock,
    );
  }
}
```

The session acquires a lock on first `loadAsync()` for a given stream, and releases it after `saveChangesAsync()` (or `discardAll()`). A second session trying to load the same stream **waits** until the first session completes.

```
Workflow A                          Workflow B
─────────                          ─────────
load User → acquires lock
                                   load User → WAITS (lock held)
append EmailChanged
saveChanges → success
release lock
                                   load User → acquires lock (gets v4)
                                   append NameChanged
                                   saveChanges → success (v5)
                                   release lock
```

### Trade-Offs of Client-Side Locking

| Aspect | Without Lock (OCC Only) | With Stream Guard |
|---|---|---|
| **Wasted round-trips** | Conflict → fail → reload → retry | No conflicts on same client |
| **Latency** | Parallel, but retry adds latency on conflict | Sequential for same stream, no retry needed |
| **Cross-device conflicts** | Handled by backend OCC | NOT handled — still need backend OCC |
| **Deadlocks** | Impossible | Possible if workflow A locks stream X then Y, workflow B locks Y then X |
| **Complexity** | Simple | Lock management, timeout, cleanup on error |
| **Backend without OCC** | Last-write-wins (silent data loss) | Safe on same client, still unsafe cross-device |

### Deadlock Risk

If a single session loads multiple aggregates, and two sessions load them in different order, you get a classic deadlock:

```
Session A: load(User1) ✓, load(User2) → WAITS (held by B)
Session B: load(User2) ✓, load(User1) → WAITS (held by A)
→ DEADLOCK
```

**Mitigations:**
- **Lock timeout**: If a lock isn't acquired within N seconds, throw a `StreamLockTimeoutException`. The workflow fails and can be retried.
- **Ordered acquisition**: Document that multi-stream sessions should load streams in a deterministic order (e.g., sorted by StreamId). This is a convention, not enforced by the framework.
- **Lock on save, not on load**: Instead of locking when `loadAsync()` is called, lock only when `saveChangesAsync()` begins. This narrows the window but doesn't prevent conflicts — it just serializes the persist step.

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
  → Reduces wasted round-trips when parallel workflows are common.
  → Server-side OCC remains the safety net for cross-device.
  → Adds complexity (timeouts, deadlock risk).
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

1. **Extract a `ContinuumStore` interface** from `EventSourcingStore` with a single method: `ContinuumSession openSession()`.
2. **Define `AggregatePersistenceAdapter<T>`** — the user-implemented interface for backend fetch + persist per aggregate type. Contract: must throw `ConcurrencyException` on version mismatch.
3. **Create `StateBasedStore`** that implements `ContinuumStore`, takes adapters per aggregate, and produces `StateBasedSession` instances.
4. **Keep `EventApplierRegistry` shared** — both session types use it for `append()`.
5. **Keep projections working** — both session types feed events to `InlineProjectionExecutor` after successful save.
6. **Keep concurrency retry logic shared** — the retry loop (reload → re-apply → retry) is the same for both session types; only the reload/persist mechanisms differ.

---

## Open Questions — Proposed Solutions

### 1. `startStream` in State-Based Mode

**The problem**: In event-sourced mode, `startStream()` creates the aggregate locally via the creation factory, sets `loadedVersion = -1`, and the creation event becomes the first pending event. On save, `ExpectedVersion.noStream` ensures no duplicate streams. In state-based mode, the backend is the source of truth — how does creation work?

**Option A: Defer to `saveChangesAsync()` (recommended)**

`startStream()` behaves identically to event-sourced mode: creates the aggregate locally via the creation factory, records the creation event as pending, sets `loadedVersion = -1`. On `saveChangesAsync()`, the adapter receives the aggregate, the pending events (starting with the creation event), and `ExpectedVersion.noStream`.

The adapter checks `expectedVersion == noStream` to decide: this is a create, not an update.

```dart
class UserApiAdapter implements AggregatePersistenceAdapter<User> {
  @override
  Future<int> persistAsync(
    StreamId streamId,
    User aggregate,
    List<ContinuumEvent> pendingEvents,
    ExpectedVersion expectedVersion,
  ) async {
    if (expectedVersion == ExpectedVersion.noStream) {
      // Create — POST
      final response = await _api.createUser(aggregate.toJson());
      return response.version;
    } else {
      // Update — PATCH/PUT
      final response = await _api.updateUser(streamId.value, ...);
      return response.version;
    }
  }
}
```

**Why this works**:
- Unit-of-work pattern stays consistent: nothing hits the network until `saveChangesAsync()`.
- The adapter already receives `ExpectedVersion` — it naturally distinguishes create from update.
- No new interface methods or session behavior needed.
- If `saveChangesAsync()` is never called (workflow fails early), no orphan resources on the backend.

**Why not call the backend immediately** (Option B):
- Breaks the unit-of-work pattern — you'd have a partially committed session.
- If the workflow fails after creation but before save, you have an orphan aggregate on the backend.
- Requires rollback/compensation logic, which adds significant complexity.

**Verdict: Option A. No changes to `ContinuumSession` interface.**

---

### 2. Error Mapping — The Adapter Exception Contract

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

/// An unrecoverable error (400 bad request, 403 forbidden, serialization failure).
/// Session response: rethrow to caller (cannot retry).
final class PermanentAdapterException extends AdapterException {
  final String message;
  final Object? cause;
  PermanentAdapterException(this.message, {this.cause});
}
```

**Why sealed**: The session can exhaustively switch on error types. No surprise subclasses slip through.

**What the session does with each**:

| Exception | Session Behavior |
|---|---|
| `ConcurrencyException` | Reload via adapter → re-apply pending → retry (same as event-sourced mode) |
| `StreamNotFoundException` | Rethrow immediately — caller handles |
| `TransientAdapterException` | Rethrow immediately — caller can retry the whole workflow |
| `PermanentAdapterException` | Rethrow immediately — something is fundamentally wrong |

**Note**: `ConcurrencyException` and `StreamNotFoundException` already exist in continuum today. The new ones are `TransientAdapterException` and `PermanentAdapterException` for backend-specific failures. Alternatively, these could be a single `AdapterException` with a `retryable` flag, but explicit types are clearer.

**What about unknown exceptions?** If the adapter throws something outside this hierarchy (e.g., a raw `HttpException`), the session lets it propagate unchanged. The session only catches what it knows how to handle. This follows the principle: don't catch what you can't act on.

---

### 3. Multi-Aggregate Saves — No Cross-Aggregate Atomicity

**The problem**: A session might have pending events for `User` and `Playlist`. In event-sourced mode, `AtomicEventStore` saves both atomically. In state-based mode, these are separate API calls — what if one succeeds and the other fails?

**Option A: Accept non-atomicity (recommended for v1)**

In state-based mode, `saveChangesAsync()` persists each stream independently via its adapter. If stream A succeeds and stream B fails, stream A's changes are committed.

This matches how most REST APIs work in practice. Cross-resource atomicity over HTTP is rare. Backends that need it implement sagas/compensation internally.

The session behavior on partial failure:

```
saveChangesAsync():
  for each stream with pending events:
    try:
      adapter.persistAsync(...)
      mark stream as saved (clear pending, update version)
    catch ConcurrencyException:
      mark this stream for retry
    catch other:
      stop — rethrow with context about what succeeded and what didn't

  if any streams need retry:
    reload those streams via adapter
    re-apply pending events
    retry (up to maxRetries)
```

**What the caller gets on partial failure**: The exception should include information about which streams succeeded. This lets the caller decide how to compensate.

```dart
/// Thrown when some streams saved but others failed.
final class PartialSaveException implements Exception {
  final List<StreamId> savedStreams;
  final List<StreamId> failedStreams;
  final Object cause;
}
```

**Option B: Batch adapter (future consideration)**

For users whose backend supports batch/transaction endpoints:

```dart
/// Optional. If the store's adapter registry includes a BatchAdapter,
/// multi-stream saves go through it instead of individual adapters.
abstract interface class BatchPersistenceAdapter {
  Future<Map<StreamId, int>> persistBatchAsync(
    Map<StreamId, AggregateChanges> changes,
  );
}
```

This is a niche requirement and can be added later without breaking changes.

**Verdict: Option A for v1. Accept non-atomicity, report partial failures clearly. Option B as future opt-in.**

---

### 4. Does `saveChangesAsync()` Send One Call or Many?

**This is already resolved by the adapter design, but worth documenting explicitly.**

The session calls `adapter.persistAsync()` once per stream per save attempt. Within that single call, the adapter receives ALL pending events for that stream and decides the wire strategy:

```
Session perspective (per stream):
  1 call to persistAsync() → receives N pending events → adapter decides

Adapter can:
  A) Send 1 API call with final state
  B) Send 1 API call with all N events as batch
  C) Send N API calls (one per event)
  D) Any combination
```

**But what about the retry scenario?**

When the session retries (after `ConcurrencyException`):
1. It reloads the stream via `adapter.fetchAsync()`
2. It re-applies all pending events on the fresh aggregate
3. It calls `adapter.persistAsync()` again with the same pending events

The adapter receives the same event list on retry, but the aggregate is now in a different state (freshly loaded + re-applied). If the adapter uses "send final state" (Strategy A), the state reflects the merged result. If it uses "send events" (Strategy B/C), the events are the same but the `expectedVersion` is updated.

**Edge case — event-per-API-call (Strategy C) and partial success**:

If the adapter sends one API call per event and the 2nd of 3 calls fails, the adapter has a problem: events 1 was committed but 2 wasn't. The adapter must handle this internally — continuum can't help because it has no visibility into the adapter's internal strategy. The adapter contract says: `persistAsync` either succeeds completely or throws. If it throws, the session assumes nothing was committed for that stream.

**Recommendation**: Document in the adapter contract that `persistAsync` must be all-or-nothing from the session's perspective. If the adapter uses multiple API calls internally, it's responsible for rollback/compensation if one fails mid-way. This is a strong contract but necessary — otherwise the retry logic can't reason about state.

```dart
abstract interface class AggregatePersistenceAdapter<TAggregate> {
  /// ...
  ///
  /// **Atomicity contract**: This method must be all-or-nothing.
  /// Either all changes are persisted and the new version is returned,
  /// or an exception is thrown and NO changes are committed.
  ///
  /// If the adapter uses multiple API calls internally, it is responsible
  /// for rollback if one fails mid-way.
  Future<int> persistAsync(
    StreamId streamId,
    TAggregate aggregate,
    List<ContinuumEvent> pendingEvents,
    ExpectedVersion expectedVersion,
  );
}
```
