## 1. ContinuumStore Interface

- [x] 1.1 Create `ContinuumStore` abstract interface class in `packages/continuum/lib/src/persistence/continuum_store.dart` with single method `ContinuumSession openSession()`
- [x] 1.2 Make `EventSourcingStore` implement `ContinuumStore`
- [x] 1.3 Export `ContinuumStore` from the barrel file `packages/continuum/lib/continuum.dart`

## 2. EventApplicationMode

- [x] 2.1 Create `EventApplicationMode` enum (`eager`, `deferred`) in `packages/continuum/lib/src/persistence/event_application_mode.dart`
- [x] 2.2 Add optional `applicationMode` parameter to `EventSourcingStore` factory constructor, defaulting to `EventApplicationMode.eager`
- [x] 2.3 Pass `applicationMode` through to `SessionImpl` constructor
- [x] 2.4 Export `EventApplicationMode` from the barrel file

## 3. Unified Mutation API — ContinuumSession Interface

- [x] 3.1 Add `Future<TAggregate> applyAsync<TAggregate>(StreamId streamId, ContinuumEvent event)` to `ContinuumSession` interface
- [x] 3.2 Remove `startStream` method from `ContinuumSession` interface
- [x] 3.3 Remove `append` method from `ContinuumSession` interface
- [x] 3.4 Change `saveChangesAsync` return type from `Future<void>` to `Future<List<ContinuumEvent>>` on `ContinuumSession` interface

## 4. Unified Mutation API — SessionImpl Implementation

- [x] 4.1 Implement `applyAsync` in `SessionImpl` with three-path detection: already-tracked → creation event (factory probe) → mutation event (load + apply)
- [x] 4.2 Add strict creation guard in `applyAsync`: throw `InvalidOperationException` when a creation event is applied to an already-tracked stream
- [x] 4.3 Create `InvalidOperationException` in `packages/continuum/lib/src/exceptions/invalid_operation_exception.dart` and export from barrel file
- [x] 4.4 Extract private `_append` method with `EventApplicationMode` branch: eager calls `_applyEventToAggregate` immediately, deferred only records the event
- [x] 4.5 Update `saveChangesAsync` in `SessionImpl` to apply deferred events before serialization when in deferred mode
- [x] 4.6 Update `saveChangesAsync` in `SessionImpl` to collect and return `List<ContinuumEvent>` of all committed events across all streams
- [x] 4.7 Remove public `startStream` method from `SessionImpl` (logic folded into `applyAsync`)
- [x] 4.8 Remove public `append` method from `SessionImpl` (logic folded into `applyAsync` and `_append`)

## 5. Decouple Projections from Session

- [x] 5.1 Remove `InlineProjectionExecutor?` parameter from `SessionImpl` constructor
- [x] 5.2 Remove inline projection execution from `SessionImpl._persistPendingEventsAsync`
- [x] 5.3 Remove `ProjectionRegistry?` parameter from `EventSourcingStore` factory constructor
- [x] 5.4 Remove `InlineProjectionExecutor` instantiation from `EventSourcingStore` factory constructor

## 6. CommitHandler Interface

- [x] 6.1 Create `CommitHandler` abstract interface class in `packages/continuum/lib/src/persistence/commit_handler.dart` with `Future<void> onCommitAsync(List<ContinuumEvent> events)`
- [x] 6.2 Export `CommitHandler` from the barrel file

## 7. TransactionalRunner

- [x] 7.1 Create `TransactionalRunner` final class in `packages/continuum/lib/src/persistence/transactional_runner.dart`
- [x] 7.2 Implement constructor accepting `ContinuumStore` and optional `CommitHandler`
- [x] 7.3 Implement `runAsync<T>` with zone-based session scoping: create session, `runZoned` with session in zone values, auto-commit via `saveChangesAsync`, call `CommitHandler.onCommitAsync` if handler configured and events non-empty
- [x] 7.4 Implement static `currentSession` accessor that retrieves session from `Zone.current` and throws `StateError` if absent
- [x] 7.5 Implement static `currentSessionOrNull` accessor that returns `null` if no ambient session
- [x] 7.6 Export `TransactionalRunner` from the barrel file

## 8. AggregatePersistenceAdapter Interface

- [x] 8.1 Create `AggregatePersistenceAdapter<TAggregate>` abstract interface class in `packages/continuum/lib/src/persistence/aggregate_persistence_adapter.dart` with `fetchAsync(StreamId)` and `persistAsync(StreamId, TAggregate, List<ContinuumEvent>)`
- [x] 8.2 Export `AggregatePersistenceAdapter` from the barrel file

## 9. Migrate Tests

- [x] 9.1 Update `session_test.dart` to replace all `startStream` calls with `applyAsync`
- [x] 9.2 Update `session_test.dart` to replace all `append` calls with `applyAsync`
- [x] 9.3 Update `session_test.dart` to handle `saveChangesAsync` returning `List<ContinuumEvent>` instead of `void`
- [x] 9.4 Update `session_concurrency_retry_test.dart` to replace all `startStream`/`append` calls with `applyAsync` and update save return type expectations
- [x] 9.5 Update projection tests that depend on `ProjectionRegistry` being passed to `EventSourcingStore`

## 10. New Tests

- [x] 10.1 Add tests for `applyAsync` creation path (factory probe, aggregate creation, stream tracking)
- [x] 10.2 Add tests for `applyAsync` mutation path (load from store, apply event)
- [x] 10.3 Add tests for `applyAsync` already-tracked fast path
- [x] 10.4 Add test for strict creation guard: `InvalidOperationException` when creation event applied to tracked stream
- [x] 10.5 Add test for `applyAsync` with non-existent stream and mutation event: `StreamNotFoundException`
- [x] 10.6 Add tests for `saveChangesAsync` returning committed events list (single stream, multi-stream, empty)
- [x] 10.7 Add tests for `EventApplicationMode.eager` — aggregate reflects event immediately after `applyAsync`
- [x] 10.8 Add tests for `EventApplicationMode.deferred` — aggregate does not reflect event until `saveChangesAsync`
- [x] 10.9 Add tests for `TransactionalRunner.runAsync` lifecycle: session creation, auto-commit, commit handler invocation
- [x] 10.10 Add tests for `TransactionalRunner.currentSession` and `currentSessionOrNull` accessors (inside/outside `runAsync`)
- [x] 10.11 Add tests for `TransactionalRunner` when action throws: session abandoned, no save, exception propagates
- [x] 10.12 Add tests for `CommitHandler` semantics: called after save, not called on empty commit, not called on save failure
- [x] 10.13 Add tests for zone isolation: two concurrent `runAsync` calls get independent sessions

## 11. Migrate Example Project

- [x] 11.1 Update `packages/continuum/example/main.dart` to use `applyAsync` instead of `startStream`/`append`
- [x] 11.2 Update example to use `TransactionalRunner` and `CommitHandler` if applicable
- [x] 11.3 Remove `ProjectionRegistry` from `EventSourcingStore` construction in example if present

## 12. Migrate Lint Tests and Fixtures

- [x] 12.1 Update any test fixtures in `packages/continuum/test/_fixtures/` that reference `startStream` or `append`
- [x] 12.2 Update `continuum_lints` test cases if they reference the old `ContinuumSession` API surface
