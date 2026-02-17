## 1. Adapter Exception Types

- [x] 1.1 Create `TransientAdapterException` final class implementing `Exception` with `message` (String) and optional `cause` (Object?) fields
- [x] 1.2 Create `PermanentAdapterException` final class implementing `Exception` with `message` (String) and optional `cause` (Object?) fields
- [x] 1.3 Create `PartialSaveException` final class implementing `Exception` with `savedStreams` (List\<StreamId\>), `failedStreams` (List\<StreamId\>), and `cause` (Object) fields
- [x] 1.4 Export all three new exception types from `continuum.dart` barrel file
- [x] 1.5 Write unit tests for exception construction and field access

## 2. SessionBase Extraction

- [x] 2.1 Create `SessionBase` abstract class with shared fields: `_streams` identity map, `AggregateFactoryRegistry`, `EventApplierRegistry`, `EventApplicationMode`
- [x] 2.2 Move `_StreamState` class into `SessionBase` (or a shared file accessible by both session types)
- [x] 2.3 Move `applyAsync` 3-path detection logic (tracked → creation → mutation/load) into `SessionBase`, declaring `loadAsync` as abstract
- [x] 2.4 Move `_append` with eager/deferred branching into `SessionBase`
- [x] 2.5 Move `_applyEventByRuntimeType`, `_createAndTrack`, strict creation guard, and `_isExplicitType` helper into `SessionBase`
- [x] 2.6 Move `discardStream` and `discardAll` into `SessionBase`
- [x] 2.7 Declare abstract methods that subclasses must implement: `loadAsync`, `saveChangesAsync`, and the reload-for-retry hook
- [x] 2.8 Refactor `SessionImpl` to extend `SessionBase`, keeping only event-sourcing-specific logic (`loadAsync` via event replay, `saveChangesAsync` via EventStore, `_reconstructAggregate`, `_reloadStreamsWithPendingEventsAsync`)
- [x] 2.9 Run all existing `SessionImpl` tests — verify zero regressions after extraction

## 3. StateBasedSession Implementation

- [x] 3.1 Create `StateBasedSession` class extending `SessionBase`, accepting adapter map (`Map<Type, AggregatePersistenceAdapter<Object>>`) as constructor parameter
- [x] 3.2 Implement `loadAsync` — resolve adapter by `TAggregate` type, call `adapter.fetchAsync(streamId)`, track returned aggregate in identity map with `loadedVersion: 0`
- [x] 3.3 Throw `InvalidOperationException` when `loadAsync` is called for an aggregate type with no registered adapter
- [x] 3.4 Implement `saveChangesAsync` — iterate streams with pending events, apply deferred events if needed, call `adapter.persistAsync(streamId, aggregate, pendingEvents)` per stream, return committed events list, clear pending events
- [x] 3.5 Implement concurrency retry in `saveChangesAsync` — catch `ConcurrencyException` from `persistAsync`, re-fetch via `adapter.fetchAsync`, re-apply pending events, retry up to `maxRetries`
- [x] 3.6 Implement partial save failure — when some streams succeed and others fail, throw `PartialSaveException` with saved/failed stream lists; clear pending events only for saved streams
- [x] 3.7 Ensure single-stream failures rethrow the original exception directly (not wrapped in `PartialSaveException`)
- [x] 3.8 Ensure all-streams-fail case throws the first failure directly (not `PartialSaveException` with empty `savedStreams`)
- [x] 3.9 Let `TransientAdapterException`, `PermanentAdapterException`, and unknown exceptions propagate unchanged from both `fetchAsync` and `persistAsync`

## 4. StateBasedStore Implementation

- [x] 4.1 Create `StateBasedStore` final class implementing `ContinuumStore`, accepting `Map<Type, AggregatePersistenceAdapter<Object>>` adapters, `List<GeneratedAggregate>` aggregates, and optional `EventApplicationMode` (default eager)
- [x] 4.2 Merge `AggregateFactoryRegistry` and `EventApplierRegistry` from provided `GeneratedAggregate` list (same pattern as `EventSourcingStore`)
- [x] 4.3 Implement `openSession()` — create and return a new `StateBasedSession` with the adapter map, merged registries, and application mode
- [x] 4.4 Export `StateBasedStore` from `continuum.dart` barrel file

## 5. StateBasedSession Tests

- [x] 5.1 Test `loadAsync` — first call fetches from adapter, second call returns cached aggregate from identity map
- [x] 5.2 Test `loadAsync` — throws `InvalidOperationException` when no adapter registered for aggregate type
- [x] 5.3 Test `loadAsync` — rethrows `StreamNotFoundException` from adapter
- [x] 5.4 Test `applyAsync` — creation event creates aggregate via factory without calling adapter
- [x] 5.5 Test `applyAsync` — mutation event on untracked stream calls `adapter.fetchAsync` first, then applies event
- [x] 5.6 Test `applyAsync` — event on already-tracked stream applies directly without calling adapter
- [x] 5.7 Test `applyAsync` — creation event on already-tracked stream throws `InvalidOperationException`
- [x] 5.8 Test eager mode — event applied immediately, returned aggregate reflects post-event state
- [x] 5.9 Test deferred mode — event recorded but aggregate unchanged until `saveChangesAsync`
- [x] 5.10 Test `saveChangesAsync` — calls `adapter.persistAsync` with aggregate and pending events, returns committed events
- [x] 5.11 Test `saveChangesAsync` — deferred mode applies events before calling `persistAsync`
- [x] 5.12 Test `saveChangesAsync` — no pending events returns empty list without calling adapter
- [x] 5.13 Test `saveChangesAsync` — pending events cleared after successful save
- [x] 5.14 Test `saveChangesAsync` — multiple streams each call `persistAsync` independently
- [x] 5.15 Test concurrency retry — `ConcurrencyException` triggers re-fetch, re-apply, and retry
- [x] 5.16 Test concurrency retry — exhausted retries rethrows `ConcurrencyException`
- [x] 5.17 Test concurrency retry — `maxRetries` parameter controls attempt count
- [x] 5.18 Test partial save — first stream succeeds, second fails → `PartialSaveException` with correct stream lists
- [x] 5.19 Test partial save — saved streams have pending events cleared, failed streams retain theirs
- [x] 5.20 Test single-stream failure rethrows original exception (not `PartialSaveException`)
- [x] 5.21 Test all-streams-fail rethrows first failure (not `PartialSaveException`)
- [x] 5.22 Test `TransientAdapterException` propagates unchanged from `persistAsync`
- [x] 5.23 Test `PermanentAdapterException` propagates unchanged from `persistAsync`
- [x] 5.24 Test unknown exception propagates unchanged from `persistAsync`
- [x] 5.25 Test `discardStream` clears pending events for one stream
- [x] 5.26 Test `discardAll` clears pending events for all streams

## 6. StateBasedStore Tests

- [x] 6.1 Test `StateBasedStore` implements `ContinuumStore` — type assignability
- [x] 6.2 Test `openSession()` returns independent sessions (events in one not visible in other)
- [x] 6.3 Test default `EventApplicationMode` is eager
- [x] 6.4 Test explicit `EventApplicationMode.deferred` is propagated to sessions
- [x] 6.5 Test `StateBasedStore` works with `TransactionalRunner` — auto-commit and `CommitHandler` integration
- [x] 6.6 Test adapter receives creation event and fully constructed aggregate on save after `applyAsync` with creation event

## 7. Barrel File and Final Verification

- [x] 7.1 Verify all new public types are exported from `continuum.dart`: `StateBasedStore`, `StateBasedSession`, `TransientAdapterException`, `PermanentAdapterException`, `PartialSaveException`
- [x] 7.2 Run full test suite across all packages to verify no regressions
- [x] 7.3 Verify `dart analyze` passes with no errors or warnings on `packages/continuum`
