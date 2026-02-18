## ADDED Requirements

### Requirement: CommitHandler interface for post-commit operation publishing

`CommitHandler` SHALL be an abstract interface with a single method `onCommitAsync(List<Operation> committedOperations)` that receives committed operations after successful persistence. In event-sourcing contexts, these operations are `ContinuumEvent` instances; in state-based contexts, they may be other `Operation` subtypes.

#### Scenario: Handler called after successful save
- **WHEN** `TransactionalRunner.runAsync` completes and `saveChangesAsync` returns a non-empty list of committed operations
- **THEN** the runner SHALL call `CommitHandler.onCommitAsync` with the full list of committed operations in application order

#### Scenario: Handler not called when save fails
- **WHEN** `saveChangesAsync` throws an exception
- **THEN** `CommitHandler.onCommitAsync` SHALL NOT be called

#### Scenario: Handler not called for empty commits
- **WHEN** `saveChangesAsync` returns an empty list (no pending operations were saved)
- **THEN** `CommitHandler.onCommitAsync` SHALL NOT be called

### Requirement: After-persist semantics

The `CommitHandler` SHALL be called only after operations are durably persisted. If the handler throws, committed operations SHALL remain persisted — no rollback occurs.

#### Scenario: Handler exception does not roll back persistence
- **WHEN** `CommitHandler.onCommitAsync` throws an exception after operations were successfully persisted
- **THEN** the persisted operations SHALL remain durable in the store, and the exception SHALL propagate to the caller of `runAsync`

### Requirement: Handler receives operations not aggregates

`CommitHandler.onCommitAsync` SHALL receive a `List<Operation>` — the operations that were committed. It SHALL NOT receive aggregate instances or aggregate state.

#### Scenario: Handler receives only operation objects
- **WHEN** `onCommitAsync` is called after a commit that included `EmailChanged` and `NameChanged` events
- **THEN** the handler SHALL receive a list containing those `Operation` instances (e.g. `ContinuumEvent` subtypes), without any aggregate references

### Requirement: Projection executor decoupled from session

`SessionImpl` SHALL NOT internally execute inline projections. The `InlineProjectionExecutor` SHALL be consumed as a `CommitHandler` implementation, configured on the `TransactionalRunner` rather than injected into the session.

#### Scenario: Session saves without running projections
- **WHEN** `saveChangesAsync` is called on a session
- **THEN** the session SHALL persist events and return committed events, but SHALL NOT invoke `InlineProjectionExecutor` internally

#### Scenario: Projections run via commit handler
- **WHEN** a projection-based `CommitHandler` is registered on the runner and events are committed
- **THEN** the handler SHALL receive the committed events and execute projections through `InlineProjectionExecutor`
