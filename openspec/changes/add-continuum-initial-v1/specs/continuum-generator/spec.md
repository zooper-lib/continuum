# Capability: continuum-generator

## ADDED Requirements

### Requirement: Discover aggregates and events
The system SHALL discover aggregates and events by scanning `@Aggregate()` and `@Event(ofAggregate: ...)` annotations.

#### Scenario: Build mappings for an aggregate
- **GIVEN** an aggregate `A` and multiple events annotated as belonging to `A`
- **WHEN** the generator runs
- **THEN** it builds a mapping of creation events and mutation events for `A`

### Requirement: Generate handler contracts for mutation events only
The system SHALL generate a `_$<Aggregate>EventHandlers` mixin requiring `apply<EventName>(...)` methods for non-creation (mutation) events only.

#### Scenario: Missing apply method fails compilation
- **GIVEN** an aggregate mixes in `_$AEventHandlers`
- **WHEN** the aggregate omits an `apply<MutationEvent>` method required by the mixin
- **THEN** the project fails to compile

### Requirement: Generate apply dispatcher
The system SHALL generate an `applyEvent(DomainEvent)` dispatcher for each aggregate that routes supported mutation events to the corresponding `apply...` method.

#### Scenario: Applying a supported event
- **GIVEN** a mutation event `E` for aggregate `A`
- **WHEN** `a.applyEvent(E())` is invoked
- **THEN** the generated dispatcher calls `a.applyE(...)`

#### Scenario: Applying an unsupported event
- **GIVEN** an event not belonging to aggregate `A`
- **WHEN** `a.applyEvent(event)` is invoked
- **THEN** the dispatcher throws `UnsupportedEventException`

### Requirement: Generate replay helper
The system SHALL generate a `replayEvents(Iterable<DomainEvent>)` helper for each aggregate that applies events in order via `applyEvent`.

#### Scenario: Replaying multiple events
- **GIVEN** a list of mutation events in desired order
- **WHEN** `replayEvents` is called
- **THEN** each event is applied sequentially

### Requirement: Generate creation dispatcher
The system SHALL generate a creation dispatcher that constructs an aggregate instance from a creation event by calling the matching static `create*` method.

#### Scenario: Creating from a valid creation event
- **GIVEN** a valid creation event for aggregate `A`
- **WHEN** `createFromEvent(creationEvent)` is invoked
- **THEN** it returns `A.create*(creationEvent)`

#### Scenario: Creating from an invalid creation event
- **GIVEN** an event that is not a valid creation event for `A`
- **WHEN** `createFromEvent(event)` is invoked
- **THEN** it throws `InvalidCreationEventException`

### Requirement: Generate event registry for persistence
The system SHALL generate an `EventRegistry` mapping stable event type strings to `fromJson` factories for persistence deserialization.

#### Scenario: Deserializing a known event type
- **GIVEN** stored event type `t` present in the registry and JSON payload `data`
- **WHEN** `EventRegistry.fromStored(t, data)` is invoked
- **THEN** it returns a `DomainEvent` instance using the mapped factory

#### Scenario: Unknown event type
- **GIVEN** a stored event type `t` missing from the registry
- **WHEN** deserialization is attempted
- **THEN** it throws `UnknownEventTypeException`
