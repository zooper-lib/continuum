# Capability: continuum-persistence

## MODIFIED Requirements

### Requirement: EventSourcingStore configuration
The system SHALL allow `EventSourcingStore` to accept optional projection configuration during construction.

#### Scenario: Store with projection registry
- **GIVEN** an EventSourcingStore constructor call
- **WHEN** a `ProjectionRegistry` is provided
- **THEN** sessions from this store execute registered inline projections on save

#### Scenario: Store without projection registry
- **GIVEN** an EventSourcingStore constructor call
- **WHEN** no `ProjectionRegistry` is provided
- **THEN** the store operates as before with no projection processing

### Requirement: Session saveChangesAsync with projections
The system SHALL execute inline projections as part of `Session.saveChangesAsync()` when projections are configured.

#### Scenario: saveChangesAsync triggers inline projections
- **GIVEN** a session from a store with inline projections configured
- **WHEN** `saveChangesAsync()` is called with pending events
- **THEN** events are persisted
- **AND** all matching inline projections are executed before the method returns

#### Scenario: Inline projection failure rolls back
- **GIVEN** an inline projection that fails during execution
- **WHEN** `saveChangesAsync()` is called
- **THEN** no events are persisted
- **AND** no read models are updated
- **AND** an exception is thrown

#### Scenario: saveChangesAsync without projections unchanged
- **GIVEN** a session from a store without projection configuration
- **WHEN** `saveChangesAsync()` is called
- **THEN** only event persistence occurs (no projection overhead)
