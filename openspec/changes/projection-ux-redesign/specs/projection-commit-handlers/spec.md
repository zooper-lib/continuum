## ADDED Requirements

### Requirement: ProjectionCommitHandler bridges inline projections

The system SHALL provide a `ProjectionCommitHandler` class in `continuum_uow` (L1) that implements `CommitHandler` and delegates to `InlineProjectionExecutor` (L0).

`ProjectionCommitHandler` SHALL accept an `InlineProjectionExecutor` at construction. On `onCommitAsync(CommitBatch)`, it SHALL call `executor.executeAsync(batch)`.

#### Scenario: ProjectionCommitHandler delegates to InlineProjectionExecutor
- **WHEN** `ProjectionCommitHandler.onCommitAsync(batch)` is called with a `CommitBatch`
- **THEN** it SHALL call `executor.executeAsync(batch)` with the same batch

#### Scenario: ProjectionCommitHandler used with TransactionalRunner
- **WHEN** a `TransactionalRunner` is created with a `ProjectionCommitHandler` as its commit handler
- **THEN** after each successful commit, the runner SHALL pass the `CommitBatch` to the handler, which delegates to the inline executor

#### Scenario: ProjectionCommitHandler propagates executor exceptions
- **WHEN** the `InlineProjectionExecutor` throws during `executeAsync`
- **THEN** `ProjectionCommitHandler.onCommitAsync` SHALL propagate the exception to the caller

### Requirement: AsyncProjectionCommitHandler bridges async projections

The system SHALL provide an `AsyncProjectionCommitHandler` class in `continuum_uow` (L1) that implements `CommitHandler` and delegates to a user-provided callback for async projection processing.

`AsyncProjectionCommitHandler` SHALL accept a callback of type `Future<void> Function(CommitBatch batch)` at construction. On `onCommitAsync(CommitBatch)`, it SHALL invoke the callback with the batch.

#### Scenario: AsyncProjectionCommitHandler invokes callback with CommitBatch
- **WHEN** `AsyncProjectionCommitHandler.onCommitAsync(batch)` is called
- **THEN** it SHALL invoke the user-provided callback with the same `CommitBatch`

#### Scenario: AsyncProjectionCommitHandler supports fire-and-forget enqueueing
- **WHEN** the user provides a callback that enqueues the batch to an in-memory queue
- **THEN** the handler SHALL invoke it and return after the callback completes

#### Scenario: AsyncProjectionCommitHandler propagates callback exceptions
- **WHEN** the user-provided callback throws
- **THEN** `AsyncProjectionCommitHandler.onCommitAsync` SHALL propagate the exception to the caller

### Requirement: Both handlers composable via CompositeCommitHandler

`ProjectionCommitHandler` and `AsyncProjectionCommitHandler` SHALL both implement `CommitHandler` and SHALL be usable together within a `CompositeCommitHandler`.

#### Scenario: Inline and async handlers composed together
- **WHEN** a `CompositeCommitHandler` is created with `[ProjectionCommitHandler, AsyncProjectionCommitHandler]`
- **THEN** on commit, it SHALL call the inline handler first, then the async handler, each receiving the same `CommitBatch`
