## Context

Continuum's persistence architecture is built on the `ContinuumStore` → `ContinuumSession` abstraction. Today, `EventSourcingStore` is the sole `ContinuumStore` implementation — it produces `SessionImpl` instances that load aggregates by replaying events from an `EventStore` and save by appending serialized events.

The `AggregatePersistenceAdapter<T>` interface already exists (defined during Phase 2 for design validation). `SessionImpl` contains ~630 lines, roughly half of which (`applyAsync` 3-path detection, `_append` with eager/deferred modes, `_StreamState` identity map, `discardStream`/`discardAll`) is persistence-agnostic. The other half (`loadAsync` via event replay, `saveChangesAsync` via `EventStore.appendEventsAsync`, `_reconstructAggregate`, `_reloadStreamsWithPendingEventsAsync`) is event-sourcing-specific.

The existing exception types (`ConcurrencyException`, `StreamNotFoundException`, `InvalidOperationException`, `UnsupportedEventException`, `InvalidCreationEventException`, `UnknownEventTypeException`) cover event-sourcing concerns. Backend adapters need additional exception types for transient/permanent failures and partial multi-stream save failures.

## Goals / Non-Goals

**Goals:**

- Implement `StateBasedStore` and `StateBasedSession` so users can back aggregates with a backend API instead of a local event store
- Ensure workflow code (`applyAsync`, `loadAsync`, `saveChangesAsync`, `TransactionalRunner`, `CommitHandler`) works identically with both store types — zero changes when swapping
- Extract shared session logic so `SessionImpl` and `StateBasedSession` reuse the same `applyAsync` / event-tracking / creation-detection code without duplication
- Support concurrency retry when the adapter throws `ConcurrencyException` (reload via `fetchAsync` → re-apply pending → retry)
- Report partial multi-stream save failures clearly via `PartialSaveException`
- Add adapter-specific exception types (`TransientAdapterException`, `PermanentAdapterException`) the session propagates without catching

**Non-Goals:**

- Client-side stream guard (Level 2 concurrency) — deferred to a future change as an optional decorator
- Hybrid store (local-first + backend sync) — separate future concern
- Cross-aggregate atomicity in state-based mode — adapters persist per stream; no distributed transaction support
- Changes to the `AggregatePersistenceAdapter<T>` interface — it is already defined and will not change
- Changes to code generation — both session types use the existing `EventApplierRegistry` and `AggregateFactoryRegistry`
- Changes to existing `EventSourcingStore` or `SessionImpl` public behavior

## Decisions

### 1. Extract shared session logic into a base class

**Decision:** Extract a `SessionBase` abstract class from `SessionImpl` containing all persistence-agnostic logic.

**What moves to `SessionBase`:**
- `_StreamState` tracking (`Map<StreamId, _StreamState>` identity map)
- `applyAsync` 3-path detection (tracked → creation → mutation/load)
- `_append` with eager/deferred branching
- `_applyEventByRuntimeType` event dispatch
- `_createAndTrack` aggregate creation from factory
- Strict creation guard (creation event on tracked stream → `InvalidOperationException`)
- `_isExplicitType` helper
- `discardStream` / `discardAll`
- `AggregateFactoryRegistry` and `EventApplierRegistry` field references
- `EventApplicationMode` field and support

**What stays abstract (implemented by subclasses):**
- `loadAsync` — `SessionImpl` replays from `EventStore`; `StateBasedSession` calls `adapter.fetchAsync`
- `saveChangesAsync` — `SessionImpl` appends to `EventStore`; `StateBasedSession` calls `adapter.persistAsync` per stream
- `reloadAndReapplyAsync` (or equivalent) — `SessionImpl` re-reads events from store; `StateBasedSession` re-fetches via adapter

**Alternatives considered:**
- *Mixin instead of base class:* Mixins can't hold final fields or constructors, making initialization awkward. A base class is more natural.
- *Delegation/composition:* Wrapping a shared `SessionCore` object adds indirection without benefit — both session types need the same fields and the same `applyAsync` entry point.
- *Leave duplicated:* Copying 300+ lines between two session classes creates a maintenance burden and risks divergence.

**Rationale:** The base class captures the domain-event-application invariant — "events mutate aggregates identically regardless of persistence strategy" — as shared code. Subclasses only define how to load and save.

### 2. `StateBasedStore` construction API

**Decision:** `StateBasedStore` takes a `Map<Type, AggregatePersistenceAdapter<Object>>` (keyed by aggregate type) and a `List<GeneratedAggregate>` (for the event applier and factory registries).

```dart
final store = StateBasedStore(
  adapters: {
    User: UserApiAdapter(httpClient),
    Playlist: PlaylistApiAdapter(httpClient),
  },
  aggregates: [$User, $Playlist],
  applicationMode: EventApplicationMode.deferred, // optional, defaults to eager
);
```

**Rationale:** Mirrors `EventSourcingStore`'s constructor pattern (`aggregates` param for registries). The adapter map replaces the `eventStore` param. `applicationMode` remains configurable — deferred mode is particularly useful here since the backend is the authority.

**Alternatives considered:**
- *Typed adapter map via generics:* Not possible in Dart — a `Map<Type, AggregatePersistenceAdapter<T>>` can't hold mixed generic values. The map uses `Object` and the session casts internally (same pattern as `EventApplierRegistry`).
- *Adapters inside `GeneratedAggregate`:* Would require codegen changes and couples generated code to user-provided infrastructure. Rejected.

### 3. `StateBasedSession.loadAsync` — adapter delegation

**Decision:** `loadAsync` checks the identity map first (shared behavior in `SessionBase`). On cache miss, it resolves the adapter by aggregate type and calls `adapter.fetchAsync(streamId)`. The returned aggregate is tracked in `_streams` with `loadedVersion: 0` (since there's no event-stream version concept).

**Why `loadedVersion: 0`:** The state-based session doesn't track event-stream versions. The value `0` is a sentinel meaning "loaded from backend, version unknown." Concurrency detection is the adapter's responsibility (ETags, version fields, etc.), not the session's.

**Alternatives considered:**
- *`loadedVersion: -1`:* Already used to mean "new stream, never persisted." Using `-1` for backend-loaded aggregates would conflate creation and load semantics.
- *Optional version field:* Adding a nullable version field to `_StreamState` adds complexity for a concern the session doesn't own. The adapter handles versioning internally.

### 4. `StateBasedSession.saveChangesAsync` — per-stream persist with partial failure

**Decision:** `saveChangesAsync` iterates streams with pending events and calls `adapter.persistAsync(streamId, aggregate, pendingEvents)` for each. If all succeed, returns all committed events. If some succeed and others fail, throws `PartialSaveException` with the lists of saved and failed stream IDs.

**Persist order:** Streams are persisted independently. No ordering guarantee between streams. Each `persistAsync` call is all-or-nothing for its own stream.

**Concurrency retry:** If `persistAsync` throws `ConcurrencyException`, the session re-fetches via `adapter.fetchAsync`, re-applies pending events, and retries — identical to `SessionImpl`'s retry loop. The `maxRetries` parameter applies per stream.

**Deferred mode:** If `EventApplicationMode.deferred`, all pending events are applied to the in-memory aggregate before calling `persistAsync`, so the adapter receives the post-event state. Same as `SessionImpl`.

**Alternatives considered:**
- *Parallel persist calls (`Future.wait`):* Could improve latency but complicates partial-failure handling and makes retry ordering non-deterministic. Sequential is simpler and correct.
- *Stop on first failure (no partial):* Simpler, but committed streams can't be uncommitted. Reporting partial success is more honest.

### 5. Adapter resolution by aggregate type

**Decision:** The session resolves the adapter for a given stream by looking up the aggregate type (tracked in `_StreamState.aggregateType`) in the adapter map. If no adapter is registered for that type, it throws `InvalidOperationException`.

**When the type is known:** 
- On `loadAsync<TAggregate>(...)` — the generic parameter `TAggregate` provides the type.
- On `applyAsync<TAggregate>(...)` with a creation event — the factory registry provides the aggregate type.
- On `saveChangesAsync` — each `_StreamState` already tracks `aggregateType`.

**Rationale:** This is the same pattern `SessionImpl` uses for resolving event appliers and factories — lookup by `Type` key in a map. No new patterns introduced.

### 6. New exception types

**Decision:** Add three new exception types:

- `TransientAdapterException` — network timeouts, 503s, rate limits. The session rethrows immediately; the caller decides whether to retry the whole workflow.
- `PermanentAdapterException` — 400s, validation errors, authorization failures. The session rethrows immediately; something is fundamentally wrong.
- `PartialSaveException` — thrown by `StateBasedSession.saveChangesAsync` when some streams persisted successfully but others failed. Contains `savedStreams`, `failedStreams`, and `cause`.

**These are NOT sealed under a common `AdapterException` base.** Reason: `ConcurrencyException` and `StreamNotFoundException` already exist as standalone types. Making them subtypes of a sealed `AdapterException` would be a breaking change. Instead, the new types stand alone, and the session catches them individually:

| Exception | Session behavior |
|---|---|
| `ConcurrencyException` | Reload → re-apply → retry (existing behavior) |
| `StreamNotFoundException` | Rethrow (existing behavior) |
| `TransientAdapterException` | Rethrow — caller retries workflow |
| `PermanentAdapterException` | Rethrow — caller handles |
| Any other exception | Rethrow unchanged |

**Alternatives considered:**
- *Sealed `AdapterException` hierarchy:* Would require `ConcurrencyException` and `StreamNotFoundException` to extend it — breaking change. Rejected for v1.
- *Single `AdapterException` with `retryable` flag:* Less type-safe, harder to catch selectively. Explicit types are clearer.

### 7. No `EventSerializer` dependency

**Decision:** `StateBasedSession` does NOT depend on `EventSerializer` or `EventSerializerRegistry`. Events are never serialized to JSON in state-based mode — they exist only in-memory as domain objects. The adapter receives live `ContinuumEvent` instances, not serialized payloads.

**Rationale:** Serialization is an event-store concern. In state-based mode, the adapter translates domain events into API calls — it works with typed Dart objects, not JSON.

**Consequence:** `StateBasedStore` does NOT require `EventSerializerRegistry` entries in `GeneratedAggregate`. However, the `GeneratedAggregate` bundles always contain a serializer registry because code generation produces them. The store simply ignores it.

## Risks / Trade-offs

**[Risk] `SessionBase` extraction may break `SessionImpl` behavior** → The extraction is a refactor of existing working code. Mitigation: run all existing `SessionImpl` tests after extraction to verify no regressions. The public API (`ContinuumSession`) does not change.

**[Risk] Partial save leaves session in inconsistent state** → After a `PartialSaveException`, some streams are committed (pending events cleared) and others are not (pending events retained). The session is technically usable but the caller must decide how to proceed. Mitigation: document that `PartialSaveException` means the session should typically be abandoned. The `TransactionalRunner` will rethrow, abandoning the session.

**[Risk] Adapter type map uses `Object` — runtime cast errors** → If the adapter map has the wrong type registered (e.g., `User` type mapped to a `PlaylistApiAdapter`), the cast inside `persistAsync` will fail at runtime. Mitigation: the store constructor validates adapter registrations at construction time where possible, and runtime errors surface immediately on first use.

**[Trade-off] No cross-aggregate atomicity** → Accepted for v1. Most REST backends don't support cross-resource transactions. Users who need atomicity implement it in their adapter (batch endpoint, saga pattern). Document this clearly.

**[Trade-off] Sequential stream persist vs. parallel** → Sequential is simpler and avoids complex partial-failure interleaving. Latency cost is the sum of all `persistAsync` calls. For most use cases (1–2 streams per save), this is acceptable. Can be optimized later if profiling shows it matters.
