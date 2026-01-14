# Capability: continuum-lints

## ADDED Requirements

### Requirement: Warn when creation factories are missing
The system SHALL provide a lint that warns when an `@Aggregate()` class is missing one or more required static `createFrom<EventName>` factory methods for its creation events.

#### Scenario: Aggregate missing a required creation factory
- **GIVEN** an aggregate `A` annotated with `@Aggregate()`
- **AND** an event `E` annotated with `@AggregateEvent(of: A, creation: true)`
- **AND** `A` does not declare `static A createFromE(E event)`
- **WHEN** lints are run
- **THEN** the lint reports a warning on `A` indicating the missing `createFromE` method

#### Scenario: Aggregate has all required creation factories
- **GIVEN** an aggregate `A` and creation events `E1..En` for `A`
- **AND** `A` declares `static A createFromE1(E1 event)` .. `static A createFromEn(En event)`
- **WHEN** lints are run
- **THEN** no warnings are reported
