## ADDED Requirements

### Requirement: StateBasedSession implements ContinuumSession

`StateBasedSession` SHALL implement the `ContinuumSession` interface with `loadAsync`, `applyAsync`, `saveChangesAsync`, `discardStream`, and `discardAll`.

#### Scenario: StateBasedSession satisfies ContinuumSession interface
- **WHEN** a `StateBasedSession` instance is assigned to a variable of type `ContinuumSession`
- **THEN** the assignment SHALL compile and all `ContinuumSession` methods SHALL be available

### Requirement: loadAsync delegates to adapter fetchAsync

`StateBasedSession.loadAsync<TAggregate>(streamId)` SHALL check the identity map first. On cache miss, it SHALL resolve the `AggregatePersistenceAdapter` for `TAggregate` and call `adapter.fetchAsync(streamId)`. The returned aggregate SHALL be tracked in the identity map.

#### Scenario: First load fetches from adapter
- **WHEN** `loadAsync<User>(streamId)` is called for a stream not yet tracked
- **THEN** the session SHALL call `UserApiAdapter.fetchAsync(streamId)` and return the hydrated `User` aggregate

#### Scenario: Subsequent load returns cached aggregate
- **WHEN** `loadAsync<User>(streamId)` is called for a stream already loaded in this session
- **THEN** the session SHALL return the cached aggregate from the identity map without calling `fetchAsync` again

#### Scenario: Load with no registered adapter throws
- **WHEN** `loadAsync<Playlist>(streamId)` is called but no adapter is registered for `Playlist`
- **THEN** the session SHALL throw `InvalidOperationException`

#### Scenario: Adapter fetchAsync throws StreamNotFoundException
- **WHEN** `loadAsync<User>(streamId)` is called and the adapter's `fetchAsync` throws `StreamNotFoundException`
- **THEN** the session SHALL rethrow the `StreamNotFoundException` to the caller

### Requirement: applyAsync uses shared 3-path detection logic

`StateBasedSession.applyAsync` SHALL use the same 3-path detection as `SessionImpl`: (1) already tracked → apply directly, (2) creation event → create via factory, (3) mutation event → load then apply. The logic SHALL be shared via `SessionBase`, not duplicated.

#### Scenario: Apply to already-tracked stream
- **WHEN** `applyAsync<User>(streamId, EmailChanged(...))` is called for a stream already loaded in this session
- **THEN** the event SHALL be appended to pending events and (in eager mode) applied to the in-memory aggregate without calling the adapter

#### Scenario: Apply creation event creates new aggregate
- **WHEN** `applyAsync<User>(streamId, UserRegistered(...))` is called and `UserRegistered` is a registered creation event
- **THEN** the session SHALL create the aggregate via the `AggregateFactoryRegistry`, track it as a new stream, and return the new aggregate

#### Scenario: Apply mutation event to untracked stream loads first
- **WHEN** `applyAsync<User>(streamId, EmailChanged(...))` is called for a stream not yet tracked and `EmailChanged` is not a creation event
- **THEN** the session SHALL first call `adapter.fetchAsync(streamId)` to load the aggregate, then apply the event

#### Scenario: Creation event on already-tracked stream throws
- **WHEN** `applyAsync<User>(streamId, UserRegistered(...))` is called but the stream is already tracked in this session
- **THEN** the session SHALL throw `InvalidOperationException`

### Requirement: Eager and deferred application modes

`StateBasedSession` SHALL support both `EventApplicationMode.eager` and `EventApplicationMode.deferred`, with identical semantics to `SessionImpl`.

#### Scenario: Eager mode applies event immediately
- **WHEN** the session is configured with `EventApplicationMode.eager` and `applyAsync` is called with `EmailChanged(newEmail: 'new@example.com')`
- **THEN** the aggregate's email SHALL be updated immediately and the returned aggregate SHALL reflect the new email

#### Scenario: Deferred mode records event without applying
- **WHEN** the session is configured with `EventApplicationMode.deferred` and `applyAsync` is called with `EmailChanged(newEmail: 'new@example.com')`
- **THEN** the aggregate's email SHALL remain unchanged until `saveChangesAsync` is called

#### Scenario: Deferred mode applies events during save
- **WHEN** the session is in deferred mode and `saveChangesAsync` is called with pending events
- **THEN** all pending events SHALL be applied to the in-memory aggregate before calling `adapter.persistAsync`, so the adapter receives the post-event state

### Requirement: saveChangesAsync delegates to adapter persistAsync per stream

`StateBasedSession.saveChangesAsync` SHALL iterate all streams with pending events and call `adapter.persistAsync(streamId, aggregate, pendingEvents)` for each. On success, it SHALL return the list of all committed events and clear pending events.

#### Scenario: Save with one stream
- **WHEN** `saveChangesAsync()` is called with one stream having pending events `[EmailChanged, NameChanged]`
- **THEN** the session SHALL call `adapter.persistAsync(streamId, aggregate, [EmailChanged, NameChanged])` once and return `[EmailChanged, NameChanged]`

#### Scenario: Save with multiple streams
- **WHEN** `saveChangesAsync()` is called with two streams (User and Playlist) each having pending events
- **THEN** the session SHALL call `persistAsync` once per stream and return the combined list of committed events from all streams

#### Scenario: Save with no pending events
- **WHEN** `saveChangesAsync()` is called with no streams having pending events
- **THEN** the session SHALL return an empty list without calling any adapter

#### Scenario: Pending events cleared after successful save
- **WHEN** `saveChangesAsync()` succeeds
- **THEN** all streams' pending events SHALL be cleared and a subsequent `saveChangesAsync()` call SHALL return an empty list

### Requirement: Concurrency retry via adapter-thrown ConcurrencyException

When `adapter.persistAsync` throws `ConcurrencyException`, the session SHALL re-fetch the aggregate via `adapter.fetchAsync`, re-apply all pending events on the fresh state, and retry persistence — up to `maxRetries` attempts.

#### Scenario: Successful retry after concurrency conflict
- **WHEN** `adapter.persistAsync` throws `ConcurrencyException` on the first attempt and succeeds on the second
- **THEN** the session SHALL re-fetch the aggregate, re-apply pending events, call `persistAsync` again, and return the committed events

#### Scenario: Exhausted retries rethrows ConcurrencyException
- **WHEN** `adapter.persistAsync` throws `ConcurrencyException` on every attempt up to `maxRetries`
- **THEN** the session SHALL rethrow the `ConcurrencyException` to the caller

#### Scenario: maxRetries parameter controls retry count
- **WHEN** `saveChangesAsync(maxRetries: 3)` is called and `persistAsync` throws `ConcurrencyException` on the first two attempts
- **THEN** the session SHALL retry up to 3 times total (1 initial + 2 retries), succeeding on the third attempt

### Requirement: Partial save failure throws PartialSaveException

When `saveChangesAsync` persists multiple streams and some succeed while others fail, the session SHALL throw `PartialSaveException` containing the lists of saved and failed stream IDs.

#### Scenario: First stream succeeds, second fails
- **WHEN** `saveChangesAsync()` is called with two streams, and the first stream's `persistAsync` succeeds but the second throws an exception
- **THEN** the session SHALL throw `PartialSaveException` with the first stream in `savedStreams` and the second in `failedStreams`

#### Scenario: Saved streams have pending events cleared
- **WHEN** a `PartialSaveException` is thrown
- **THEN** the successfully saved streams SHALL have their pending events cleared, while failed streams SHALL retain their pending events

### Requirement: No cross-aggregate atomicity

`StateBasedSession` SHALL NOT guarantee atomicity across multiple streams. Each stream is persisted independently via its adapter.

#### Scenario: Independent stream persistence
- **WHEN** `saveChangesAsync()` is called with pending events for both `User` and `Playlist`
- **THEN** each stream SHALL be persisted via a separate `adapter.persistAsync` call, and success or failure of one SHALL NOT affect the other

### Requirement: Adapter receives both aggregate state and pending events

When `adapter.persistAsync` is called, it SHALL receive the stream ID, the aggregate in its post-event state, and the full list of pending domain events for that stream.

#### Scenario: Adapter receives creation event for new aggregate
- **WHEN** `saveChangesAsync()` is called after a creation event `UserRegistered(...)` was applied
- **THEN** `adapter.persistAsync` SHALL receive the fully constructed `User` aggregate and `[UserRegistered(...)]` as pending events

#### Scenario: Adapter receives mutation events for existing aggregate
- **WHEN** `saveChangesAsync()` is called after `EmailChanged(...)` and `NameChanged(...)` were applied to an existing aggregate
- **THEN** `adapter.persistAsync` SHALL receive the mutated `User` aggregate and `[EmailChanged(...), NameChanged(...)]` as pending events

### Requirement: discardStream and discardAll clear pending events

`discardStream` and `discardAll` SHALL clear pending events without reverting aggregate state, identical to `SessionImpl` behavior.

#### Scenario: discardStream clears one stream
- **WHEN** `discardStream(streamId)` is called
- **THEN** pending events for that stream SHALL be cleared and `saveChangesAsync()` SHALL NOT persist anything for that stream

#### Scenario: discardAll clears all streams
- **WHEN** `discardAll()` is called
- **THEN** pending events for all tracked streams SHALL be cleared

### Requirement: SessionBase extracts shared session logic

A `SessionBase` abstract class SHALL contain the persistence-agnostic session logic shared between `SessionImpl` and `StateBasedSession`. `SessionImpl` SHALL extend `SessionBase` after the refactor, with no changes to its public behavior.

#### Scenario: SessionImpl behavior unchanged after extraction
- **WHEN** `SessionImpl` is refactored to extend `SessionBase`
- **THEN** all existing `SessionImpl` tests SHALL pass without modification

#### Scenario: StateBasedSession extends SessionBase
- **WHEN** `StateBasedSession` is created
- **THEN** it SHALL extend `SessionBase` and implement only `loadAsync`, `saveChangesAsync`, and the reload-for-retry logic
