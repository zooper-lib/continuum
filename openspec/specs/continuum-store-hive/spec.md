# Capability: continuum-store-hive

## ADDED Requirements

### Requirement: Hive-backed EventStore implementation
The system SHALL provide a Hive-backed `EventStore` implementation for local persistence.

#### Scenario: Persisted round-trip
- **GIVEN** a Hive-backed store configured for a directory
- **WHEN** events are appended and the store is re-opened
- **THEN** `loadStream` returns the persisted events ordered by version

### Requirement: Concurrency behavior matches EventStore contract
The Hive store SHALL throw a concurrency error when `expectedVersion` does not match the stream’s current version.

#### Scenario: Append with wrong expected version
- **GIVEN** a stream with current version `v`
- **WHEN** `appendEvents` is called with `expectedVersion != v`
- **THEN** a `ConcurrencyException` is thrown

### Requirement: Sequential versioning
The Hive store SHALL assign strictly sequential per-stream versions starting at 0.

#### Scenario: Append multiple events
- **GIVEN** a new stream
- **WHEN** multiple events are appended in a single call
- **THEN** stored versions are sequential and gapless
