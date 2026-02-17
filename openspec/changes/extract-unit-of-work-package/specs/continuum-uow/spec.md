## ADDED Requirements

### Requirement: Session interface

The system SHALL provide a `Session` abstract interface class as the core Unit of Work contract, with methods for loading, applying operations, saving, and discarding.

#### Scenario: Session interface shape
- **WHEN** inspecting the `Session` interface
- **THEN** it SHALL be an `abstract interface class` with methods `loadAsync`, `loadAllAsync`, `applyAsync`, `saveChangesAsync`, `discardStream`, and `discardAll`

#### Scenario: applyAsync accepts Operation
- **WHEN** `applyAsync<TAggregate>(streamId, operation)` is called
- **THEN** the `operation` parameter type SHALL be `Operation` (not `ContinuumEvent`)

#### Scenario: saveChangesAsync returns Future void
- **WHEN** inspecting the `Session.saveChangesAsync` signature
- **THEN** the return type SHALL be `Future<void>`

#### Scenario: saveChangesAsync accepts maxRetries
- **WHEN** `saveChangesAsync(maxRetries: 3)` is called
- **THEN** the method SHALL accept `maxRetries` as an optional named parameter defaulting to `1`

### Requirement: TrackedEntity identity map entry

The system SHALL provide a `TrackedEntity` final class that holds an entity in the identity map: the cached instance, its runtime type, the version when loaded, and pending operations.

#### Scenario: TrackedEntity construction
- **WHEN** a `TrackedEntity` is created with entity, entityType, loadedVersion, and pendingOperations
- **THEN** all fields SHALL be accessible and `pendingOperations` SHALL default to an empty list if not provided

#### Scenario: TrackedEntity uses Operation for pending operations
- **WHEN** inspecting the `pendingOperations` field
- **THEN** its type SHALL be `List<Operation>` (not `List<ContinuumEvent>`)

#### Scenario: withClearedPendingOperations creates a copy
- **WHEN** `withClearedPendingOperations()` is called on a `TrackedEntity` with pending operations
- **THEN** it SHALL return a new `TrackedEntity` with the same entity, entityType, and loadedVersion but an empty `pendingOperations` list

### Requirement: SessionBase abstract class with 3-path detection

The system SHALL provide a `SessionBase` abstract class implementing `Session` that contains persistence-agnostic session logic: identity map, 3-path `applyAsync` detection, eager/deferred branching, creation guard, and discard operations.

#### Scenario: SessionBase constructor dependencies
- **WHEN** `SessionBase` is constructed
- **THEN** it SHALL require `AggregateFactoryRegistry`, `EventApplierRegistry`, and `EventApplicationMode` (all from the `continuum` package)

#### Scenario: Path 1 — already tracked entity
- **WHEN** `applyAsync` is called for a stream ID already in the identity map
- **THEN** the operation SHALL be appended to pending operations and (in eager mode) applied to the in-memory entity without loading from persistence

#### Scenario: Path 2 — creation operation
- **WHEN** `applyAsync` is called with an operation that has a registered factory and the stream is not tracked
- **THEN** the entity SHALL be created via the `AggregateFactoryRegistry`, tracked in the identity map with `loadedVersion: -1`, and returned

#### Scenario: Path 3 — mutation on untracked entity
- **WHEN** `applyAsync` is called with a non-creation operation for an untracked stream
- **THEN** `SessionBase` SHALL delegate to the abstract `handleMutationOnUntrackedEntity` method

#### Scenario: Creation guard on tracked entity
- **WHEN** `applyAsync` is called with a creation operation for a stream that is already tracked
- **THEN** `SessionBase` SHALL throw `InvalidOperationException`

#### Scenario: Eager mode applies operation immediately
- **WHEN** the session is in `EventApplicationMode.eager` and an operation is appended
- **THEN** the operation SHALL be applied to the entity immediately via `applyOperationByRuntimeType`

#### Scenario: Deferred mode records without applying
- **WHEN** the session is in `EventApplicationMode.deferred` and an operation is appended
- **THEN** the operation SHALL be recorded as pending but NOT applied until `applyDeferredOperations` is called

#### Scenario: Deferred operations flushed before save
- **WHEN** `applyDeferredOperations` is called with pending entries in deferred mode
- **THEN** all pending operations SHALL be applied to their entities in order, skipping the creation operation (index 0) for new entities

#### Scenario: applyAsync accepts Operation type
- **WHEN** `applyAsync` is called with a plain `Operation` implementation (not `ContinuumEvent`)
- **THEN** the session SHALL process it identically to a `ContinuumEvent` — the session layer is ES-agnostic

### Requirement: SessionBase subclass extension point

`SessionBase` SHALL define four abstract methods that subclasses implement for their specific persistence strategy.

#### Scenario: Required abstract methods
- **WHEN** a class extends `SessionBase`
- **THEN** it SHALL implement `loadAsync`, `loadAllAsync`, `saveChangesAsync`, and `handleMutationOnUntrackedEntity`

#### Scenario: Custom strategy extends SessionBase
- **WHEN** a user extends `SessionBase` and implements the four abstract methods
- **THEN** they SHALL get the identity map, 3-path detection, eager/deferred mode, creation guard, and discard operations for free

### Requirement: SessionStore interface

The system SHALL provide a `SessionStore` abstract interface class as the session factory.

#### Scenario: SessionStore interface shape
- **WHEN** inspecting the `SessionStore` interface
- **THEN** it SHALL be an `abstract interface class` with exactly one method: `Session openSession()`

### Requirement: TransactionalRunner zone-scoped lifecycle

The system SHALL provide a `TransactionalRunner` final class that manages session lifecycle: open session, execute action in a zone-scoped context, auto-commit on success, and publish via `CommitHandler`.

#### Scenario: Successful transactional workflow
- **WHEN** `runner.runAsync(() async { ... })` is called
- **THEN** the runner SHALL open a new session via `SessionStore.openSession()`, execute the action, call `saveChangesAsync()` on the session, and call `CommitHandler.onCommitAsync()` if configured

#### Scenario: Action throws — no commit
- **WHEN** the action inside `runAsync` throws an exception
- **THEN** the runner SHALL NOT call `saveChangesAsync()` and the exception SHALL propagate

#### Scenario: Ambient session via currentSession
- **WHEN** code inside `runAsync` calls `TransactionalRunner.currentSession`
- **THEN** it SHALL receive the `Session` instance for that scope

#### Scenario: currentSession outside runAsync throws
- **WHEN** `TransactionalRunner.currentSession` is called outside any `runAsync` scope
- **THEN** it SHALL throw `StateError`

#### Scenario: currentSessionOrNull outside runAsync
- **WHEN** `TransactionalRunner.currentSessionOrNull` is called outside any `runAsync` scope
- **THEN** it SHALL return `null`

#### Scenario: Nested runAsync creates independent sessions
- **WHEN** `runAsync` is called inside another `runAsync`
- **THEN** the inner call SHALL create a new zone with a new session, committing independently

#### Scenario: No commit handler is valid
- **WHEN** a `TransactionalRunner` is created without a `commitHandler`
- **THEN** events SHALL be persisted but no post-commit step occurs

### Requirement: CommitHandler post-commit hook

The system SHALL provide a `CommitHandler` abstract interface with a single method for post-commit side effects.

#### Scenario: CommitHandler interface shape
- **WHEN** inspecting the `CommitHandler` interface
- **THEN** it SHALL have one method: `Future<void> onCommitAsync()`

#### Scenario: Handler called after successful save
- **WHEN** `runAsync` completes and `saveChangesAsync` succeeds
- **THEN** `CommitHandler.onCommitAsync()` SHALL be called

#### Scenario: Handler not called when save fails
- **WHEN** `saveChangesAsync` throws an exception
- **THEN** `CommitHandler.onCommitAsync()` SHALL NOT be called

### Requirement: ConcurrencyException

The system SHALL provide a `ConcurrencyException` class for optimistic concurrency conflicts, with `streamId`, `expectedVersion`, `actualVersion`, and `message` fields.

#### Scenario: ConcurrencyException construction
- **WHEN** a `ConcurrencyException` is created with streamId, expectedVersion, actualVersion, and message
- **THEN** all fields SHALL be accessible

#### Scenario: ConcurrencyException implements Exception
- **WHEN** inspecting `ConcurrencyException`
- **THEN** it SHALL implement `Exception`

### Requirement: InvalidOperationException

The system SHALL provide an `InvalidOperationException` final class with a `message` field.

#### Scenario: InvalidOperationException construction
- **WHEN** an `InvalidOperationException` is created with a message
- **THEN** the `message` field SHALL be accessible

#### Scenario: InvalidOperationException implements Exception
- **WHEN** inspecting `InvalidOperationException`
- **THEN** it SHALL be a `final class` that implements `Exception`

### Requirement: UnsupportedOperationException

The system SHALL provide an `UnsupportedOperationException` final class thrown when no applier or factory is registered for an operation type. It SHALL have `operationType` and `aggregateType` fields.

#### Scenario: UnsupportedOperationException construction
- **WHEN** an `UnsupportedOperationException` is created with operationType and aggregateType
- **THEN** both fields SHALL be accessible

#### Scenario: UnsupportedOperationException implements Exception
- **WHEN** inspecting `UnsupportedOperationException`
- **THEN** it SHALL be a `final class` that implements `Exception`

### Requirement: PartialSaveException

The system SHALL provide a `PartialSaveException` final class with `savedStreams`, `failedStreams`, and `cause` fields.

#### Scenario: PartialSaveException construction
- **WHEN** a `PartialSaveException` is created with savedStreams, failedStreams, and cause
- **THEN** all fields SHALL be accessible

#### Scenario: PartialSaveException implements Exception
- **WHEN** inspecting `PartialSaveException`
- **THEN** it SHALL be a `final class` that implements `Exception`

### Requirement: Backward-compatibility typedefs

The system SHALL provide typedefs for renamed types to ease migration.

#### Scenario: ContinuumSession typedef
- **WHEN** code references `ContinuumSession` from the `continuum_uow` package
- **THEN** it SHALL resolve to `Session`

#### Scenario: ContinuumStore typedef
- **WHEN** code references `ContinuumStore` from the `continuum_uow` package
- **THEN** it SHALL resolve to `SessionStore`

#### Scenario: UnsupportedEventException typedef
- **WHEN** code references `UnsupportedEventException` from the `continuum_uow` package
- **THEN** it SHALL resolve to `UnsupportedOperationException`

### Requirement: Package depends on continuum core

The `continuum_uow` package SHALL depend on `continuum` (Layer 0) for `Operation`, `AggregateFactoryRegistry`, `EventApplierRegistry`, `EventApplicationMode`, `StreamId`, and `GeneratedAggregate`.

#### Scenario: UoW imports from continuum
- **WHEN** `SessionBase` needs registry and mode types
- **THEN** they SHALL be imported from `package:continuum/continuum.dart`

#### Scenario: UoW does not contain core types
- **WHEN** inspecting the `continuum_uow` package
- **THEN** it SHALL NOT define `Operation`, `AggregateFactoryRegistry`, `EventApplierRegistry`, or `StreamId` — these remain in `continuum`

### Requirement: Barrel file exports all public types

The `continuum_uow` package SHALL export all public types from `lib/continuum_uow.dart`.

#### Scenario: Barrel file completeness
- **WHEN** a consumer imports `package:continuum_uow/continuum_uow.dart`
- **THEN** `Session`, `SessionBase`, `TrackedEntity`, `SessionStore`, `TransactionalRunner`, `CommitHandler`, `ConcurrencyException`, `InvalidOperationException`, `UnsupportedOperationException`, and `PartialSaveException` SHALL all be available
