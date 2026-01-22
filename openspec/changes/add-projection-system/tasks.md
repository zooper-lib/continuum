# Tasks: Add Projection and Read-Model System

## 1. Core Projection Abstractions

- [x] 1.1 Create `Projection` base class with `handledEventTypes` property
- [x] 1.2 Create `SingleStreamProjection<TReadModel, TId>` abstract class
  - `extractId(StoredEvent) -> TId`
  - `createInitial(TId) -> TReadModel`
  - `apply(TReadModel, StoredEvent) -> TReadModel`
- [x] 1.3 Create `MultiStreamProjection<TReadModel, TKey>` abstract class
  - `extractKey(StoredEvent) -> TKey`
  - `createInitial(TKey) -> TReadModel`
  - `apply(TReadModel, StoredEvent) -> TReadModel`
- [x] 1.4 Add unit tests for projection type definitions

## 2. Projection Registry

- [x] 2.1 Create `ProjectionLifecycle` enum (inline, async)
- [x] 2.2 Create `ProjectionRegistration` class holding projection + lifecycle + metadata
- [x] 2.3 Create `ProjectionRegistry` class
  - `registerInline<TProjection>(TProjection projection)`
  - `registerAsync<TProjection>(TProjection projection)`
  - `getInlineProjectionsForEvent(Type eventType) -> List<ProjectionRegistration>`
  - `getAsyncProjectionsForEvent(Type eventType) -> List<ProjectionRegistration>`
- [x] 2.4 Add unit tests for registry registration and lookup

## 3. Read Model Storage

- [x] 3.1 Create `ReadModelStore<TReadModel, TKey>` abstract interface
  - `loadAsync(TKey) -> TReadModel?`
  - `saveAsync(TKey, TReadModel) -> void`
  - `deleteAsync(TKey) -> void`
- [x] 3.2 Create `InMemoryReadModelStore` implementation for testing
- [x] 3.3 Add unit tests for read model store contract

## 4. Position Tracking

- [x] 4.1 Create `ProjectionPositionStore` abstract interface
  - `loadPositionAsync(String projectionName) -> int?`
  - `savePositionAsync(String projectionName, int position) -> void`
- [x] 4.2 Create `InMemoryProjectionPositionStore` implementation
- [x] 4.3 Add unit tests for position store contract

## 5. Inline Projection Execution

- [x] 5.1 Create `InlineProjectionExecutor` class
  - Accepts registry, read model stores
  - `executeAsync(List<StoredEvent> events)` applies matching inline projections
- [x] 5.2 Handle projection failures (abort, propagate exception)
- [x] 5.3 Add unit tests for inline execution scenarios

## 6. Async Projection Execution

- [x] 6.1 Create `AsyncProjectionExecutor` class
  - Accepts registry, read model stores, position store
  - `processEventsAsync(List<StoredEvent> events)` applies matching async projections
- [x] 6.2 Implement position tracking (load, update after success)
- [x] 6.3 Handle projection failures (log, retry logic)
- [x] 6.4 Add unit tests for async execution scenarios

## 7. Background Projection Processor

- [x] 7.1 Create `ProjectionProcessor` abstract interface
  - `startAsync()` / `stopAsync()` / `processAsync()`
- [x] 7.2 Create `PollingProjectionProcessor` implementation
  - Polls event store for new events (after last global sequence)
  - Processes batches through async executor
- [x] 7.3 Add unit tests for processor lifecycle

## 8. Event Store Integration

- [x] 8.1 Add method to `EventStore` interface: `loadEventsFromPositionAsync(int fromGlobalSequence, int limit) -> List<StoredEvent>`
- [x] 8.2 Implement in `InMemoryEventStore`
- [x] 8.3 Implement in `HiveEventStore`
- [x] 8.4 Add unit tests for new event store method

## 9. Session Integration

- [x] 9.1 Modify `SessionImpl` to accept optional `InlineProjectionExecutor`
- [x] 9.2 Modify `saveChangesAsync()` to:
  - Persist events
  - Execute inline projections with persisted events
  - Roll back if inline projection fails (or make atomic)
- [x] 9.3 Add unit tests for session with inline projections

## 10. EventSourcingStore Integration

- [x] 10.1 Add optional `ProjectionRegistry` parameter to `EventSourcingStore` factory
- [x] 10.2 Create `InlineProjectionExecutor` from registry when configured
- [x] 10.3 Pass executor to sessions via `openSession()`
- [x] 10.4 Add integration tests for store with projections

## 11. Public API Exports

- [x] 11.1 Add projection exports to `lib/continuum.dart`:
  - `src/projections/projection.dart`
  - `src/projections/single_stream_projection.dart`
  - `src/projections/multi_stream_projection.dart`
  - `src/projections/projection_registry.dart`
  - `src/projections/read_model_store.dart`
  - `src/projections/projection_position_store.dart`
  - `src/projections/projection_processor.dart`

## 12. Documentation

- [x] 12.1 Add CHANGELOG entry for projection system
- [x] 12.2 Update README with projection usage examples
- [x] 12.3 Add example code demonstrating:
  - Single-stream projection setup
  - Multi-stream projection setup
  - Inline vs async configuration
  - Background processor startup

## 13. Final Validation

- [x] 13.1 Run full test suite
- [x] 13.2 Run `dart analyze` with zero warnings
- [x] 13.3 Verify backward compatibility (existing tests pass unchanged)
- [ ] 13.4 Manual integration test with example app
