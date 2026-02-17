## MODIFIED Requirements

### Requirement: StateBasedSession implements ContinuumSession

`StateBasedSession` SHALL implement the `Session` interface (from `continuum_uow`, renamed from `ContinuumSession`) by extending `SessionBase` (from `continuum_uow`). It SHALL implement `loadAsync`, `loadAllAsync`, `saveChangesAsync`, and `handleMutationOnUntrackedEntity`.

`StateBasedSession` SHALL move from the `continuum` package to the `continuum_state` package.

#### Scenario: StateBasedSession extends SessionBase
- **WHEN** inspecting `StateBasedSession`
- **THEN** it SHALL extend `SessionBase` (from `continuum_uow`) and implement the four abstract methods

#### Scenario: StateBasedSession removed from continuum
- **WHEN** inspecting the `continuum` package barrel file
- **THEN** it SHALL NOT export `StateBasedSession`

### Requirement: applyAsync uses shared 3-path detection logic

`StateBasedSession.applyAsync` SHALL use the same 3-path detection as before, inherited from `SessionBase` (now in `continuum_uow`). The logic SHALL work with `Operation` (not `ContinuumEvent`) as the mutation type.

#### Scenario: Apply with plain Operation
- **WHEN** `applyAsync<TAggregate>(streamId, operation)` is called with a plain `Operation` implementation
- **THEN** the session SHALL process it identically — the 3-path detection is ES-agnostic

#### Scenario: Apply with ContinuumEvent still works
- **WHEN** `applyAsync<TAggregate>(streamId, event)` is called with a `ContinuumEvent`
- **THEN** the session SHALL process it normally since `ContinuumEvent implements Operation`

### Requirement: SessionBase extracts shared session logic

`SessionBase` SHALL be provided by the `continuum_uow` package (not `continuum`). `StateBasedSession` SHALL extend it from the `continuum_uow` dependency.

#### Scenario: SessionImpl behavior unchanged after extraction
- **WHEN** `SessionImpl` (in `continuum_es`) is refactored to extend `SessionBase` (from `continuum_uow`)
- **THEN** all existing `SessionImpl` tests SHALL pass without modification

#### Scenario: StateBasedSession extends SessionBase from UoW
- **WHEN** `StateBasedSession` extends `SessionBase`
- **THEN** the import SHALL be from `package:continuum_uow/continuum_uow.dart`
