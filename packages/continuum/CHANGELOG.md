## UNRELEASED

### Breaking Changes

- **BREAKING**: Renamed `@Event` annotation to `@AggregateEvent` to avoid naming conflicts with user code.
- **BREAKING**: Renamed `ofAggregate:` parameter to `of:` in `@AggregateEvent` annotation.
- **BREAKING**: Renamed `DomainEvent` class to `ContinuumEvent` to avoid naming conflicts.
- **BREAKING**: Renamed `Session` interface to `ContinuumSession` to avoid naming conflicts.
- **BREAKING**: Renamed `StoredEvent.fromDomainEvent()` to `StoredEvent.fromContinuumEvent()`.
- **BREAKING**: Updated all parameter names from `domainEvent` to `continuumEvent`.

## 1.0.0

- Initial release with event sourcing core functionality.
- Added `@Aggregate()` and `@Event()` annotations for code generation.
- Added strong types: `EventId`, `StreamId`.
- Added `DomainEvent` base contract.
- Added persistence interfaces: `Session`, `EventStore`, `EventSerializer`.
- Added `EventSourcingStore` root object for wiring dependencies.
- Added exception types for error handling.
