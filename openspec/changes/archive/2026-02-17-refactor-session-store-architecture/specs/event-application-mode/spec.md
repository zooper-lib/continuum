## ADDED Requirements

### Requirement: EventApplicationMode enum with eager and deferred variants

The system SHALL provide an `EventApplicationMode` enum with two values: `eager` and `deferred`. This mode controls when domain events mutate the in-memory aggregate during a session.

#### Scenario: Enum has exactly two values
- **WHEN** inspecting `EventApplicationMode`
- **THEN** it SHALL have exactly `eager` and `deferred` variants

### Requirement: Eager mode applies events immediately

When `EventApplicationMode.eager` is configured, `applyAsync` SHALL apply the event's `apply*` handler to the in-memory aggregate immediately. The returned aggregate SHALL reflect the post-event state.

#### Scenario: Aggregate reflects event immediately in eager mode
- **WHEN** a store is configured with `EventApplicationMode.eager` and `applyAsync<User>(id, EmailChanged(newEmail: 'new@example.com'))` is called
- **THEN** the returned `User` aggregate SHALL have `email` equal to `'new@example.com'`

#### Scenario: Multiple eager events accumulate state
- **WHEN** `applyAsync` is called twice in eager mode with `EmailChanged` then `NameChanged`
- **THEN** the returned aggregate after each call SHALL reflect all events applied up to that point

### Requirement: Deferred mode records events without applying

When `EventApplicationMode.deferred` is configured, `applyAsync` SHALL record the event in the pending events list but SHALL NOT apply the event's `apply*` handler to the in-memory aggregate. The returned aggregate SHALL reflect the pre-event state.

#### Scenario: Aggregate does not reflect event in deferred mode
- **WHEN** a store is configured with `EventApplicationMode.deferred` and `applyAsync<User>(id, EmailChanged(newEmail: 'new@example.com'))` is called on a user with email `'old@example.com'`
- **THEN** the returned `User` aggregate SHALL still have `email` equal to `'old@example.com'`

#### Scenario: Deferred events are applied during saveChangesAsync
- **WHEN** events are applied in deferred mode and then `saveChangesAsync` is called
- **THEN** `saveChangesAsync` SHALL apply all pending events to the aggregate before serialization and persistence

### Requirement: Application mode is a store-level configuration

The `EventApplicationMode` SHALL be configured on the store (e.g., `EventSourcingStore`) and propagated to all sessions created by that store. It SHALL NOT be configurable per-event or per-session.

#### Scenario: Store propagates mode to sessions
- **WHEN** `EventSourcingStore` is created with `applicationMode: EventApplicationMode.deferred`
- **THEN** every session created via `openSession()` SHALL use deferred event application

### Requirement: Eager mode is the default

If no `EventApplicationMode` is explicitly provided, the store SHALL default to `EventApplicationMode.eager`.

#### Scenario: Default application mode
- **WHEN** `EventSourcingStore` is created without specifying `applicationMode`
- **THEN** sessions SHALL use eager event application

### Requirement: Both modes produce identical persisted results

Regardless of the configured `EventApplicationMode`, `saveChangesAsync` SHALL persist the same events with the same data. The only difference between modes is when the in-memory aggregate reflects the change.

#### Scenario: Same events persisted in both modes
- **WHEN** the same sequence of `applyAsync` calls is made under eager and deferred modes
- **THEN** `saveChangesAsync` SHALL persist identical events in both cases
