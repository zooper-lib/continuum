## 1. Phase 1 — Create `continuum_uow` Package

- [ ] 1.1 Create `packages/continuum_uow/` directory with `pubspec.yaml` (depends on `continuum`, `meta`; dev depends on `lints`, `test`, `mockito`), `analysis_options.yaml`, and `LICENSE`
- [ ] 1.2 Add `packages/continuum_uow` to workspace `pubspec.yaml` under `workspace:`
- [ ] 1.3 Add `Operation` marker interface to `continuum` core at `lib/src/operations/operation.dart` and make `ContinuumEvent` implement `Operation`
- [ ] 1.4 Export `Operation` from `continuum.dart` barrel file
- [ ] 1.5 Create `lib/src/session.dart` — `Session` interface (renamed from `ContinuumSession`) with `applyAsync` accepting `Operation`; `saveChangesAsync` returning `Future<void>`
- [ ] 1.6 Create `lib/src/tracked_entity.dart` — `TrackedEntity` class (renamed from `StreamState`) using `List<Operation>` for pending operations
- [ ] 1.7 Create `lib/src/session_base.dart` — `SessionBase` abstract class with identity map, 3-path `applyAsync` detection, eager/deferred branching, creation guard, discard operations; rename internals (`applyOperationByRuntimeType`, `applyDeferredOperations`, `trackedEntities`, `handleMutationOnUntrackedEntity`, `pendingOperations`)
- [ ] 1.8 Create `lib/src/session_store.dart` — `SessionStore` interface (renamed from `ContinuumStore`)
- [ ] 1.9 Create `lib/src/transactional_runner.dart` — `TransactionalRunner` using `SessionStore` / `Session`
- [ ] 1.10 Create `lib/src/commit_handler.dart` — `CommitHandler` interface with `onCommitAsync()` (no event list parameter)
- [ ] 1.11 Create `lib/src/concurrency_exception.dart` — `ConcurrencyException` with `streamId`, `expectedVersion`, `actualVersion`, `message`
- [ ] 1.12 Create `lib/src/invalid_operation_exception.dart` — `InvalidOperationException` with `message`
- [ ] 1.13 Create `lib/src/unsupported_operation_exception.dart` — `UnsupportedOperationException` with `operationType`, `aggregateType`
- [ ] 1.14 Create `lib/src/partial_save_exception.dart` — `PartialSaveException` with `savedStreams`, `failedStreams`, `cause`
- [ ] 1.15 Create backward-compatibility typedefs: `ContinuumSession = Session`, `ContinuumStore = SessionStore`, `UnsupportedEventException = UnsupportedOperationException`
- [ ] 1.16 Create barrel file `lib/continuum_uow.dart` exporting all public types
- [ ] 1.17 Write tests for `TrackedEntity` (construction, `withClearedPendingOperations`, operation accumulation)
- [ ] 1.18 Write tests for `SessionBase` via a concrete `InMemoryTestSession` subclass (3-path detection, identity map, creation guard, eager mode, deferred mode, discard, plain `Operation` support)
- [ ] 1.19 Write tests for `TransactionalRunner` (lifecycle, zone scoping, `currentSession`/`currentSessionOrNull`, nested `runAsync`, `CommitHandler` integration, no handler)
- [ ] 1.20 Write tests for exception types (construction, field access)
- [ ] 1.21 Run `dart analyze` on `continuum_uow` — must be clean
- [ ] 1.22 Run `dart test` on `continuum_uow` — must pass

## 2. Phase 2 — Create `continuum_es` Package

- [ ] 2.1 Create `packages/continuum_es/` directory with `pubspec.yaml` (depends on `continuum`, `continuum_uow`, `meta`), `analysis_options.yaml`, and `LICENSE`
- [ ] 2.2 Add `packages/continuum_es` to workspace `pubspec.yaml` under `workspace:`
- [ ] 2.3 Move `EventSourcingStore` to `lib/src/persistence/event_sourcing_store.dart` — implement `SessionStore` (from UoW)
- [ ] 2.4 Move `SessionImpl` to `lib/src/persistence/session_impl.dart` — extend `SessionBase` (from UoW); keep `Future<List<ContinuumEvent>>` return on `saveChangesAsync`; add validation that pending operations are `ContinuumEvent` instances
- [ ] 2.5 Move event store types: `EventStore`, `AtomicEventStore`, `ExpectedVersion`, `StoredEvent` (with `StreamAppendBatch` if exists)
- [ ] 2.6 Move serialization types: `EventSerializer`, `EventSerializerRegistry`, `JsonEventSerializer`
- [ ] 2.7 Move `ProjectionEventStore`
- [ ] 2.8 Move all projection types from `lib/src/projections/` to `continuum_es` (14 files: `Projection`, `SingleStreamProjection`, `MultiStreamProjection`, `ProjectionRegistry`, `InlineProjectionExecutor`, `AsyncProjectionExecutor`, `ProjectionProcessor`, `ReadModelStore`, `ProjectionPositionStore`, `ProjectionPosition`, `ProjectionLifecycle`, `ProjectionRegistration`, `ReadModelResult`, `GeneratedProjection`)
- [ ] 2.9 Create barrel file `lib/continuum_es.dart` exporting all public types
- [ ] 2.10 Move relevant tests from `continuum/test/persistence/` to `continuum_es/test/`: `session_test`, `session_apply_async_test`, `session_concurrency_retry_test`, `session_load_all_async_test`, `event_application_mode_test`, `expected_version_test`, `json_event_serializer_test`, `stored_event_*_test`, `sealed_class_subtype_matching_test`
- [ ] 2.11 Move relevant tests from `continuum/test/projections/` to `continuum_es/test/`: all projection tests
- [ ] 2.12 Update all moved test imports to reference `continuum_es` and `continuum_uow` packages
- [ ] 2.13 Verify `continuum_generator` generated code — check if projection codegen emits imports that need updating to `package:continuum_es/...`; fix generator if needed
- [ ] 2.14 Run `dart analyze` on `continuum_es` — must be clean
- [ ] 2.15 Run `dart test` on `continuum_es` — must pass

## 3. Phase 3 — Create `continuum_state` Package

- [ ] 3.1 Create `packages/continuum_state/` directory with `pubspec.yaml` (depends on `continuum`, `continuum_uow`, `meta`), `analysis_options.yaml`, and `LICENSE`
- [ ] 3.2 Add `packages/continuum_state` to workspace `pubspec.yaml` under `workspace:`
- [ ] 3.3 Move `StateBasedStore` to `lib/src/persistence/state_based_store.dart` — implement `SessionStore` (from UoW)
- [ ] 3.4 Move `StateBasedSession` to `lib/src/persistence/state_based_session.dart` — extend `SessionBase` (from UoW)
- [ ] 3.5 Move `AggregatePersistenceAdapter` to `lib/src/persistence/aggregate_persistence_adapter.dart` — change `persistAsync` parameter from `List<ContinuumEvent>` to `List<Operation>`
- [ ] 3.6 Move `PermanentAdapterException` to `lib/src/exceptions/permanent_adapter_exception.dart`
- [ ] 3.7 Move `TransientAdapterException` to `lib/src/exceptions/transient_adapter_exception.dart`
- [ ] 3.8 Create barrel file `lib/continuum_state.dart` exporting all public types
- [ ] 3.9 Move relevant tests from `continuum/test/persistence/` to `continuum_state/test/`: `state_based_session_test`, `state_based_store_test`
- [ ] 3.10 Move `continuum/test/exceptions/adapter_exceptions_test.dart` to `continuum_state/test/`
- [ ] 3.11 Update all moved test imports to reference `continuum_state` and `continuum_uow` packages
- [ ] 3.12 Run `dart analyze` on `continuum_state` — must be clean
- [ ] 3.13 Run `dart test` on `continuum_state` — must pass

## 4. Phase 4 — Update Store Implementations

- [ ] 4.1 Update `continuum_store_memory/pubspec.yaml` — depend on `continuum_es` instead of `continuum`
- [ ] 4.2 Update `continuum_store_memory` source imports to reference `continuum_es` types
- [ ] 4.3 Update `continuum_store_memory` test imports
- [ ] 4.4 Run `dart analyze` and `dart test` on `continuum_store_memory` — must pass
- [ ] 4.5 Update `continuum_store_hive/pubspec.yaml` — depend on `continuum_es` instead of `continuum`
- [ ] 4.6 Update `continuum_store_hive` source imports to reference `continuum_es` types
- [ ] 4.7 Update `continuum_store_hive` test imports
- [ ] 4.8 Run `dart analyze` and `dart test` on `continuum_store_hive` — must pass
- [ ] 4.9 Update `continuum_store_sembast/pubspec.yaml` — depend on `continuum_es` instead of `continuum`
- [ ] 4.10 Update `continuum_store_sembast` source imports to reference `continuum_es` types
- [ ] 4.11 Update `continuum_store_sembast` test imports
- [ ] 4.12 Run `dart analyze` and `dart test` on `continuum_store_sembast` — must pass

## 5. Phase 5 — Clean Up `continuum` Core

- [ ] 5.1 Delete moved persistence files from `packages/continuum/lib/src/persistence/`: `session.dart`, `session_base.dart`, `session_impl.dart`, `transactional_runner.dart`, `commit_handler.dart`, `continuum_store.dart`, `event_sourcing_store.dart`, `event_store.dart`, `atomic_event_store.dart`, `event_serializer.dart`, `event_serializer_registry.dart`, `json_event_serializer.dart`, `stored_event.dart`, `expected_version.dart`, `projection_event_store.dart`, `aggregate_persistence_adapter.dart`, `state_based_session.dart`, `state_based_store.dart`
- [ ] 5.2 Delete moved exception files from `packages/continuum/lib/src/exceptions/`: `concurrency_exception.dart`, `invalid_operation_exception.dart`, `unsupported_event_exception.dart`, `partial_save_exception.dart`, `permanent_adapter_exception.dart`, `transient_adapter_exception.dart`
- [ ] 5.3 Delete moved projection files — entire `packages/continuum/lib/src/projections/` directory
- [ ] 5.4 Update `lib/continuum.dart` barrel file — remove all deleted exports; keep only Layer 0 types (annotations, events, identity, `Operation`, `EventApplicationMode`, `EventRegistry`, `GeneratedAggregate`, remaining exceptions)
- [ ] 5.5 Delete moved test files from `packages/continuum/test/persistence/` and `packages/continuum/test/projections/`
- [ ] 5.6 Verify remaining `continuum` tests (`continuum_event_test`, `stream_id_test`, `dispatch_registries_test`, `event_registry_test`, `exceptions_test`) still pass
- [ ] 5.7 Run `dart analyze` on `continuum` — must be clean
- [ ] 5.8 Run `dart test` on `continuum` — must pass

## 6. Documentation & Changelogs

- [ ] 6.1 Create `packages/continuum_uow/README.md` — package description, installation, usage examples (extending `SessionBase`, using `TransactionalRunner`), link to main repo
- [ ] 6.2 Create `packages/continuum_es/README.md` — package description, installation, usage examples (event sourcing setup, projections), link to main repo
- [ ] 6.3 Create `packages/continuum_state/README.md` — package description, installation, usage examples (state-based store, adapters), link to main repo
- [ ] 6.4 Update `packages/continuum/README.md` — reflect shrunk scope (Layer 0 only); remove session/persistence/projection sections that moved to other packages; update dependency examples for the new multi-package structure
- [ ] 6.5 Update `packages/continuum_store_memory/README.md` — update installation instructions to reference `continuum_es` dependency
- [ ] 6.6 Update `packages/continuum_store_hive/README.md` — update installation instructions to reference `continuum_es` dependency
- [ ] 6.7 Update `packages/continuum_store_sembast/README.md` — update installation instructions to reference `continuum_es` dependency
- [ ] 6.8 Update root `CHANGELOG.md` — add entry under `[Unreleased]` documenting the package extraction (breaking changes, new packages, migration guidance)
- [ ] 6.9 Update root `README.md` — reflect the new four-layer architecture, updated dependency examples for each consumption mode

## 7. Final Validation

- [ ] 7.1 Run `dart analyze` across ALL packages in the workspace
- [ ] 7.2 Run `dart test` across ALL packages in the workspace
- [ ] 7.3 Verify `continuum_generator` generated code compiles against the new package structure (run `build_runner` in example or test project)
- [ ] 7.4 Verify no circular dependencies exist in the package graph
