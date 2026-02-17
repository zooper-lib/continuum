## Context

The continuum package provides event-sourced persistence for domain aggregates in Dart. The current architecture has `EventSourcingStore` as the only store implementation producing `SessionImpl` instances that implement `ContinuumSession`. Sessions expose `startStream`, `append`, and `saveChangesAsync` (returning `void`), and internally wire `InlineProjectionExecutor` for post-save projection execution.

This design is tightly coupled to event sourcing as the sole persistence strategy and exposes persistence concerns in the public API (distinguishing creation from mutation). The proposal calls for a unified mutation API, a transactional lifecycle boundary, decoupled post-commit handling, and the foundation for swappable persistence strategies.

Reference architecture: `doc/draft/session-store-architecture.md`.

## Goals / Non-Goals

**Goals:**

- Unify `startStream` + `append` into a single `applyAsync` method that auto-detects creation vs. mutation
- Change `saveChangesAsync` to return `Future<List<ContinuumEvent>>` for committed event reporting
- Introduce `ContinuumStore` as an abstract interface that `EventSourcingStore` implements
- Add `TransactionalRunner` with zone-based ambient session management and auto-commit
- Add `CommitHandler` interface for pluggable post-commit side effects
- Decouple `InlineProjectionExecutor` from `SessionImpl` — projections move to a commit handler
- Add `EventApplicationMode` (eager/deferred) as a store-level configuration
- Define `AggregatePersistenceAdapter<T>` interface for future state-based persistence

**Non-Goals:**

- Implementing `StateBasedStore` or `StateBasedSession` — adapter interface is defined but not wired into a session implementation yet
- Client-side stream guards (per-stream semaphores) — deferred to a future change
- Hybrid store (local-first + backend sync) — future concern
- Changes to code generation — the existing `AggregateFactoryRegistry` and `EventApplierRegistry` are structurally compatible with `applyAsync`
- Changes to `EventStore`, `AtomicEventStore`, or `ProjectionEventStore` interfaces
- Changes to store implementation packages (`continuum_store_hive`, `continuum_store_memory`, `continuum_store_sembast`)

## Decisions

### 1. `applyAsync` auto-detects creation vs. mutation via factory registry probe

**Decision**: When `applyAsync<T>(streamId, event)` is called, the method checks three paths in order:

1. **Already tracked** — stream is in the session's identity map → apply event directly (fast path)
2. **Creation event** — `AggregateFactoryRegistry.getFactory<T>(T, event.runtimeType)` returns non-null → create aggregate from factory, begin tracking
3. **Mutation event** — no factory found → call `loadAsync(streamId)` to hydrate from store, then apply

**Rationale**: The factory registry already exists and maps `(AggregateType, EventType)` pairs to creation factories. Probing it is O(1) (two map lookups) and deterministic. No annotation changes, no codegen changes. The registry is the single source of truth for "is this a creation event?"

**Strict creation guard**: If a creation event is applied to an already-tracked stream, `applyAsync` throws `InvalidOperationException`. Creation events semantically mean "this aggregate starts here" — applying one to an existing aggregate is a programming error.

**Alternative considered**: Adding an `isCreation` flag to `ContinuumEvent`. Rejected — it pushes persistence semantics into the domain event, violating the principle that events are pure domain facts.

### 2. `saveChangesAsync` returns committed events

**Decision**: Change the return type from `Future<void>` to `Future<List<ContinuumEvent>>`. The list contains all events from all streams persisted in this save call, ordered by stream. After return, all `pendingEvents` lists are cleared.

**Rationale**: The `TransactionalRunner` needs the committed events to pass to `CommitHandler.onCommitAsync`. Without a return value, the runner would need to inspect session internals, breaking encapsulation. Manual session users also benefit — they can log, publish, or act on committed events.

**Impact on retry**: On concurrency retry, the returned list contains the same logical events re-applied on a fresher aggregate. The events are the user's original events — retry is transparent.

### 3. `ContinuumStore` as an abstract interface extracted from `EventSourcingStore`

**Decision**: Introduce `ContinuumStore` as an abstract interface with a single method:

```dart
abstract interface class ContinuumStore {
  ContinuumSession openSession();
}
```

`EventSourcingStore` implements `ContinuumStore`. Future `StateBasedStore` will implement the same interface.

**Rationale**: The `TransactionalRunner` accepts a `ContinuumStore` — it doesn't know or care which implementation is behind it. This enables swapping stores without changing workflow code.

**Alternative considered**: Making `EventSourcingStore` itself abstract and having concrete subclasses. Rejected — the store hierarchy should be flat (interface + implementations), not an inheritance tree.

### 4. `TransactionalRunner` uses Dart Zones for ambient session scoping

**Decision**: `TransactionalRunner.runAsync` creates a new `Zone` via `runZoned`, places a fresh `ContinuumSession` in the zone's values, executes the user's action, auto-commits via `saveChangesAsync`, and then calls `CommitHandler.onCommitAsync` with the committed events.

`TransactionalRunner.currentSession` retrieves the ambient session from `Zone.current[_key]`. Throws `StateError` if called outside `runAsync`.

**Rationale**: Zones provide ambient scoping without parameter threading — nested async calls, helper functions, and composed workflows all see the same session. Each `runAsync` creates an isolated zone with its own session — two concurrent calls get separate sessions with no shared state.

**Nesting behavior**: Nested `runAsync` calls create independent transactions (separate zones, separate sessions). This is intentional — true nested transactions add complexity without clear benefit. Users who want shared sessions should compose workflows within a single `runAsync`.

**Alternative considered**: `InheritedWidget`-style scoping. Rejected — this is a Dart package, not Flutter-specific. Zones work in all Dart environments.

### 5. `CommitHandler` as a simple callback interface

**Decision**: Define `CommitHandler` as an abstract interface with a single method:

```dart
abstract interface class CommitHandler {
  Future<void> onCommitAsync(List<ContinuumEvent> events);
}
```

The runner calls `onCommitAsync` after a successful save. If no handler is configured, nothing is published.

**Rationale**: Continuum is a persistence library, not a messaging library. The handler pattern lets users inject whatever publish mechanism they use. The handler receives events (not aggregates) because publishing should depend on what happened, not on aggregate state.

**After-persist semantics**: The handler is called only after `saveChangesAsync` succeeds. If save fails, the handler is never called. If the handler throws, the committed events are still persisted — no rollback. The exception propagates to the caller.

**Composite pattern**: A `CompositeCommitHandler` (list of handlers executed in order) is a natural extension but is user-space code, not framework-provided.

### 6. Projections decouple from `SessionImpl` into a `CommitHandler`

**Decision**: Remove the `InlineProjectionExecutor?` parameter from `SessionImpl`. Inline projections are instead wired as a `CommitHandler` on the `TransactionalRunner`.

**Rationale**: The session's responsibility is persistence and concurrency — not downstream side effects. Projections, event bus publishing, and analytics are all post-commit concerns that belong at the runner level, not inside the session.

**Migration path**: Users currently passing `ProjectionRegistry` to `EventSourcingStore` will instead create a projection-based `CommitHandler` and pass it to the `TransactionalRunner`. The projection execution behavior is identical — only the wiring surface changes.

**Impact**: `EventSourcingStore`'s factory constructor no longer accepts `ProjectionRegistry?`. The `InlineProjectionExecutor` class remains — it's just consumed differently (as a commit handler implementation rather than a session dependency).

### 7. `EventApplicationMode` is a store-level configuration defaulting to eager

**Decision**: Add an `EventApplicationMode` enum with `eager` and `deferred` variants. The mode is configured on the store (e.g., `EventSourcingStore(applicationMode: EventApplicationMode.eager)`) and propagated to sessions.

- **Eager** (default): Events mutate the in-memory aggregate immediately when `applyAsync` is called. The workflow sees post-event state.
- **Deferred**: Events are recorded but not applied until `saveChangesAsync` succeeds. The workflow sees pre-event state throughout the transaction.

**Rationale**: Most event-sourcing workflows need to read post-event state (check invariants, compute derived values, conditionally apply further events). Eager is the natural default. Deferred is opt-in for users who want stricter separation between intent and committed state — particularly useful when the backend is the authority.

**Implementation**: A single branch in the internal `_append` method. In eager mode, `_applyEventToAggregate` is called immediately. In deferred mode, events are only recorded; `saveChangesAsync` applies them all before serialization.

### 8. `AggregatePersistenceAdapter<T>` defined now, wired later

**Decision**: Define the `AggregatePersistenceAdapter<T>` interface in this change but do not implement `StateBasedStore` or `StateBasedSession`. The interface has two methods:

- `fetchAsync(StreamId)` — returns a hydrated aggregate from the backend
- `persistAsync(StreamId, TAggregate, List<ContinuumEvent>)` — persists changes using whatever backend strategy the adapter chooses

**Rationale**: Defining the interface now validates the design and ensures `ContinuumSession`/`ContinuumStore` are shaped correctly for both persistence modes. Implementing the state-based session is a separate change with its own complexity (error mapping, partial save handling, concurrency control delegation).

**Adapter receives both state and events**: The adapter gets the final aggregate (for state-based persistence) AND the pending events (for event-driven API calls). This gives the adapter full flexibility: send the whole state, map events to API calls, or combine both.

## Risks / Trade-offs

**[Breaking API]** → `startStream`/`append` removal and `saveChangesAsync` return type change break all existing call sites. Mitigation: these are straightforward mechanical migrations. The example project and tests serve as the migration reference.

**[Projection wiring change]** → Users passing `ProjectionRegistry` to `EventSourcingStore` must rewire to a commit handler on the runner. Mitigation: the `InlineProjectionExecutor` class remains unchanged — only its consumer changes. Provide a `ProjectionCommitHandler` adapter to minimize migration effort.

**[Zone overhead]** → Dart Zones add minimal overhead per `runAsync` call (zone allocation + map lookup for ambient session). Risk is negligible — zones are lightweight and widely used in production Dart code.

**[Deferred mode complexity]** → Deferred event application adds a code path where `saveChangesAsync` must apply all pending events before serialization. Risk: subtle bugs if the application order doesn't match the recording order. Mitigation: pending events are an ordered list per stream — apply in insertion order.

**[Adapter interface stability]** → The `AggregatePersistenceAdapter` interface is defined without an implementation to validate it against. Risk: the interface may need revision when `StateBasedStore` is actually built. Mitigation: the interface is minimal (two methods) and modeled after real-world adapter patterns. Changes, if needed, will be small.

**[No cross-aggregate atomicity in state-based mode]** → When `StateBasedStore` is implemented, multi-stream saves will not be atomic (each adapter call is independent). Risk: partial failures leave inconsistent state. Mitigation: this matches real-world REST API behavior. `PartialSaveException` (future) will report which streams succeeded/failed.
