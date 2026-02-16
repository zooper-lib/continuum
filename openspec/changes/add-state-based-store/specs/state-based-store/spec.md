## ADDED Requirements

### Requirement: StateBasedStore implements ContinuumStore

`StateBasedStore` SHALL be a `final class` that implements `ContinuumStore`. Its `openSession()` method SHALL return a `ContinuumSession` instance backed by `AggregatePersistenceAdapter` instances.

#### Scenario: StateBasedStore is assignable to ContinuumStore
- **WHEN** a `StateBasedStore` instance is assigned to a variable of type `ContinuumStore`
- **THEN** the assignment SHALL compile and `openSession()` SHALL return a valid `ContinuumSession`

### Requirement: StateBasedStore constructor accepts adapter map and aggregates

`StateBasedStore` SHALL accept a `Map<Type, AggregatePersistenceAdapter<Object>>` keyed by aggregate type, and a `List<GeneratedAggregate>` for event applier and factory registries. It SHALL accept an optional `EventApplicationMode` parameter defaulting to `EventApplicationMode.eager`.

#### Scenario: Construction with adapters and aggregates
- **WHEN** `StateBasedStore` is constructed with an adapter map `{User: UserApiAdapter(...)}` and aggregates `[$User]`
- **THEN** `openSession()` SHALL return a session that can load, apply events to, and save `User` aggregates via the provided adapter

#### Scenario: Construction with explicit application mode
- **WHEN** `StateBasedStore` is constructed with `applicationMode: EventApplicationMode.deferred`
- **THEN** the sessions it creates SHALL use deferred event application mode

#### Scenario: Construction with default application mode
- **WHEN** `StateBasedStore` is constructed without specifying `applicationMode`
- **THEN** the sessions it creates SHALL use `EventApplicationMode.eager`

### Requirement: StateBasedStore does not depend on EventStore or EventSerializer

`StateBasedStore` SHALL NOT require an `EventStore`, `EventSerializer`, or `EventSerializerRegistry`. It SHALL use only `AggregatePersistenceAdapter` instances for persistence and `AggregateFactoryRegistry` / `EventApplierRegistry` from the provided `GeneratedAggregate` list for event application.

#### Scenario: No event store required
- **WHEN** `StateBasedStore` is constructed
- **THEN** its constructor SHALL NOT accept an `EventStore` parameter

### Requirement: StateBasedStore openSession produces independent sessions

Each call to `StateBasedStore.openSession()` SHALL return a new, independent `ContinuumSession` instance. Sessions SHALL NOT share mutable state.

#### Scenario: Two sessions from same store are independent
- **WHEN** `openSession()` is called twice on the same `StateBasedStore`
- **THEN** events applied in one session SHALL NOT be visible in the other session

### Requirement: StateBasedStore works with TransactionalRunner

`StateBasedStore` SHALL be usable as the store for a `TransactionalRunner`. The runner's `runAsync` SHALL open a session, execute the action, and commit via the session's `saveChangesAsync` — identical to how it works with `EventSourcingStore`.

#### Scenario: TransactionalRunner with StateBasedStore
- **WHEN** a `TransactionalRunner` is created with a `StateBasedStore` and `runAsync` is called
- **THEN** the runner SHALL open a session from the store, make it available via `TransactionalRunner.currentSession`, auto-commit on success, and call the `CommitHandler` with committed events

### Requirement: Workflow code is unchanged between store types

Workflow code that uses `ContinuumSession` via `TransactionalRunner.currentSession` SHALL compile and function identically regardless of whether the underlying store is `EventSourcingStore` or `StateBasedStore`.

#### Scenario: Same workflow with different stores
- **WHEN** a workflow calls `session.applyAsync<User>(id, SomeEvent(...))` and `session.saveChangesAsync()`
- **THEN** the workflow code SHALL be identical for both `EventSourcingStore` and `StateBasedStore` — only the store construction site changes
