# Capability: continuum-core

## MODIFIED Requirements

### Requirement: Annotations for discovery
The system SHALL provide `@Aggregate()` and `@AggregateEvent()` annotations for code generation discovery.

`@AggregateEvent` SHALL support an explicit `creation` boolean flag that indicates whether an event is a creation event (the first event in a stream).

#### Scenario: Annotating an aggregate
- **GIVEN** a plain Dart class marked with `@Aggregate()`
- **WHEN** the generator scans the library
- **THEN** the class is treated as an aggregate candidate

#### Scenario: Annotating a mutation event
- **GIVEN** a class marked with `@AggregateEvent(of: SomeAggregate)` and `creation` omitted or `false`
- **WHEN** the generator scans the library
- **THEN** the class is treated as a mutation event belonging to `SomeAggregate`

#### Scenario: Annotating a creation event
- **GIVEN** a class marked with `@AggregateEvent(of: SomeAggregate, creation: true)`
- **WHEN** the generator scans the library
- **THEN** the class is treated as a creation event belonging to `SomeAggregate`

### Requirement: Event type discriminator is optional in core
The system SHALL allow `@AggregateEvent(type: ...)` to be omitted when using the core layer without persistence.

#### Scenario: Event defined without type
- **GIVEN** an event annotated with `@AggregateEvent(of: A)` and no `type`
- **WHEN** the user only uses event-driven mutation (no persistence)
- **THEN** the event remains valid for compilation and generated apply dispatch
