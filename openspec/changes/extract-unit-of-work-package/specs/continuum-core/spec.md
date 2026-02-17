## ADDED Requirements

### Requirement: Operation marker interface

The system SHALL provide an `Operation` abstract interface class as the lowest-common-denominator mutation type. An operation describes what happened and carries only domain data — no identity, no timestamp, no metadata.

#### Scenario: Operation is a marker interface
- **WHEN** inspecting the `Operation` type
- **THEN** it SHALL be an `abstract interface class` with no methods or fields

#### Scenario: ContinuumEvent implements Operation
- **WHEN** inspecting the `ContinuumEvent` type
- **THEN** it SHALL implement `Operation` (in addition to `BoundedDomainEvent<EventId>`)

#### Scenario: Plain Operation implementations are valid
- **WHEN** a user creates a class that implements `Operation` without implementing `ContinuumEvent`
- **THEN** it SHALL compile and be usable with `SessionBase.applyAsync` in the UoW layer
