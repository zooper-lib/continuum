## ADDED Requirements
### Requirement: Global ordered event reads
The event store SHALL provide a global ordered read of stored events for projection processing.

#### Scenario: Load events after a checkpoint
- **WHEN** a caller provides a global sequence checkpoint
- **THEN** the store returns events with global sequence greater than the checkpoint in ascending order

### Requirement: Global sequence availability
The event store SHALL return a global sequence value on stored events when using global ordered reads.

#### Scenario: Returned events include global sequence
- **WHEN** a caller requests globally ordered events
- **THEN** each returned stored event includes a non-null global sequence
