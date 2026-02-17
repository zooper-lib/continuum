# Capability: continuum-generator

## MODIFIED Requirements

### Requirement: Discover aggregates and events
The system SHALL discover aggregates and events by scanning `@Aggregate()` and `@AggregateEvent(of: ...)` annotations.

The system SHALL classify an event as a creation event if and only if the event annotation has `creation: true`.

#### Scenario: Building mappings for an aggregate
- **GIVEN** an aggregate `A` and multiple events annotated as belonging to `A`
- **WHEN** the generator runs
- **THEN** it builds a mapping of creation events and mutation events for `A` based on each event’s `creation` flag

### Requirement: Generate handler contracts for mutation events only
The system SHALL generate a `_$<Aggregate>EventHandlers` mixin requiring `apply<EventName>(...)` methods for mutation events only.

#### Scenario: A creation event does not require an apply handler
- **GIVEN** an event `E` annotated with `@AggregateEvent(of: A, creation: true)`
- **WHEN** the generator emits handler contracts for `A`
- **THEN** no `applyE` contract is generated

### Requirement: Generate creation dispatcher
The system SHALL generate a creation dispatcher that constructs an aggregate instance from a creation event by calling the matching static `createFrom<EventName>` method.

#### Scenario: Creating from a valid creation event
- **GIVEN** a creation event `E` for aggregate `A`
- **AND** `A` defines `static A createFromE(E event)`
- **WHEN** `createFromEvent(E())` is invoked
- **THEN** it returns `A.createFromE(event)`

#### Scenario: Missing factory for a creation event
- **GIVEN** a creation event `E` for aggregate `A`
- **AND** `A` does not define `static A createFromE(E event)`
- **WHEN** the generator runs
- **THEN** code generation fails with a clear error describing the missing factory

#### Scenario: Creating from a non-creation event
- **GIVEN** an event that is not a creation event for `A`
- **WHEN** `createFromEvent(event)` is invoked
- **THEN** it throws `InvalidCreationEventException`
