## ADDED Requirements
### Requirement: Projection definition
The system SHALL provide a projection definition API that maps domain events to read model mutations.

#### Scenario: Projection handler applies an event
- **WHEN** a projection receives a supported event type
- **THEN** it mutates the read model state deterministically

### Requirement: Projection state persistence
The system SHALL persist projection state and checkpoints through a projection store abstraction.

#### Scenario: Projection checkpoint advances after successful save
- **WHEN** a projection processes an event and saves its state
- **THEN** the checkpoint advances to the processed event’s global sequence

### Requirement: Projection runner
The system SHALL provide a runner that replays stored events in global order and applies them to projections.

#### Scenario: Projection runner rebuilds from start
- **WHEN** a projection has no checkpoint
- **THEN** the runner processes events from the beginning in global order

### Requirement: Failure semantics
The system SHALL not advance projection checkpoints when event handling fails.

#### Scenario: Handler failure does not advance checkpoint
- **WHEN** a projection handler throws an exception
- **THEN** the checkpoint remains at the previous value and the event may be retried
