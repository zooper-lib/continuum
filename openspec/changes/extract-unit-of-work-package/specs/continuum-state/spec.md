## ADDED Requirements

### Requirement: StateBasedStore implements SessionStore

The system SHALL provide a `StateBasedStore` final class that implements `SessionStore` (from `continuum_uow`). Its `openSession()` method SHALL return a `Session` instance backed by `AggregatePersistenceAdapter` instances.

#### Scenario: StateBasedStore is assignable to SessionStore
- **WHEN** a `StateBasedStore` instance is assigned to a variable of type `SessionStore`
- **THEN** the assignment SHALL compile and `openSession()` SHALL return a valid `Session`

#### Scenario: StateBasedStore construction
- **WHEN** `StateBasedStore` is constructed
- **THEN** it SHALL accept a `Map<Type, AggregatePersistenceAdapter<Object>>`, a `List<GeneratedAggregate>`, and an optional `EventApplicationMode` defaulting to eager

### Requirement: StateBasedSession extends SessionBase

The system SHALL provide a `StateBasedSession` class that extends `SessionBase` (from `continuum_uow`) and implements state-based persistence via adapters.

#### Scenario: StateBasedSession extends SessionBase
- **WHEN** inspecting `StateBasedSession`
- **THEN** it SHALL extend `SessionBase` and implement `loadAsync`, `loadAllAsync`, `saveChangesAsync`, and `handleMutationOnUntrackedEntity`

#### Scenario: loadAsync delegates to adapter fetchAsync
- **WHEN** `loadAsync<TAggregate>(streamId)` is called for an untracked stream
- **THEN** the session SHALL call `adapter.fetchAsync(streamId)` and track the result

#### Scenario: saveChangesAsync delegates to adapter persistAsync
- **WHEN** `saveChangesAsync()` is called with pending operations
- **THEN** the session SHALL call `adapter.persistAsync` for each stream with pending operations

### Requirement: AggregatePersistenceAdapter interface

The system SHALL provide an `AggregatePersistenceAdapter<TAggregate>` abstract interface with `fetchAsync` and `persistAsync` methods.

#### Scenario: Adapter interface shape
- **WHEN** inspecting `AggregatePersistenceAdapter<TAggregate>`
- **THEN** it SHALL have `Future<TAggregate> fetchAsync(StreamId streamId)` and `Future<void> persistAsync(StreamId streamId, TAggregate aggregate, List<Operation> pendingOperations)`

#### Scenario: persistAsync receives Operations not ContinuumEvents
- **WHEN** inspecting the `persistAsync` parameter type for pending operations
- **THEN** it SHALL be `List<Operation>` (not `List<ContinuumEvent>`)

### Requirement: PermanentAdapterException

The system SHALL provide a `PermanentAdapterException` final class for permanent backend failures with `message` and optional `cause` fields.

#### Scenario: PermanentAdapterException construction
- **WHEN** a `PermanentAdapterException` is created with a message
- **THEN** the `message` field SHALL be accessible

#### Scenario: PermanentAdapterException implements Exception
- **WHEN** inspecting `PermanentAdapterException`
- **THEN** it SHALL be a `final class` that implements `Exception`

### Requirement: TransientAdapterException

The system SHALL provide a `TransientAdapterException` final class for transient backend failures with `message` and optional `cause` fields.

#### Scenario: TransientAdapterException construction
- **WHEN** a `TransientAdapterException` is created with message and cause
- **THEN** both fields SHALL be accessible

#### Scenario: TransientAdapterException implements Exception
- **WHEN** inspecting `TransientAdapterException`
- **THEN** it SHALL be a `final class` that implements `Exception`

### Requirement: Barrel file exports all state-based types

The `continuum_state` package SHALL export all public types from `lib/continuum_state.dart`.

#### Scenario: Barrel file completeness
- **WHEN** a consumer imports `package:continuum_state/continuum_state.dart`
- **THEN** `StateBasedStore`, `StateBasedSession`, `AggregatePersistenceAdapter`, `PermanentAdapterException`, and `TransientAdapterException` SHALL all be available

### Requirement: Package depends on continuum and continuum_uow

The `continuum_state` package SHALL depend on `continuum` (Layer 0) and `continuum_uow` (Layer 1).

#### Scenario: Dependency chain
- **WHEN** inspecting `continuum_state` pubspec.yaml
- **THEN** it SHALL list `continuum` and `continuum_uow` as dependencies
