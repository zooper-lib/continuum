## MODIFIED Requirements

### Requirement: StateBasedStore implements ContinuumStore

`StateBasedStore` SHALL be a `final class` that implements `SessionStore` (from `continuum_uow`, renamed from `ContinuumStore`). Its `openSession()` method SHALL return a `Session` instance backed by `AggregatePersistenceAdapter` instances.

`StateBasedStore` SHALL move from the `continuum` package to the `continuum_state` package.

#### Scenario: StateBasedStore is assignable to SessionStore
- **WHEN** a `StateBasedStore` instance is assigned to a variable of type `SessionStore`
- **THEN** the assignment SHALL compile and `openSession()` SHALL return a valid `Session`

#### Scenario: StateBasedStore removed from continuum
- **WHEN** inspecting the `continuum` package barrel file
- **THEN** it SHALL NOT export `StateBasedStore`

### Requirement: StateBasedStore constructor accepts adapter map and aggregates

`StateBasedStore` SHALL accept a `Map<Type, AggregatePersistenceAdapter<Object>>` keyed by aggregate type, and a `List<GeneratedAggregate>` for event applier and factory registries. It SHALL accept an optional `EventApplicationMode` parameter defaulting to `EventApplicationMode.eager`.

#### Scenario: Construction with adapters and aggregates
- **WHEN** `StateBasedStore` is constructed with an adapter map `{User: UserApiAdapter(...)}` and aggregates `[$User]`
- **THEN** `openSession()` SHALL return a session that can load, apply operations to, and save `User` aggregates via the provided adapter

### Requirement: StateBasedStore works with TransactionalRunner

`StateBasedStore` SHALL be usable as the store for a `TransactionalRunner` (from `continuum_uow`). The runner's `runAsync` SHALL open a session, execute the action, and commit via the session's `saveChangesAsync`.

#### Scenario: TransactionalRunner with StateBasedStore
- **WHEN** a `TransactionalRunner` is created with a `StateBasedStore` and `runAsync` is called
- **THEN** the runner SHALL open a session from the store, make it available via `TransactionalRunner.currentSession`, and auto-commit on success
