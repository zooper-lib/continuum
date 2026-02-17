## MODIFIED Requirements

### Requirement: CommitHandler interface for post-commit event publishing

`CommitHandler` SHALL move from the `continuum` package to the `continuum_uow` package. It SHALL be an abstract interface with a single method `onCommitAsync()` that is called after successful persistence.

The `onCommitAsync` method SHALL NOT accept a `List<ContinuumEvent>` parameter. Since the base `Session.saveChangesAsync` returns `Future<void>`, the commit handler operates as a no-argument callback. ES-specific commit handlers that need access to committed events SHALL obtain them through other mechanisms (e.g., the ES session exposes them via a getter).

#### Scenario: CommitHandler interface shape
- **WHEN** inspecting the `CommitHandler` interface
- **THEN** it SHALL have one method: `Future<void> onCommitAsync()`

#### Scenario: CommitHandler removed from continuum
- **WHEN** inspecting the `continuum` package barrel file
- **THEN** it SHALL NOT export `CommitHandler`

#### Scenario: CommitHandler available from continuum_uow
- **WHEN** a consumer imports `package:continuum_uow/continuum_uow.dart`
- **THEN** `CommitHandler` SHALL be available

### Requirement: After-persist semantics

The `CommitHandler` SHALL be called only after `saveChangesAsync` succeeds. If the handler throws, committed data SHALL remain persisted — no rollback occurs.

#### Scenario: Handler exception does not roll back persistence
- **WHEN** `CommitHandler.onCommitAsync` throws an exception after successful save
- **THEN** the persisted data SHALL remain durable, and the exception SHALL propagate to the caller of `runAsync`

### Requirement: Projection executor decoupled from session

`SessionImpl` (in `continuum_es`) SHALL NOT internally execute inline projections. The `InlineProjectionExecutor` SHALL be consumed as a `CommitHandler` implementation, configured on the `TransactionalRunner` (from `continuum_uow`).

#### Scenario: Session saves without running projections
- **WHEN** `saveChangesAsync` is called on a session
- **THEN** the session SHALL persist events and return committed events, but SHALL NOT invoke `InlineProjectionExecutor` internally

#### Scenario: Projections run via commit handler
- **WHEN** a projection-based `CommitHandler` is registered on the runner and events are committed
- **THEN** the handler SHALL execute projections
