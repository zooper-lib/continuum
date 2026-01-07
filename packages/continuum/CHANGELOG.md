## 1.0.0

- Initial release with event sourcing core functionality.
- Added `@Aggregate()` and `@Event()` annotations for code generation.
- Added strong types: `EventId`, `StreamId`.
- Added `DomainEvent` base contract.
- Added persistence interfaces: `Session`, `EventStore`, `EventSerializer`.
- Added `EventSourcingStore` root object for wiring dependencies.
- Added exception types for error handling.
