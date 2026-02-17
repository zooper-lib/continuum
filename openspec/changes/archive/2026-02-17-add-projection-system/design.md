# Design: Projection and Read-Model System

## Context

Continuum needs a projection system that:
- Automatically updates read models when events are appended
- Supports both single-stream and multi-stream projections
- Supports inline (strongly consistent) and async (eventually consistent) execution
- Requires only one-time startup configuration
- Provides predictable consistency guarantees

Stakeholders: Application developers using Continuum for event sourcing.

Constraints:
- Must not break existing event sourcing functionality
- Must work with any EventStore implementation
- Must support code generation patterns established in Continuum
- Must keep core lightweight (no heavy dependencies)

## Goals / Non-Goals

### Goals
- Declarative projection definitions
- Automatic event-driven updates
- Zero runtime user interaction after configuration
- Support both single-stream and multi-stream projections
- Support both inline and async execution models
- Predictable failure and recovery behavior

### Non-Goals
- Real-time streaming/push to clients (that's a separate concern)
- Complex event processing (CEP) patterns
- Projection versioning/schema evolution (future work)
- Distributed projection processing (single-node only for v1)

## Decisions

### Decision 1: Projection as Pure Event Consumer

Projections are pure functions that transform events into read model updates. They:
- Do NOT load aggregates
- Do NOT issue commands
- Do NOT have side effects beyond updating the read model
- Receive events and return read model mutations

**Rationale**: Keeps projections simple, testable, and deterministic. Side effects belong in process managers (future work).

### Decision 2: Two Projection Types

#### Single-Stream Projections
- Build read model from one event stream (tied to aggregate identity)
- One projection instance per stream/aggregate
- Deterministic event ordering (per-stream version)
- Use case: per-entity query models, aggregate summaries

```dart
abstract class SingleStreamProjection<TReadModel, TId> {
  TId extractId(StoredEvent event);
  TReadModel createInitial(TId id);
  TReadModel apply(TReadModel current, StoredEvent event);
}
```

#### Multi-Stream Projections
- Build read model from events across multiple streams
- Events grouped by a projection-defined key
- Ordering based on global sequence number
- Use case: cross-aggregate views, dashboards, statistics

```dart
abstract class MultiStreamProjection<TReadModel, TKey> {
  TKey extractKey(StoredEvent event);
  TReadModel createInitial(TKey key);
  TReadModel apply(TReadModel current, StoredEvent event);
}
```

**Rationale**: Clear separation allows optimized implementations and clearer mental model.

### Decision 3: Execution Lifecycle Selection

Each projection declares its execution lifecycle:

#### Inline Projections
- Executed synchronously during `saveChangesAsync()`
- Part of the same logical unit of work
- Failure aborts the event append
- Guarantees: if event exists, projection is updated

#### Async Projections
- Executed by a background processor
- Event append completes immediately
- Projections resume from last position after restart
- Guarantees: every event is eventually processed

**Rationale**: Different use cases need different consistency guarantees. Inline for critical reads (e.g., unique constraints), async for non-critical views.

### Decision 4: Projection Registry

A central `ProjectionRegistry` maintains:
- All registered projections
- Event type → projection mappings
- Lifecycle (inline/async) per projection
- Projection type (single/multi-stream)

The registry is consulted on every event append to determine affected projections.

```dart
final class ProjectionRegistry {
  void registerInline<TProjection>(TProjection projection);
  void registerAsync<TProjection>(TProjection projection);
  
  List<InlineProjection> getInlineProjectionsForEvent(Type eventType);
  List<AsyncProjection> getAsyncProjectionsForEvent(Type eventType);
}
```

### Decision 5: Read Model Storage Abstraction

Read models are persisted via a `ReadModelStore` abstraction:

```dart
abstract interface class ReadModelStore<TReadModel, TKey> {
  Future<TReadModel?> loadAsync(TKey key);
  Future<void> saveAsync(TKey key, TReadModel readModel);
  Future<void> deleteAsync(TKey key);
}
```

Implementations:
- `InMemoryReadModelStore` for testing/local
- `HiveReadModelStore` for persistent local storage
- Users can implement custom backends

### Decision 6: Position Tracking for Async Projections

Async projections track their processing position:

```dart
abstract interface class ProjectionPositionStore {
  Future<int?> loadPositionAsync(String projectionName);
  Future<void> savePositionAsync(String projectionName, int position);
}
```

The position is the `globalSequence` of the last processed event.

### Decision 7: Background Projection Processor

A `ProjectionProcessor` runs async projections:

```dart
abstract interface class ProjectionProcessor {
  Future<void> startAsync();
  Future<void> stopAsync();
  Future<void> processAsync(); // Single batch
}
```

Implementation polls for new events, applies to relevant projections, and updates positions.

### Decision 8: Integration Points

#### EventSourcingStore Changes
```dart
factory EventSourcingStore({
  required EventStore eventStore,
  required List<GeneratedAggregate> aggregates,
  ProjectionRegistry? projections, // NEW
});
```

#### Session.saveChangesAsync() Changes
After persisting events, inline projections are executed in the same logical operation.

### Decision 9: Event Type Filtering

Projections declare which event types they handle:

```dart
abstract class Projection {
  Set<Type> get handledEventTypes;
}
```

The registry uses this to efficiently route events.

## Alternatives Considered

### Alternative A: Event Bus Pattern
Considered using a publish-subscribe event bus.

**Rejected because**:
- Adds complexity with no clear benefit
- Harder to guarantee execution order
- Projections would need manual subscription management

### Alternative B: Reactive Streams
Considered using Stream-based reactive patterns.

**Rejected because**:
- Adds dependency on async programming model
- Harder to implement inline (synchronous) projections
- Overkill for single-node use case

### Alternative C: Single Unified Projection Type
Considered having one projection type for both single and multi-stream.

**Rejected because**:
- Conflates different use cases
- Single-stream can be optimized differently
- Clearer API when separated

## Risks / Trade-offs

| Risk | Impact | Mitigation |
|------|--------|------------|
| Inline projections slow down writes | Medium | Document trade-offs; recommend async for non-critical |
| Async projection lag confuses users | Low | Clear documentation; provide lag monitoring |
| Read model storage adds complexity | Medium | Provide simple in-memory default |
| Position tracking failure loses progress | High | Idempotent projections; atomic position updates |

## Migration Plan

1. Phase 1: Core abstractions (Projection, Registry, ReadModelStore)
2. Phase 2: Inline projection execution
3. Phase 3: Async projection processor
4. Phase 4: Integration with EventSourcingStore

Rollback: Feature is additive; disable by not registering projections.

## Open Questions

1. **Should projections support batching?** (Process multiple events at once)
   - Tentative answer: Yes for async, no for inline initially
   
2. **Should we support projection rebuild from scratch?**
   - Tentative answer: Yes, via reset position to 0 and reprocess
   
3. **Should multi-stream projections support event ordering guarantees?**
   - Tentative answer: Ordered by globalSequence; document eventual consistency
