# Capability: continuum-projections

## ADDED Requirements

### Requirement: Projection abstraction
The system SHALL provide a `Projection` abstraction that defines how events mutate a read model.

#### Scenario: Projection declares handled event types
- **GIVEN** a projection implementation
- **WHEN** the projection is queried for handled event types
- **THEN** it returns the set of event types it reacts to

#### Scenario: Projection applies event to read model
- **GIVEN** a projection and an event it handles
- **WHEN** the event is applied
- **THEN** the projection returns an updated read model

### Requirement: Single-stream projection
The system SHALL provide a `SingleStreamProjection` abstraction for building read models from one event stream.

#### Scenario: Single-stream projection extracts stream identity
- **GIVEN** a single-stream projection and a stored event
- **WHEN** the projection extracts the ID
- **THEN** it returns the stream identity for read model lookup

#### Scenario: Single-stream projection creates initial read model
- **GIVEN** a single-stream projection and a stream ID with no existing read model
- **WHEN** the first event is processed
- **THEN** the projection creates an initial read model for that stream

#### Scenario: Single-stream projection applies events in stream order
- **GIVEN** a stream with events at versions 0, 1, 2
- **WHEN** the projection processes the stream
- **THEN** events are applied in version order (0, 1, 2)

### Requirement: Multi-stream projection
The system SHALL provide a `MultiStreamProjection` abstraction for building read models from events across multiple streams.

#### Scenario: Multi-stream projection extracts grouping key
- **GIVEN** a multi-stream projection and a stored event
- **WHEN** the projection extracts the key
- **THEN** it returns the grouping key for read model lookup

#### Scenario: Multi-stream projection aggregates across streams
- **GIVEN** events from streams A and B that map to the same key K
- **WHEN** the projection processes these events
- **THEN** both events are applied to the same read model for key K

#### Scenario: Multi-stream projection uses global ordering
- **GIVEN** events with global sequences 10, 20, 30 from different streams
- **WHEN** the projection processes these events
- **THEN** events are applied in global sequence order (10, 20, 30)

### Requirement: Projection registry
The system SHALL provide a `ProjectionRegistry` that tracks all registered projections and their configuration.

#### Scenario: Register inline projection
- **GIVEN** a projection registry
- **WHEN** a projection is registered as inline
- **THEN** it is stored with inline lifecycle configuration

#### Scenario: Register async projection
- **GIVEN** a projection registry
- **WHEN** a projection is registered as async
- **THEN** it is stored with async lifecycle configuration

#### Scenario: Query projections for event type
- **GIVEN** a registry with projections A (handles E1, E2) and B (handles E2, E3)
- **WHEN** queried for projections handling event type E2
- **THEN** both A and B are returned

### Requirement: Inline projection execution
The system SHALL execute inline projections synchronously during event persistence.

#### Scenario: Inline projection updates on saveChangesAsync
- **GIVEN** an inline projection P registered for event type E
- **AND** a session with pending event E
- **WHEN** `saveChangesAsync()` is called
- **THEN** projection P is applied to event E before the method returns

#### Scenario: Inline projection failure aborts event append
- **GIVEN** an inline projection that throws an exception
- **WHEN** `saveChangesAsync()` is called
- **THEN** no events are persisted
- **AND** the exception propagates to the caller

#### Scenario: Inline projection guarantees strong consistency
- **GIVEN** an inline projection P for event type E
- **WHEN** `saveChangesAsync()` completes successfully
- **THEN** the read model is immediately consistent with the persisted events

### Requirement: Async projection execution
The system SHALL execute async projections via a background processor after event persistence.

#### Scenario: Async projection does not block saveChangesAsync
- **GIVEN** an async projection P registered for event type E
- **AND** a session with pending event E
- **WHEN** `saveChangesAsync()` is called
- **THEN** the method returns immediately after events are persisted
- **AND** projection P is scheduled for background processing

#### Scenario: Async projection failure does not affect event append
- **GIVEN** an async projection that throws an exception
- **WHEN** `saveChangesAsync()` is called
- **THEN** events are persisted successfully
- **AND** the projection failure is logged for retry

#### Scenario: Async projection eventual consistency
- **GIVEN** an async projection P for event type E
- **WHEN** `saveChangesAsync()` completes
- **THEN** the read model may not yet be updated
- **AND** the read model will eventually be updated by the background processor

### Requirement: Read model storage
The system SHALL provide a `ReadModelStore` abstraction for persisting read models.

#### Scenario: Load existing read model
- **GIVEN** a read model store with a stored model for key K
- **WHEN** `loadAsync(K)` is called
- **THEN** the stored read model is returned

#### Scenario: Load missing read model
- **GIVEN** a read model store with no model for key K
- **WHEN** `loadAsync(K)` is called
- **THEN** null is returned

#### Scenario: Save read model
- **GIVEN** a read model store and a read model M for key K
- **WHEN** `saveAsync(K, M)` is called
- **THEN** subsequent `loadAsync(K)` returns M

#### Scenario: Delete read model
- **GIVEN** a read model store with a model for key K
- **WHEN** `deleteAsync(K)` is called
- **THEN** subsequent `loadAsync(K)` returns null

### Requirement: Projection position tracking
The system SHALL track the last processed event position for each async projection.

#### Scenario: Load projection position
- **GIVEN** a position store with position 42 for projection P
- **WHEN** `loadPositionAsync("P")` is called
- **THEN** 42 is returned

#### Scenario: Save projection position
- **GIVEN** a position store
- **WHEN** `savePositionAsync("P", 100)` is called
- **THEN** subsequent `loadPositionAsync("P")` returns 100

#### Scenario: Position starts at null for new projection
- **GIVEN** a position store with no entry for projection P
- **WHEN** `loadPositionAsync("P")` is called
- **THEN** null is returned (indicating process from beginning)

### Requirement: Background projection processor
The system SHALL provide a `ProjectionProcessor` for running async projections.

#### Scenario: Processor starts and runs continuously
- **GIVEN** a projection processor with registered async projections
- **WHEN** `startAsync()` is called
- **THEN** the processor begins polling for new events

#### Scenario: Processor stops gracefully
- **GIVEN** a running projection processor
- **WHEN** `stopAsync()` is called
- **THEN** the processor completes current work and stops

#### Scenario: Processor resumes from last position
- **GIVEN** projection P with last position 50
- **WHEN** the processor restarts
- **THEN** it processes events starting from global sequence 51

#### Scenario: Processor updates position after successful processing
- **GIVEN** projection P processing event with global sequence 100
- **WHEN** the event is successfully applied
- **THEN** P's position is updated to 100

### Requirement: Automatic projection updates
The system SHALL automatically update all applicable projections when events are appended.

#### Scenario: Zero runtime user interaction
- **GIVEN** projections registered during startup
- **WHEN** events are appended via any session
- **THEN** all applicable projections are updated automatically
- **AND** no user code invokes projections manually

#### Scenario: New events trigger all matching projections
- **GIVEN** projections A (inline, handles E1) and B (async, handles E1, E2)
- **WHEN** event E1 is appended
- **THEN** projection A is applied immediately
- **AND** projection B is scheduled for async processing

### Requirement: Projection idempotency support
The system SHALL support idempotent projection processing to handle reprocessing safely.

#### Scenario: Reprocessing same event is safe
- **GIVEN** a projection that has already processed event E at position P
- **WHEN** the same event E is reprocessed (e.g., after crash recovery)
- **THEN** the read model remains correct (no duplicate effects)

### Requirement: EventSourcingStore projection integration
The system SHALL integrate projections into `EventSourcingStore` configuration.

#### Scenario: Configure store with projections
- **GIVEN** an EventSourcingStore factory call with projection registry
- **WHEN** the store is created
- **THEN** sessions from this store automatically execute inline projections

#### Scenario: Store without projections works unchanged
- **GIVEN** an EventSourcingStore factory call without projection registry
- **WHEN** sessions append events
- **THEN** no projection processing occurs (backward compatible)
