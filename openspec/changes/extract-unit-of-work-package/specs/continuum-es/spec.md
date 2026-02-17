## ADDED Requirements

### Requirement: EventSourcingStore implements SessionStore

The system SHALL provide an `EventSourcingStore` final class that implements `SessionStore` (from `continuum_uow`). Its `openSession()` method SHALL return a `Session` instance backed by event store persistence.

#### Scenario: EventSourcingStore is assignable to SessionStore
- **WHEN** an `EventSourcingStore` instance is assigned to a variable of type `SessionStore`
- **THEN** the assignment SHALL compile and `openSession()` SHALL return a valid `Session`

#### Scenario: EventSourcingStore construction
- **WHEN** `EventSourcingStore` is constructed
- **THEN** it SHALL accept `eventStore`, `aggregates`, and optional `applicationMode` and projection configuration parameters

### Requirement: SessionImpl extends SessionBase

The system SHALL provide a `SessionImpl` class that extends `SessionBase` (from `continuum_uow`) and implements event-sourcing-specific persistence: loading from event streams, appending events, serialization, and projection execution.

#### Scenario: SessionImpl extends SessionBase
- **WHEN** inspecting `SessionImpl`
- **THEN** it SHALL extend `SessionBase` and implement `loadAsync`, `loadAllAsync`, `saveChangesAsync`, and `handleMutationOnUntrackedEntity`

#### Scenario: saveChangesAsync returns committed events
- **WHEN** `saveChangesAsync()` is called on `SessionImpl`
- **THEN** it SHALL return `Future<List<ContinuumEvent>>` (covariant return type narrowing `Future<void>` from the base)

#### Scenario: saveChangesAsync validates pending operations are ContinuumEvent
- **WHEN** `saveChangesAsync()` is called and a pending operation is a plain `Operation` (not `ContinuumEvent`)
- **THEN** `SessionImpl` SHALL throw `InvalidOperationException` with a descriptive message

#### Scenario: Concurrency retry reloads and re-applies
- **WHEN** `saveChangesAsync` encounters a `ConcurrencyException` and `maxRetries > 0`
- **THEN** the session SHALL reload conflicting streams from the event store, reconstruct aggregates, re-apply pending events, and retry

### Requirement: EventStore interface

The system SHALL provide an `EventStore` abstract interface for stream-based event persistence.

#### Scenario: EventStore interface shape
- **WHEN** inspecting the `EventStore` interface
- **THEN** it SHALL provide methods for loading streams, appending events, and querying stream metadata

### Requirement: AtomicEventStore interface

The system SHALL provide an `AtomicEventStore` abstract interface that extends `EventStore` and adds multi-stream atomic append support.

#### Scenario: AtomicEventStore extends EventStore
- **WHEN** inspecting `AtomicEventStore`
- **THEN** it SHALL extend `EventStore` and add `appendEventsAtomicAsync` for multi-stream atomic operations

### Requirement: StoredEvent value type

The system SHALL provide a `StoredEvent` class representing a persisted event with stream identity, version, global sequence, timestamp, type discriminator, and serialized payload.

#### Scenario: StoredEvent construction
- **WHEN** a `StoredEvent` is created
- **THEN** it SHALL contain streamId, version, globalSequence, timestamp, eventType, and data fields

### Requirement: ExpectedVersion concurrency control

The system SHALL provide an `ExpectedVersion` type for optimistic concurrency control on event stream appends.

#### Scenario: ExpectedVersion.noStream for new streams
- **WHEN** `ExpectedVersion.noStream` is used
- **THEN** the append SHALL succeed only if the stream does not yet exist

#### Scenario: ExpectedVersion with specific version
- **WHEN** `ExpectedVersion(version)` is used
- **THEN** the append SHALL succeed only if the stream's current version matches

### Requirement: Event serialization

The system SHALL provide `EventSerializer`, `EventSerializerRegistry`, and `JsonEventSerializer` for converting domain events to/from persistence format.

#### Scenario: Serialize and deserialize round-trip
- **WHEN** a `ContinuumEvent` is serialized via `EventSerializer` and then deserialized
- **THEN** the resulting event SHALL be equal to the original

#### Scenario: Registry resolves serializer by event type
- **WHEN** the `EventSerializerRegistry` is queried for an event type
- **THEN** it SHALL return the registered `EventSerializer` for that type

### Requirement: ProjectionEventStore for projection queries

The system SHALL provide a `ProjectionEventStore` interface extending `EventStore` with methods for global-ordered event queries needed by async projections.

#### Scenario: Load events by global sequence
- **WHEN** `loadEventsFromSequenceAsync(fromSequence)` is called
- **THEN** it SHALL return events ordered by global sequence starting from the given position

### Requirement: Projection system

The system SHALL provide the full projection system: `Projection`, `SingleStreamProjection`, `MultiStreamProjection`, `ProjectionRegistry`, `InlineProjectionExecutor`, `AsyncProjectionExecutor`, `ProjectionProcessor`, `ReadModelStore`, `ProjectionPositionStore`, `GeneratedProjection`, and related types.

#### Scenario: Inline projections execute during save
- **WHEN** `saveChangesAsync()` is called with inline projections configured
- **THEN** projections SHALL be executed before the method returns

#### Scenario: Async projections are scheduled after save
- **WHEN** events are committed with async projections configured
- **THEN** projections SHALL be scheduled for background processing

### Requirement: Barrel file exports all ES types

The `continuum_es` package SHALL export all public types from `lib/continuum_es.dart`.

#### Scenario: Barrel file completeness
- **WHEN** a consumer imports `package:continuum_es/continuum_es.dart`
- **THEN** `EventSourcingStore`, `SessionImpl`, `EventStore`, `AtomicEventStore`, `StoredEvent`, `ExpectedVersion`, `EventSerializer`, `EventSerializerRegistry`, `JsonEventSerializer`, `ProjectionEventStore`, and all projection types SHALL be available

### Requirement: Package depends on continuum and continuum_uow

The `continuum_es` package SHALL depend on `continuum` (Layer 0) and `continuum_uow` (Layer 1).

#### Scenario: Dependency chain
- **WHEN** inspecting `continuum_es` pubspec.yaml
- **THEN** it SHALL list `continuum` and `continuum_uow` as dependencies
