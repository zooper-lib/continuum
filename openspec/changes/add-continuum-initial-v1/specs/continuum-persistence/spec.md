# Capability: continuum-persistence

## ADDED Requirements

### Requirement: Session interface
The system SHALL provide a `Session` abstraction that supports:
- `load<TAggregate>(StreamId)`
- `startStream<TAggregate>(StreamId, DomainEvent creationEvent)`
- `append(StreamId, DomainEvent event)`
- `saveChanges()`
- `discardStream(StreamId)`
- `discardAll()`

#### Scenario: Start a new stream
- **GIVEN** a creation event valid for aggregate `A`
- **WHEN** `startStream<A>(id, creationEvent)` is called
- **THEN** the session tracks the stream as having one pending creation event
- **AND** the aggregate instance is constructed via a generated `create*` method

### Requirement: Load reconstructs from stored events
The system SHALL reconstruct aggregates by:
1) loading stored events for the stream, ordered by version,
2) constructing the aggregate from the first event (creation),
3) applying remaining events via generated mutation dispatch.

#### Scenario: Loading a populated stream
- **GIVEN** a stream with a valid creation event and subsequent mutation events
- **WHEN** `load<A>(id)` is called
- **THEN** the returned aggregate reflects the state after replaying the mutation events

### Requirement: Pending events live in Session
The system SHALL store pending (uncommitted) events in the `Session` and SHALL NOT require aggregates to track pending events.

#### Scenario: Append applies immediately to cached aggregate
- **GIVEN** a session with a cached aggregate instance for a stream
- **WHEN** `append(id, mutationEvent)` is called
- **THEN** the event is recorded as pending
- **AND** the event is applied to the cached aggregate via generated `applyEvent`

### Requirement: Optimistic concurrency with expected version
The system SHALL enforce optimistic concurrency by appending events with an `expectedVersion`.

#### Scenario: Concurrency mismatch
- **GIVEN** an `expectedVersion` that does not match the current persisted stream version
- **WHEN** `appendEvents` is invoked on the `EventStore`
- **THEN** a `ConcurrencyException` is thrown

### Requirement: EventStore interface
The system SHALL provide an `EventStore` abstraction with:
- `loadStream(StreamId) -> List<StoredEvent>` ordered by version
- `appendEvents(StreamId, expectedVersion, List<DomainEvent>)`

#### Scenario: Loading a missing stream
- **GIVEN** a stream that does not exist
- **WHEN** `loadStream(id)` is called
- **THEN** it returns an empty list

### Requirement: StoredEvent model
The system SHALL define `StoredEvent` including:
- `eventId`, `streamId`, per-stream `version`
- stable `eventType` discriminator
- serialized `data` payload
- `occurredOn`, `metadata`
- optional `globalSequence`

#### Scenario: Sequential versions
- **GIVEN** a stream with events
- **WHEN** events are appended successfully
- **THEN** the resulting stored versions are strictly sequential starting at 0 with no gaps

### Requirement: Serialization abstraction
The system SHALL provide an `EventSerializer` abstraction and a `SerializedEvent` model for converting events to/from persisted representation.

#### Scenario: Persisted event round-trip
- **GIVEN** a domain event and a serializer implementation
- **WHEN** the event is serialized and deserialized
- **THEN** the resulting event is of the expected concrete type

### Requirement: EventSourcingStore root
The system SHALL provide an `EventSourcingStore` root object that wires `EventStore`, `EventSerializer`, and `EventRegistry`, and can create `Session` instances.

#### Scenario: Opening a session
- **GIVEN** an `EventSourcingStore` configured with dependencies
- **WHEN** `openSession()` is invoked
- **THEN** a new usable session instance is returned
