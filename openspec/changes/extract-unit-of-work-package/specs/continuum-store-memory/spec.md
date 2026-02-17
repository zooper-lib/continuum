## MODIFIED Requirements

### Requirement: In-memory EventStore implementation
The system SHALL provide an in-memory `EventStore` implementation suitable for tests. The package SHALL depend on `continuum_es` (instead of `continuum`) for `EventStore`, `StoredEvent`, `ExpectedVersion`, and related types.

#### Scenario: Append and load round-trip
- **GIVEN** an empty in-memory store
- **WHEN** events are appended to a stream with `ExpectedVersion.noStream`
- **THEN** subsequent `loadStream` returns stored events ordered by per-stream version

#### Scenario: Package depends on continuum_es
- **WHEN** inspecting `continuum_store_memory` pubspec.yaml
- **THEN** it SHALL list `continuum_es` as a dependency (not `continuum` directly, though `continuum_es` transitively brings in `continuum`)

### Requirement: Concurrency behavior matches EventStore contract
The in-memory store SHALL throw a concurrency error when `expectedVersion` does not match the stream's current version.

#### Scenario: Append with wrong expected version
- **GIVEN** a stream with current version `v`
- **WHEN** `appendEvents` is called with `expectedVersion != v`
- **THEN** a `ConcurrencyException` is thrown

### Requirement: No gaps in versions
The in-memory store SHALL assign strictly sequential versions for appended events.

#### Scenario: Two appends
- **GIVEN** a new stream
- **WHEN** one event is appended, then another event is appended
- **THEN** the stored versions are `0` then `1`
