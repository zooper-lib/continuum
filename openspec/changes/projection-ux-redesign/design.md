## Context

The framework has three package layers:

| Layer | Package | Relevant types |
|-------|---------|----------------|
| L0 | `continuum` | `Operation`, `StreamId`, `ProjectionBase`, `SingleStreamProjection`, `MultiStreamProjection`, `InlineProjectionExecutor`, `ProjectionRegistry`, `ReadModelStore` |
| L1 | `continuum_uow` | `Session`, `SessionBase`, `CommitHandler`, `CompositeCommitHandler`, `TransactionalRunner`, `SessionStore` |
| L2 | `continuum_event_sourcing` | `SessionImpl`, `AsyncProjectionExecutor`, `StoredEvent`, `EventStore` |

Dependency direction: L2 → L1 → L0.

Today, `Session.saveChangesAsync()` returns `Future<List<Operation>>`. Inside `saveChangesAsync`, both `SessionImpl` (event-sourcing) and `StateBasedSession` iterate `trackedEntities` — a `Map<StreamId, TrackedEntity>` — meaning the `StreamId ↔ Operation` pairing exists in memory but is discarded when the method flattens operations into a list.

`TransactionalRunner` passes this flat list to `CommitHandler.onCommitAsync(List<Operation>)`, which in turn reaches `InlineProjectionExecutor.executeAsync(List<Operation>)`. Because `Operation` is a bare marker interface, `SingleStreamProjection` must implement `extractKey(Operation)` to recover the `StreamId` from event payload data — information the session already had.

The async executor (`AsyncProjectionExecutor`) receives `List<StoredEvent>` which does carry `StreamId`, yet still calls `projection.extractKey(domainEvent)` on the bare operation rather than using it.

## Goals / Non-Goals

**Goals:**

- Preserve the `StreamId ↔ Operation` association through the entire post-commit pipeline so projections receive stream context without manual key extraction.
- Eliminate `extractKey` from `SingleStreamProjection` — the executor supplies the key from the commit batch.
- Ship framework-provided commit handlers (`ProjectionCommitHandler`, `AsyncProjectionCommitHandler`) so users never write adapter classes.
- Extend the code generator to emit projection registration glue, reducing per-projection manual wiring.

**Non-Goals:**

- Making `Operation` itself carry identity or metadata. `Operation` stays a bare marker interface.
- Designing a persistent async queue abstraction. The `AsyncProjectionCommitHandler` schedules processing but does not define delivery guarantees.
- Changing the `@Projection` annotation shape or the generated dispatch mixin. Existing handler method generation is unaffected.
- Rebuilding the `AsyncProjectionExecutor` in `continuum_event_sourcing`. It continues to work over `StoredEvent`, but the async commit handler bridges `CommitBatch` into it.

## Decisions

### D1: `CommitBatch` and `CommittedOperation` live in L0 (`continuum`)

**Choice:** Place `CommitBatch` and `CommittedOperation` in `continuum` (L0).

**Rationale:** Both L0 types (`InlineProjectionExecutor`) and L1 types (`CommitHandler`, `TransactionalRunner`) need to reference `CommitBatch`. Since L1 depends on L0, placing these types in L0 satisfies both without introducing a circular dependency. Placing them in L1 would prevent the L0 projection executor from accepting them.

**Alternatives considered:**
- *Place in L1*: Would require `InlineProjectionExecutor` (L0) to accept a different type and introduce an adapter. Defeats the purpose.
- *New shared package*: Over-engineering for two small value types.

### D2: `CommitBatch` shape

**Choice:**

```
CommitBatch
├── List<CommittedEntry> entries
│   ├── StreamId streamId
│   ├── List<CommittedOperation> operations
│   │   ├── Operation operation
│   │   ├── int? streamVersion
│   │   └── int? globalSequence
```

`CommitBatch` groups operations by stream via `CommittedEntry`. Each `CommittedEntry` carries one `StreamId` and its ordered list of `CommittedOperation`s.

**Rationale:** Grouping by stream (rather than a flat list of `{StreamId, Operation}` pairs) reflects how sessions actually work — they track entities per stream. It makes iteration by stream natural for single-stream projections and avoids redundant `StreamId` repetition.

Optional fields (`streamVersion`, `globalSequence`) support event-sourcing stores without burdening state-based stores.

**Alternatives considered:**
- *Flat list of `(StreamId, Operation)` pairs*: Simpler, but loses the grouping that sessions naturally produce and forces projections to re-group by stream. The current `trackedEntities` map already provides per-stream grouping — preserving it is free.
- *Include `DateTime committedAt` on `CommitBatch`*: Omitted. Timestamps are store-specific metadata. Consumers that need them can read `globalSequence` or store-level metadata.
- *Include `Map<String, Object?> metadata` on `CommittedOperation`*: Omitted from the initial design. Can be added later as a non-breaking change if use cases emerge. Keeping the type minimal reduces cognitive overhead.

### D3: `Session.saveChangesAsync()` returns `CommitBatch`

**Choice:** Change the return type from `Future<List<Operation>>` to `Future<CommitBatch>`.

**Rationale:** `saveChangesAsync` is the single point where operations transition from "pending" to "committed". Both `SessionImpl` and `StateBasedSession` already iterate `trackedEntities` (a `Map<StreamId, TrackedEntity>`) during persistence. Building a `CommitBatch` from this map is trivial — instead of flattening into `List<Operation>`, collect `CommittedEntry` per stream.

`TransactionalRunner` then passes the `CommitBatch` directly to `CommitHandler.onCommitAsync(CommitBatch)` — no intermediate transformation.

**Alternatives considered:**
- *Keep `List<Operation>` return, build `CommitBatch` in `TransactionalRunner`*: `TransactionalRunner` does not have access to `StreamId` per operation. It would need a separate lookup or the session would need an additional method — both worse.

### D4: Remove `extractKey` from `SingleStreamProjection`

**Choice:** `SingleStreamProjection<TReadModel>` no longer declares `extractKey`. The executor derives the key from `CommittedEntry.streamId`.

The class hierarchy becomes:

- `ProjectionBase<TReadModel, TKey>` — unchanged (still has `extractKey`).
- `SingleStreamProjection<TReadModel>` — overrides `extractKey` internally (not exposed to users). The executor calls it, but the implementation simply returns the `StreamId` from the committed entry. Alternatively, the executor bypasses `extractKey` entirely for single-stream projections and uses the committed entry's `StreamId` directly.
- `MultiStreamProjection<TReadModel, TKey>` — unchanged. Users still implement `extractKey`.

**Chosen approach:** The `InlineProjectionExecutor` detects single-stream projections (via `is SingleStreamProjection`) and uses `CommittedEntry.streamId` as the key directly, skipping `extractKey`. For multi-stream projections, it calls `extractKey(operation)` as before.

**Rationale:** This avoids changing `ProjectionBase`'s contract while removing the burden from single-stream projection authors. The executor already knows which type of projection it's dealing with.

**Alternatives considered:**
- *Add `StreamId` parameter to `extractKey`*: Makes `extractKey(Operation, StreamId?)` — nullable because not all callers have it. Ugly API that leaks optional context into the signature.
- *Split `ProjectionBase` into two hierarchies*: Over-engineering. The `is` check is simple and precise.

### D5: `InlineProjectionExecutor` accepts `CommitBatch`

**Choice:** Change `executeAsync(List<Operation>)` to `executeAsync(CommitBatch)`.

**Iteration strategy:** Iterate `CommitBatch.entries` (by stream), then each stream's operations. For each operation, look up matching projections. For single-stream projections, use the entry's `StreamId` as key. For multi-stream projections, call `extractKey(operation)`.

**Rationale:** The executor now has full context. The by-stream iteration also enables a future optimization: batching read-model loads per stream per projection (load once, apply N operations, save once) instead of load-apply-save per operation.

### D6: `ProjectionCommitHandler` lives in L1 (`continuum_uow`)

**Choice:** Ship `ProjectionCommitHandler` in `continuum_uow`.

```
ProjectionCommitHandler implements CommitHandler
├── InlineProjectionExecutor (from L0)
└── onCommitAsync(CommitBatch) → executor.executeAsync(batch)
```

**Rationale:** `CommitHandler` is defined in L1. `InlineProjectionExecutor` is in L0. A class that implements a L1 interface and delegates to an L0 type must live in L1. This is the most natural home — `continuum_uow` already owns the commit lifecycle.

**Alternatives considered:**
- *Separate wiring package*: Adds a package for a single class. Not worth it.
- *Place in L0*: Cannot implement `CommitHandler` (L1 type) from L0.

### D7: `AsyncProjectionCommitHandler` — enqueue model (B1)

**Choice:** Ship `AsyncProjectionCommitHandler` in `continuum_uow` using the enqueue model. It accepts a user-provided callback (`Future<void> Function(CommitBatch batch)`) and invokes it after commit.

The handler does not define queue semantics — it simply provides the extension point. Users can:
- Fire-and-forget to an in-memory queue.
- Publish to a message broker.
- Directly call `AsyncProjectionExecutor` (from L2) for event-sourcing stores.

**Rationale:** The enqueue model (B1 from the design notes) works for all store types, not just event-sourcing. Keeping it in L1 avoids coupling to L2 concepts. A callback-based design is the simplest useful abstraction — it delegates policy to the consumer.

**Alternatives considered:**
- *Built-in queue abstraction*: Too opinionated. Queue semantics (at-least-once, exactly-once, persistence) vary by deployment and belong to the application layer.
- *Place in L2 with `StoredEvent` integration*: Only works for event-sourcing stores. Users with state-based stores would get nothing.

### D8: Generator emits registration extension method

**Choice:** The generator emits an extension method on `ProjectionRegistry` that registers all discovered projections:

```dart
extension ProjectionRegistryExtensions on ProjectionRegistry {
  void registerAll({
    required UserProfileProjection userProfileProjection,
    required ReadModelStore<UserProfile, StreamId> userProfileStore,
    // ...one pair per discovered projection
  }) {
    registerGeneratedInline(/* ... */);
    // ...
  }
}
```

**Rationale:** Named parameters make it impossible to swap stores or miss a projection. The generated code calls the existing `registerGeneratedInline`/`registerGeneratedAsync` methods. Users supply instances (often from DI) and the wiring is done.

**Alternatives considered:**
- *Generated abstract class (module contract)*: Requires the user to implement a class. Extension method on an existing type is simpler.
- *Positional parameters*: Lose self-documentation — easy to swap arguments of the same type.

## Risks / Trade-offs

**[Breaking change surface is wide]** → Every `CommitHandler` implementation, every `Session.saveChangesAsync` call site, and every `SingleStreamProjection` subclass must be updated. Mitigation: this is an intentional clean break. Ship in a single major version bump. The CHANGELOG will document migration steps for each type.

**[`is SingleStreamProjection` check in executor]** → Runtime type check is slightly less elegant than compile-time dispatch. Mitigation: the check is simple (`is` on a sealed hierarchy position), has zero ambiguity, and avoids complicating the type hierarchy. If the projection type set grows, a visitor or sealed dispatch can replace it.

**[Optional fields on `CommittedOperation`]** → `streamVersion` and `globalSequence` are nullable, meaning consumers must handle absence. Mitigation: these fields are only consumed by event-sourcing-aware code that already knows whether the store provides them. State-based consumers never access them. Document which store types populate which fields.

**[`AsyncProjectionCommitHandler` is minimal]** → The callback-based design provides no retry, ordering, or idempotency guarantees. Mitigation: this is intentional — the handler is a hook, not a queue. Document that production async projection processing should use `AsyncProjectionExecutor` (L2) with proper position tracking, or a user-provided message infrastructure.

**[Generator registration glue assumes single registry]** → The generated `registerAll` extension works with one `ProjectionRegistry` instance. Applications with multiple registries (e.g., per-module) would call it multiple times or not use it. Mitigation: multiple registries is an advanced pattern. The generated method is additive — it calls `register*` methods, which are idempotent by projection name.
