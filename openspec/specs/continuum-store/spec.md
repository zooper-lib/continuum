## ADDED Requirements

### Requirement: ContinuumStore abstract interface

The system SHALL provide a `ContinuumStore` abstract interface with a single method `openSession()` that returns a `ContinuumSession`.

#### Scenario: ContinuumStore interface shape
- **WHEN** inspecting the `ContinuumStore` interface
- **THEN** it SHALL be an `abstract interface class` with exactly one method: `ContinuumSession openSession()`

### Requirement: EventSourcingStore implements ContinuumStore

`EventSourcingStore` SHALL implement the `ContinuumStore` interface. Its existing `openSession()` method SHALL satisfy the interface contract.

#### Scenario: EventSourcingStore as ContinuumStore
- **WHEN** an `EventSourcingStore` instance is assigned to a variable of type `ContinuumStore`
- **THEN** the assignment SHALL compile and `openSession()` SHALL return a valid `ContinuumSession`

### Requirement: TransactionalRunner accepts ContinuumStore

`TransactionalRunner` SHALL accept a `ContinuumStore` (the interface), not a concrete store implementation. This enables the runner to work with any store implementation without modification.

#### Scenario: Runner works with any ContinuumStore
- **WHEN** a `TransactionalRunner` is created with a `ContinuumStore` reference
- **THEN** the runner SHALL call `openSession()` on that store during `runAsync`, regardless of the underlying implementation

### Requirement: EventSourcingStore no longer accepts ProjectionRegistry

`EventSourcingStore`'s factory constructor SHALL NOT accept a `ProjectionRegistry?` parameter. Projection wiring is handled externally via `CommitHandler` on the `TransactionalRunner`.

#### Scenario: EventSourcingStore construction without projections
- **WHEN** `EventSourcingStore` is constructed
- **THEN** it SHALL accept `eventStore` and `aggregates` as required parameters, and `applicationMode` as an optional parameter, but SHALL NOT accept `projections`

### Requirement: Store swapping preserves workflow code

Switching from one `ContinuumStore` implementation to another SHALL require changes only at the store construction site. Workflow code that uses `ContinuumSession` via the runner SHALL remain unchanged.

#### Scenario: Workflow code independence from store type
- **WHEN** a `TransactionalRunner` is created with `EventSourcingStore` and then later replaced with a different `ContinuumStore` implementation
- **THEN** all workflow code using `TransactionalRunner.currentSession` and `ContinuumSession.applyAsync` / `loadAsync` / `saveChangesAsync` SHALL compile and function without modification
