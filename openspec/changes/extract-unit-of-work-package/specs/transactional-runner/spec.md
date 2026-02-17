## MODIFIED Requirements

### Requirement: TransactionalRunner manages session lifecycle

`TransactionalRunner` SHALL move from the `continuum` package to the `continuum_uow` package. It SHALL be a `final class` that manages the lifecycle of a `Session` (renamed from `ContinuumSession`): open session → execute user action → commit → call `CommitHandler`.

#### Scenario: Successful transactional workflow
- **WHEN** `runner.runAsync(() async { ... })` is called
- **THEN** the runner SHALL open a new session via `SessionStore.openSession()`, execute the action, call `saveChangesAsync()`, and call `CommitHandler.onCommitAsync()` if configured

#### Scenario: Action throws an exception
- **WHEN** the action inside `runAsync` throws an exception
- **THEN** the runner SHALL abandon the session without calling `saveChangesAsync()`

#### Scenario: TransactionalRunner removed from continuum
- **WHEN** inspecting the `continuum` package barrel file
- **THEN** it SHALL NOT export `TransactionalRunner`

#### Scenario: TransactionalRunner available from continuum_uow
- **WHEN** a consumer imports `package:continuum_uow/continuum_uow.dart`
- **THEN** `TransactionalRunner` SHALL be available

### Requirement: Ambient session via Zone scoping

`TransactionalRunner` SHALL use Dart's `Zone` mechanism to expose the current session as an ambient value. The static accessors SHALL return `Session` (renamed from `ContinuumSession`).

#### Scenario: Accessing the ambient session inside runAsync
- **WHEN** code inside `runAsync` calls `TransactionalRunner.currentSession`
- **THEN** it SHALL receive the `Session` instance created for that `runAsync` scope

#### Scenario: Accessing the ambient session outside runAsync
- **WHEN** `TransactionalRunner.currentSession` is called outside any `runAsync` scope
- **THEN** it SHALL throw `StateError`

#### Scenario: currentSessionOrNull outside runAsync
- **WHEN** `TransactionalRunner.currentSessionOrNull` is called outside any `runAsync` scope
- **THEN** it SHALL return `null`

### Requirement: Zone isolation between concurrent runAsync calls

Each `runAsync` invocation SHALL create a new `Zone` with its own independent session. Two concurrent `runAsync` calls SHALL NOT share session state.

#### Scenario: Two concurrent workflows with separate sessions
- **WHEN** two `runAsync` calls execute concurrently on the same isolate
- **THEN** each SHALL have its own `Session` instance with independent identity maps

### Requirement: Nested runAsync creates independent transactions

Nested `runAsync` calls SHALL create independent transactions with separate sessions.

#### Scenario: Nested runAsync independence
- **WHEN** `runAsync` is called inside another `runAsync`
- **THEN** the inner call SHALL create a new zone with a new session, commit independently
