# Capability: continuum-core

## ADDED Requirements

### Requirement: Annotations for discovery
The system SHALL provide `@Aggregate()` and `@Event()` annotations for code generation discovery.

#### Scenario: Annotating an aggregate
- **GIVEN** a plain Dart class marked with `@Aggregate()`
- **WHEN** the generator scans the library
- **THEN** the class is treated as an aggregate candidate

#### Scenario: Annotating an event
- **GIVEN** a class marked with `@Event(ofAggregate: SomeAggregate)`
- **WHEN** the generator scans the library
- **THEN** the class is treated as a domain event belonging to `SomeAggregate`

### Requirement: Event type discriminator is optional in core
The system SHALL allow `@Event(type: ...)` to be omitted when using the core layer without persistence.

#### Scenario: Event defined without type
- **GIVEN** an event annotated with `@Event(ofAggregate: A)` and no `type`
- **WHEN** the user only uses event-driven mutation (no persistence)
- **THEN** the event remains valid for compilation and generated apply dispatch

### Requirement: Strong identity types
The system SHALL provide strong types `EventId` and `StreamId` as lightweight wrappers around string values.

#### Scenario: Constructing identifiers
- **WHEN** the user constructs `EventId('...')` and `StreamId('...')`
- **THEN** the values are strongly typed and not interchangeable

### Requirement: Domain event base contract
The system SHALL provide a `DomainEvent` base contract with:
- `eventId: EventId`
- `occurredOn: DateTime`
- `metadata: Map<String, dynamic>`

#### Scenario: Defining an event
- **GIVEN** an event class implementing `DomainEvent`
- **WHEN** it is constructed without explicit `occurredOn`
- **THEN** user code can supply `DateTime.now().toUtc()` as the default in the event constructor

### Requirement: Exceptions used by generated code
The system SHALL provide typed exceptions that generated code and persistence components can throw for invalid usage.

#### Scenario: Unsupported mutation event application
- **GIVEN** an aggregate apply dispatcher receives an event type it does not support
- **WHEN** `applyEvent()` is invoked
- **THEN** an `UnsupportedEventException` (or equivalent typed error) is thrown
