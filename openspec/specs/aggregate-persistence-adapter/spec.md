## ADDED Requirements

### Requirement: AggregatePersistenceAdapter interface

The system SHALL provide an `AggregatePersistenceAdapter<TAggregate>` abstract interface with two methods: `fetchAsync` for loading aggregate state from a backend, and `persistAsync` for saving changes to a backend.

#### Scenario: Adapter interface shape
- **WHEN** inspecting `AggregatePersistenceAdapter<TAggregate>`
- **THEN** it SHALL be an `abstract interface class` with `Future<TAggregate> fetchAsync(StreamId streamId)` and `Future<void> persistAsync(StreamId streamId, TAggregate aggregate, List<ContinuumEvent> pendingEvents)`

### Requirement: fetchAsync returns a hydrated aggregate

`fetchAsync` SHALL return a fully constructed aggregate instance. The adapter is responsible for calling the backend, receiving the response, and constructing the aggregate from it. The session SHALL NOT know how hydration works.

#### Scenario: Adapter fetches and hydrates from backend
- **WHEN** the session needs to load an aggregate in state-based mode
- **THEN** it SHALL call `adapter.fetchAsync(streamId)` and receive a fully hydrated `TAggregate` instance without needing to know the backend's response format

### Requirement: persistAsync receives aggregate and pending events

`persistAsync` SHALL receive the stream ID, the aggregate in its post-event state, and the list of pending domain events. The adapter SHALL use these to construct whatever backend call(s) are appropriate.

#### Scenario: Adapter receives both state and events
- **WHEN** `persistAsync` is called after `applyAsync` recorded `EmailChanged` and `NameChanged` events
- **THEN** the adapter SHALL receive the final aggregate state plus a list containing both `EmailChanged` and `NameChanged` events, and SHALL decide independently how to translate these into backend API calls

### Requirement: persistAsync atomicity contract

`persistAsync` SHALL be all-or-nothing. Either all changes for the given stream are persisted, or the method throws and no changes are committed for that stream.

#### Scenario: Partial persistence failure within a stream
- **WHEN** the adapter's internal logic fails partway through persisting changes for a single stream
- **THEN** the adapter SHALL throw an exception and ensure no partial changes are committed to the backend for that stream

### Requirement: Domain events are not sent to the backend as events

The adapter SHALL use pending events to understand what changed and construct appropriate API calls. Domain events are a local mutation mechanism — the adapter SHALL NOT be required to send them to the backend in event form.

#### Scenario: Adapter translates events to API calls
- **WHEN** `persistAsync` receives `[EmailChanged, NameChanged]` as pending events
- **THEN** the adapter MAY send a single `PATCH` request, multiple requests, or a batch command — the framework SHALL NOT prescribe the wire format

### Requirement: Adapter interface is defined without implementation

The `AggregatePersistenceAdapter` interface SHALL be defined in this change. No `StateBasedStore` or `StateBasedSession` implementation SHALL be created in this change — the interface is provided for future use and design validation.

#### Scenario: Interface exists without store implementation
- **WHEN** the `AggregatePersistenceAdapter` interface is defined
- **THEN** no concrete `StateBasedStore` class SHALL exist in the codebase as part of this change
