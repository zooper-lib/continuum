# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]


## [5.2.0] - 2026-02-20

### Added

- Added `@OperationTarget()` and `@OperationFor(...)` annotations in `continuum` to support operation-driven mutation without requiring `AggregateRoot`.

### Changed

- `continuum_generator` now discovers operation targets via `@OperationTarget()` (and still supports `AggregateRoot` as a legacy marker).
- `continuum_lints` now applies missing-handler and missing-creation-factory checks to `@OperationTarget()` classes.
- `EventSourcingStore` and `StateBasedStore` now accept `targets:` instead of `aggregates:` (with `aggregates:` kept as a deprecated alias).
- State-based persistence now prefers `TargetPersistenceAdapter<T>`; `AggregatePersistenceAdapter<T>` remains as a deprecated alias for backward compatibility.

### Fixed

- Example `abstract_interface_targets.dart` is now discoverable by codegen by marking its target types with `@OperationTarget()`.

### Deprecated

- Deprecated `@AggregateEvent(...)` in favor of operation-oriented annotations.

## [5.1.0] - 2026-02-20

### Added

- New example `example/lib/store_state_based_transactional.dart` demonstrating `StateBasedStore` with `TransactionalRunner` and a REST API adapter.
- New example `example/lib/store_state_based_local_db.dart` demonstrating `StateBasedStore` with a local key-value database adapter.
- `InMemoryPersistenceAdapter` in `continuum_store_memory` — a ready-made `AggregatePersistenceAdapter` backed by a plain `Map`, suitable for testing and development.
- `HivePersistenceAdapter` in `continuum_store_hive` — a ready-made `AggregatePersistenceAdapter` backed by a Hive `Box<String>`, for local persistence.
- `SembastPersistenceAdapter` in `continuum_store_sembast` — a ready-made `AggregatePersistenceAdapter` backed by a Sembast store, for local persistence.

### Removed

- Removed obsolete hybrid examples from the `example/` package. The
  following example files and their helper DTOs were removed because the
  recommended pattern is now demonstrated in
  `example/lib/store_state_based_transactional.dart`:
  - `example/lib/hybrid_optimistic_creation.dart`
  - `example/lib/hybrid_profile_edit.dart`
  - `example/lib/hybrid_multi_step_form.dart`
  - `example/lib/hybrid/backend_api.dart`
  - `example/lib/hybrid/dtos.dart`


## [5.0.0] - 2026-02-19

### Breaking Changes

- **BREAKING**: Extracted `continuum_uow` package — Unit of Work session engine (`Session`, `SessionBase`, `TransactionalRunner`, `CommitHandler`, `TrackedEntity`, UoW exceptions). Previously part of `continuum`.
- **BREAKING**: Extracted `continuum_event_sourcing` package — event sourcing persistence (`EventSourcingStore`, `EventStore`, `AtomicEventStore`, serialization, projections, `SessionImpl`). Previously part of `continuum`.
- **BREAKING**: Extracted `continuum_state` package — state-based persistence (`StateBasedStore`, `StateBasedSession`, `AggregatePersistenceAdapter`, adapter exceptions). Previously part of `continuum`.
- **BREAKING**: `continuum` core now only exports Layer 0 types (annotations, events, identity, `Operation`, `EventApplicationMode`, `EventRegistry`, `GeneratedAggregate`, dispatch registries, core exceptions).
- **BREAKING**: Store implementations (`continuum_store_memory`, `continuum_store_hive`, `continuum_store_sembast`) now depend on `continuum_event_sourcing` instead of `continuum` for persistence types.
- **BREAKING**: `Session.saveChangesAsync` now returns `Future<List<Operation>>` instead of `Future<void>`, providing the list of committed operations in application order.
- **BREAKING**: `CommitHandler.onCommitAsync` now accepts `List<Operation> committedOperations` parameter instead of taking no arguments. The handler is not called when no operations were committed.
- **Migration**: Update imports to reference the new packages — `package:continuum_uow/continuum_uow.dart` for session types, `package:continuum_event_sourcing/continuum_event_sourcing.dart` for event sourcing types, `package:continuum_state/continuum_state.dart` for state-based types.
- Backward-compatible typedefs are available in `continuum_uow` to ease migration.

### Added

- **State-Based Store**: A complete persistence mode for backend-authoritative applications. Instead of persisting events to an event store, aggregates are loaded and saved through `AggregatePersistenceAdapter` instances that communicate with your backend (REST API, GraphQL, database, etc.):
  - `StateBasedStore`: Store implementation backed by adapter map (one adapter per aggregate type)
  - `StateBasedSession`: Session implementation delegating to adapters for load/save operations
  - `AggregatePersistenceAdapter<TAggregate>`: Interface defining `fetchAsync` and `persistAsync` operations
  - `SessionBase`: Abstract base class extracting shared session logic (identity map, event application, 3-path detection) for reuse across `SessionImpl` and `StateBasedSession`
  - `PartialSaveException`: Reports partial failures when saving multiple streams atomically
  - `TransientAdapterException`: Base exception for retriable adapter failures
  - `PermanentAdapterException`: Base exception for non-retriable adapter failures
  - Sessions support the same `applyAsync` / `saveChangesAsync` contract as `EventSourcingStore`
  - Supports concurrency retry via `maxRetries` parameter (adapter must throw `ConcurrencyException`)
  - Events exist only in memory as domain objects and are never serialized
- **Sembast EventStore** (`continuum_store_sembast`): Sembast-backed `EventStore` implementation providing persistent local storage using Sembast. Supports `AtomicEventStore` and `ProjectionEventStore` interfaces. Pure Dart solution that works on all platforms (mobile, desktop, web via `sembast_web`).
- **Concurrency retry on `saveChangesAsync`**: `ContinuumSession.saveChangesAsync` now accepts an optional `maxRetries` parameter (default `0`, fully backward-compatible). When a `ConcurrencyException` is detected and retries remain, the session automatically reloads conflicting streams from the store, reconstructs fresh aggregates, re-applies pending events on top of the latest state, and retries the save. This prevents silent event loss when multiple workflows modify the same aggregate concurrently.
- **State-Based Store documentation**: Added comprehensive documentation and examples for `StateBasedStore`:
  - New example: `example/lib/store_state_based.dart` demonstrates `StateBasedStore` with `AggregatePersistenceAdapter`
  - README: Added "State-Based Store" section under "Core Concepts" with construction patterns and adapter implementation examples
  - README: Updated Mode 3 quick-start snippet to use `StateBasedStore` instead of manual backend wiring
  - Example index: Added STATE-BASED PERSISTENCE section for state-based examples

## [4.1.0] - 2026-01-22

### Added

- **Projection System**: A comprehensive read-model projection framework with automatic event-driven updates.
  - `Projection<TReadModel, TKey>`: Base class for event-driven read model maintenance.
  - `SingleStreamProjection<TReadModel>`: Projections that follow a single aggregate stream.
  - `MultiStreamProjection<TReadModel, TKey>`: Projections that aggregate across multiple streams.
  - `ProjectionRegistry`: Central registry for projection registration and lookup.
  - `ReadModelStore<TReadModel, TKey>`: Storage abstraction for read models with `InMemoryReadModelStore` implementation.
  - `ProjectionPositionStore`: Tracks projection progress with `InMemoryProjectionPositionStore` implementation.
  - `InlineProjectionExecutor`: Synchronous execution for strongly-consistent projections.
  - `AsyncProjectionExecutor`: Asynchronous execution for eventually-consistent projections.
  - `PollingProjectionProcessor`: Background processor for async projections.
  - `ProjectionEventStore`: Interface for event stores that support projection queries.
- `EventSourcingStore` now accepts an optional `projections` parameter to enable automatic inline projection execution.
- `InMemoryEventStore` and `HiveEventStore` now implement `ProjectionEventStore` for projection support.

### Fixed

- `continuum_missing_apply_handlers` no longer requires `apply<Event>(...)` handlers for creation events marked with `@AggregateEvent(creation: true)`.
- Fix `ContinuumEvent` contract so core compilation succeeds (restoring required `id`, `occurredOn`, and `metadata` fields).
- Fix `ContinuumEvent.metadata` typing to match examples/generator fixtures (`Map<String, Object?>`).
- Stabilize `continuum_generator` tests in CI by falling back to `.dart_tool/package_config.json` when `Isolate.packageConfig` is unavailable.
- Run `melos run test` with `--concurrency 1` to reduce workspace test flakiness.

## [4.0.0] - 2026-01-14

### Breaking Changes

- **BREAKING**: Creation events are classified via `@AggregateEvent(creation: true)` (no longer inferred from aggregate `create*` methods).

### Added

- Added `creation` flag to `@AggregateEvent` for explicit creation-event declaration.
- Generator now validates that each creation event has a matching `createFrom<Event>` static factory on the aggregate.
- Added a lint that warns when an `@Aggregate()` class is missing required `createFrom<Event>(...)` factories for creation events.
- Added a Quick Fix action to implement missing `createFrom<Event>(...)` factory stubs.
- Updated the example package to show both missing apply handlers and missing creation factories warnings.

## [3.2.0] - 2026-01-14

### Added

- Added a custom lint rule that reports when a non-abstract `@Aggregate()` class mixes in the generated `_$<Aggregate>EventHandlers` but does not implement all required `apply<Event>(...)` methods.
- Added a Quick Fix action to implement missing `apply<Event>(...)` handler stubs.
- Added a runnable example package under `example/` showing the lint in action.

## [3.1.1] - 2026-01-13

### Fixed

- Aggregate event discovery now scans all libraries in the package, so mutation apply methods and dispatch cases are generated even when the aggregate library does not import the event library (the aggregate still must import the event type for compilation).

## [3.1.0] - 2026-01-13

### Added

- Added an example demonstrating code generation for `abstract class` and `abstract interface class` aggregates.

### Fixed

- Combining builder now skips non-library Dart files (e.g. `*.freezed.dart` part files) when scanning `lib/`, preventing build failures in apps using Freezed.

## [3.0.1] - 2026-01-12

### Changed

- Bump `zooper_flutter_core` to `^1.0.3`.

## [3.0.0] - 2026-01-12

### Breaking Changes

- **BREAKING**: `ContinuumEvent` now implements `ZooperDomainEvent` for better integration with other Zooper packages.

### Fixed

- `JsonEventSerializer.deserialize` now always includes a `metadata` key (empty when no stored metadata) in the payload passed to `fromJson`.
- Code generation now emits `ContinuumEvent` for `applyEvent(...)`, `replayEvents(...)`, and `createFromEvent(...)` (instead of the non-existent `DomainEvent`).

## [2.0.0] - 2026-01-08

### Breaking Changes

- **BREAKING**: Renamed `@Event` annotation to `@AggregateEvent` to avoid naming conflicts with user code.
- **BREAKING**: Renamed `ofAggregate:` parameter to `of:` in `@AggregateEvent` annotation.
- **BREAKING**: Renamed `DomainEvent` class to `ContinuumEvent` to avoid naming conflicts.
- **BREAKING**: Renamed `Session` interface to `ContinuumSession` to avoid naming conflicts.
- **BREAKING**: Renamed `StoredEvent.fromDomainEvent()` to `StoredEvent.fromContinuumEvent()`.
- **BREAKING**: Updated all parameter names from `domainEvent` to `continuumEvent`.

### Other Changes

- Updated generator implementation for analyzer 8 API changes.
- Updated generator dependencies for `source_gen ^4.0.0` (including `analyzer` and `build`).

## [1.0.0]

- Initial release with event sourcing core functionality.
- Added `@Aggregate()` and `@Event()` annotations for code generation.
- Added strong types: `EventId`, `StreamId`.
- Added persistence interfaces and store implementations.
- Added exception types for error handling.
