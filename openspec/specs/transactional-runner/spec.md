## ADDED Requirements

### Requirement: TransactionalRunner manages session lifecycle

`TransactionalRunner` SHALL be a `final class` that manages the full lifecycle of a `ContinuumSession`: open session → execute user action → commit pending events → publish committed events via `CommitHandler`.

#### Scenario: Successful transactional workflow
- **WHEN** `runner.runAsync(() async { ... })` is called
- **THEN** the runner SHALL open a new session via `ContinuumStore.openSession()`, execute the user's action, call `saveChangesAsync()` on the session after the action completes, and call `CommitHandler.onCommitAsync(events)` if a handler is configured and committed events are non-empty

#### Scenario: Action throws an exception
- **WHEN** the user's action inside `runAsync` throws an exception
- **THEN** the runner SHALL abandon the session without calling `saveChangesAsync()`, and the exception SHALL propagate to the caller

#### Scenario: runAsync returns the action's result
- **WHEN** `runAsync<T>` is called and the action returns a value of type `T`
- **THEN** the runner SHALL return that value to the caller after commit and publish succeed

### Requirement: Ambient session via Zone scoping

`TransactionalRunner` SHALL use Dart's `Zone` mechanism to expose the current session as an ambient value accessible via a static accessor, without requiring explicit parameter passing.

#### Scenario: Accessing the ambient session inside runAsync
- **WHEN** code inside `runAsync` calls `TransactionalRunner.currentSession`
- **THEN** it SHALL receive the `ContinuumSession` instance created for that `runAsync` scope

#### Scenario: Accessing the ambient session outside runAsync
- **WHEN** `TransactionalRunner.currentSession` is called outside any `runAsync` scope
- **THEN** it SHALL throw `StateError`

#### Scenario: currentSessionOrNull outside runAsync
- **WHEN** `TransactionalRunner.currentSessionOrNull` is called outside any `runAsync` scope
- **THEN** it SHALL return `null`

### Requirement: Zone isolation between concurrent runAsync calls

Each `runAsync` invocation SHALL create a new `Zone` with its own independent session. Two concurrent `runAsync` calls on the same isolate SHALL NOT share session state.

#### Scenario: Two concurrent workflows with separate sessions
- **WHEN** two `runAsync` calls execute concurrently on the same isolate
- **THEN** each SHALL have its own `ContinuumSession` instance with independent `_StreamState` maps, and changes in one session SHALL NOT be visible in the other

### Requirement: Nested runAsync creates independent transactions

Nested `runAsync` calls SHALL create independent transactions with separate sessions. The inner `runAsync` SHALL NOT share or extend the outer session.

#### Scenario: Nested runAsync independence
- **WHEN** `runAsync` is called inside another `runAsync`
- **THEN** the inner call SHALL create a new zone with a new session, commit independently, and restore the outer session's zone when complete

### Requirement: Composing workflows within a single transaction

Workflows that need to share a session and commit atomically SHALL be composed within a single `runAsync` scope by calling sub-workflows that access `TransactionalRunner.currentSession`.

#### Scenario: Sub-workflows share a session
- **WHEN** two workflow functions both call `TransactionalRunner.currentSession` inside the same `runAsync` scope
- **THEN** both SHALL receive the same `ContinuumSession` instance, and all events from both workflows SHALL be committed together in a single `saveChangesAsync` call

### Requirement: No commit handler is valid

`TransactionalRunner` SHALL accept an optional `CommitHandler`. If no handler is provided, events SHALL be persisted but no post-commit publishing occurs.

#### Scenario: Runner without a commit handler
- **WHEN** a `TransactionalRunner` is created without a `commitHandler` and `runAsync` completes successfully
- **THEN** `saveChangesAsync` SHALL be called and committed events SHALL be persisted, but no publish step occurs
