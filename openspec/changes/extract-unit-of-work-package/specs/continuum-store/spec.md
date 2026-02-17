## MODIFIED Requirements

### Requirement: ContinuumStore abstract interface

The system SHALL provide a `ContinuumStore` abstract interface with a single method `openSession()` that returns a `ContinuumSession`.

`ContinuumStore` SHALL be a backward-compatibility typedef for `SessionStore` (from `continuum_uow`). `ContinuumSession` SHALL be a backward-compatibility typedef for `Session` (from `continuum_uow`). Both typedefs SHALL be provided by the `continuum_uow` package.

The `ContinuumStore` interface and `ContinuumSession` interface SHALL be removed from the `continuum` package. They move to `continuum_uow` as `SessionStore` and `Session` respectively.

#### Scenario: ContinuumStore is a typedef for SessionStore
- **WHEN** code references `ContinuumStore` from `continuum_uow`
- **THEN** it SHALL resolve to `SessionStore`

#### Scenario: ContinuumSession is a typedef for Session
- **WHEN** code references `ContinuumSession` from `continuum_uow`
- **THEN** it SHALL resolve to `Session`

#### Scenario: Types removed from continuum package
- **WHEN** inspecting the `continuum` package barrel file
- **THEN** it SHALL NOT export `ContinuumStore` or `ContinuumSession`

### Requirement: TransactionalRunner accepts ContinuumStore

`TransactionalRunner` SHALL accept a `SessionStore` (renamed from `ContinuumStore`). The `TransactionalRunner` class SHALL be removed from the `continuum` package and provided by `continuum_uow`.

#### Scenario: Runner works with any SessionStore
- **WHEN** a `TransactionalRunner` is created with a `SessionStore` reference
- **THEN** the runner SHALL call `openSession()` on that store during `runAsync`, regardless of the underlying implementation

#### Scenario: TransactionalRunner removed from continuum
- **WHEN** inspecting the `continuum` package barrel file
- **THEN** it SHALL NOT export `TransactionalRunner`

### Requirement: Store swapping preserves workflow code

Switching from one `SessionStore` implementation to another SHALL require changes only at the store construction site. Workflow code that uses `Session` via the runner SHALL remain unchanged.

#### Scenario: Workflow code independence from store type
- **WHEN** a `TransactionalRunner` is created with `EventSourcingStore` and then later replaced with a different `SessionStore` implementation
- **THEN** all workflow code using `TransactionalRunner.currentSession` and `Session.applyAsync` / `loadAsync` / `saveChangesAsync` SHALL compile and function without modification

## REMOVED Requirements

### Requirement: EventSourcingStore implements ContinuumStore

**Reason**: `EventSourcingStore` moves to `continuum_es` package and implements `SessionStore` (from `continuum_uow`) instead.
**Migration**: Use `SessionStore` from `continuum_uow`. `EventSourcingStore` is available from `continuum_es`.

### Requirement: EventSourcingStore no longer accepts ProjectionRegistry

**Reason**: `EventSourcingStore` moves to `continuum_es` package. This requirement is restated in the `continuum-es` capability spec.
**Migration**: Import `EventSourcingStore` from `package:continuum_es/continuum_es.dart`.
