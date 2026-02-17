## ADDED Requirements

### Requirement: Single applyAsync method replaces startStream and append

`ContinuumSession` SHALL expose a single `applyAsync<TAggregate>(StreamId, ContinuumEvent)` method that replaces the previous `startStream` and `append` methods. The method SHALL return `Future<TAggregate>` with the aggregate in its post-event state (when using eager application mode).

#### Scenario: Applying a creation event to a new stream
- **WHEN** `applyAsync<User>(streamId, UserRegistered(...))` is called and no stream with that ID is tracked in the session
- **THEN** the method SHALL probe `AggregateFactoryRegistry.getFactory<User>(User, UserRegistered)`, find a creation factory, create the aggregate from the event, begin tracking the stream, and return the newly created aggregate

#### Scenario: Applying a mutation event to an untracked stream
- **WHEN** `applyAsync<User>(streamId, EmailChanged(...))` is called, no stream with that ID is tracked, and no creation factory exists for `EmailChanged`
- **THEN** the method SHALL call `loadAsync<User>(streamId)` to hydrate the aggregate from the store, apply the event to the loaded aggregate, and return the mutated aggregate

#### Scenario: Applying an event to an already-tracked stream
- **WHEN** `applyAsync<User>(streamId, EmailChanged(...))` is called and the stream is already tracked in the session's identity map
- **THEN** the method SHALL apply the event directly to the cached aggregate (fast path) without accessing the store, and return the aggregate

#### Scenario: Applying a mutation event to a non-existent stream
- **WHEN** `applyAsync<User>(streamId, EmailChanged(...))` is called, no stream is tracked, no creation factory exists, and the stream does not exist in the store
- **THEN** the method SHALL throw `StreamNotFoundException`

### Requirement: Creation events are rejected for already-tracked streams

`applyAsync` SHALL enforce a strict creation guard: if the event is a creation event (has a registered factory) AND the stream is already tracked in the session, the method SHALL throw `InvalidOperationException`.

#### Scenario: Creation event applied to an already-loaded stream
- **WHEN** a stream has been loaded via `loadAsync` or a previous `applyAsync` call, and then `applyAsync` is called with a creation event for the same stream ID
- **THEN** the method SHALL throw `InvalidOperationException` with a message indicating that creation events are only valid for new streams

### Requirement: startStream and append are removed from ContinuumSession

`ContinuumSession` SHALL NOT expose `startStream` or `append` methods. Their logic is folded into `applyAsync` and private internal methods.

#### Scenario: ContinuumSession public API surface
- **WHEN** inspecting the `ContinuumSession` interface
- **THEN** it SHALL expose exactly: `applyAsync`, `loadAsync`, `saveChangesAsync`, `discardStream`, and `discardAll`

### Requirement: loadAsync remains for read-only access

`ContinuumSession` SHALL retain `loadAsync<TAggregate>(StreamId)` for loading an aggregate without applying any event.

#### Scenario: Loading before conditionally mutating
- **WHEN** `loadAsync<User>(streamId)` is called followed by `applyAsync<User>(streamId, event)`
- **THEN** the second call SHALL hit the "already tracked" fast path and not access the store again

### Requirement: saveChangesAsync returns committed events

`saveChangesAsync` SHALL return `Future<List<ContinuumEvent>>` containing all events from all streams that were successfully persisted, ordered by stream in persistence order. After return, all pending event lists SHALL be cleared.

#### Scenario: Saving multiple events across streams
- **WHEN** two events are applied to stream A and one event to stream B, then `saveChangesAsync` is called
- **THEN** the method SHALL return a list of three `ContinuumEvent` instances in stream order, and pending event lists for both streams SHALL be empty

#### Scenario: Saving with no pending events
- **WHEN** `saveChangesAsync` is called with no pending events in any tracked stream
- **THEN** the method SHALL return an empty list

#### Scenario: Concurrency retry returns original events
- **WHEN** a concurrency conflict occurs during save and the session retries successfully
- **THEN** the returned list SHALL contain the same logical events that were originally applied
