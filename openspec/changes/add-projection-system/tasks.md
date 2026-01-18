# Tasks: Add Projection and Read-Model System

## 1. Core Projection Abstractions

- [ ] 1.1 Create `Projection` base class with `handledEventTypes` property
- [ ] 1.2 Create `SingleStreamProjection<TReadModel, TId>` abstract class
  - `extractId(StoredEvent) -> TId`
  - `createInitial(TId) -> TReadModel`
  - `apply(TReadModel, StoredEvent) -> TReadModel`
- [ ] 1.3 Create `MultiStreamProjection<TReadModel, TKey>` abstract class
  - `extractKey(StoredEvent) -> TKey`
  - `createInitial(TKey) -> TReadModel`
  - `apply(TReadModel, StoredEvent) -> TReadModel`
- [ ] 1.4 Add unit tests for projection type definitions

## 2. Projection Registry

- [ ] 2.1 Create `ProjectionLifecycle` enum (inline, async)
- [ ] 2.2 Create `ProjectionRegistration` class holding projection + lifecycle + metadata
- [ ] 2.3 Create `ProjectionRegistry` class
  - `registerInline<TProjection>(TProjection projection)`
  - `registerAsync<TProjection>(TProjection projection)`
  - `getInlineProjectionsForEvent(Type eventType) -> List<ProjectionRegistration>`
  - `getAsyncProjectionsForEvent(Type eventType) -> List<ProjectionRegistration>`
- [ ] 2.4 Add unit tests for registry registration and lookup

## 3. Read Model Storage

- [ ] 3.1 Create `ReadModelStore<TReadModel, TKey>` abstract interface
  - `loadAsync(TKey) -> TReadModel?`
  - `saveAsync(TKey, TReadModel) -> void`
  - `deleteAsync(TKey) -> void`
- [ ] 3.2 Create `InMemoryReadModelStore` implementation for testing
- [ ] 3.3 Add unit tests for read model store contract

## 4. Position Tracking

- [ ] 4.1 Create `ProjectionPositionStore` abstract interface
  - `loadPositionAsync(String projectionName) -> int?`
  - `savePositionAsync(String projectionName, int position) -> void`
- [ ] 4.2 Create `InMemoryProjectionPositionStore` implementation
- [ ] 4.3 Add unit tests for position store contract

## 5. Inline Projection Execution

- [ ] 5.1 Create `InlineProjectionExecutor` class
  - Accepts registry, read model stores
  - `executeAsync(List<StoredEvent> events)` applies matching inline projections
- [ ] 5.2 Handle projection failures (abort, propagate exception)
- [ ] 5.3 Add unit tests for inline execution scenarios

## 6. Async Projection Execution

- [ ] 6.1 Create `AsyncProjectionExecutor` class
  - Accepts registry, read model stores, position store
  - `processEventsAsync(List<StoredEvent> events)` applies matching async projections
- [ ] 6.2 Implement position tracking (load, update after success)
- [ ] 6.3 Handle projection failures (log, retry logic)
- [ ] 6.4 Add unit tests for async execution scenarios

## 7. Background Projection Processor

- [ ] 7.1 Create `ProjectionProcessor` abstract interface
  - `startAsync()` / `stopAsync()` / `processAsync()`
- [ ] 7.2 Create `PollingProjectionProcessor` implementation
  - Polls event store for new events (after last global sequence)
  - Processes batches through async executor
- [ ] 7.3 Add unit tests for processor lifecycle

## 8. Event Store Integration

- [ ] 8.1 Add method to `EventStore` interface: `loadEventsFromPositionAsync(int fromGlobalSequence, int limit) -> List<StoredEvent>`
- [ ] 8.2 Implement in `InMemoryEventStore`
- [ ] 8.3 Implement in `HiveEventStore`
- [ ] 8.4 Add unit tests for new event store method

## 9. Session Integration

- [ ] 9.1 Modify `SessionImpl` to accept optional `InlineProjectionExecutor`
- [ ] 9.2 Modify `saveChangesAsync()` to:
  - Persist events
  - Execute inline projections with persisted events
  - Roll back if inline projection fails (or make atomic)
- [ ] 9.3 Add unit tests for session with inline projections

## 10. EventSourcingStore Integration

- [ ] 10.1 Add optional `ProjectionRegistry` parameter to `EventSourcingStore` factory
- [ ] 10.2 Create `InlineProjectionExecutor` from registry when configured
- [ ] 10.3 Pass executor to sessions via `openSession()`
- [ ] 10.4 Add integration tests for store with projections

## 11. Public API Exports

- [ ] 11.1 Add projection exports to `lib/continuum.dart`:
  - `src/projections/projection.dart`
  - `src/projections/single_stream_projection.dart`
  - `src/projections/multi_stream_projection.dart`
  - `src/projections/projection_registry.dart`
  - `src/projections/read_model_store.dart`
  - `src/projections/projection_position_store.dart`
  - `src/projections/projection_processor.dart`

## 12. Documentation

- [ ] 12.1 Add CHANGELOG entry for projection system
- [ ] 12.2 Update README with projection usage examples
- [ ] 12.3 Add example code demonstrating:
  - Single-stream projection setup
  - Multi-stream projection setup
  - Inline vs async configuration
  - Background processor startup

## 13. Final Validation

- [ ] 13.1 Run full test suite
- [ ] 13.2 Run `dart analyze` with zero warnings
- [ ] 13.3 Verify backward compatibility (existing tests pass unchanged)
- [ ] 13.4 Manual integration test with example app
