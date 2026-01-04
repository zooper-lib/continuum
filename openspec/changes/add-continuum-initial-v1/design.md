## Context
Continuum is a domain event modeling and event sourcing framework for Dart with three usage modes:
1) event-driven mutation (no persistence),
2) frontend-only event sourcing, and
3) hybrid optimistic mode.

The core constraint is that Dart runtime reflection is unsuitable, so code generation must provide type-safe wiring for aggregates and events.

## Goals
- Keep the core (`continuum`) dependency-light and usable without persistence.
- Ensure aggregates remain plain Dart classes (no base class, no version field, no pending event list).
- Provide a persistence layer that tracks stream versions inside the `Session`, not inside aggregates.
- Make persistence optional via separate packages for concrete stores.
- Provide a reference in-memory EventStore to enable fast tests.

## Non-Goals
- Solving “commands” or a CQRS pipeline.
- Designing a distributed event replication system.
- Designing projections or snapshotting.

## Key Decisions
- **Two-layer API in one core package**: `continuum` contains both core concepts and persistence interfaces, matching `doc/draft/specs.md`. Concrete stores live in separate packages.
- **Stable event type discriminator**: `@Event(type: ...)` is optional in core-only usage, but required for persistence/serialization scenarios.
- **Creation events are not applied**: creation events construct aggregates via static `create*` methods; generated code never emits `apply<CreationEvent>`.
- **Session is the unit of work**: pending events are stored in the Session, and `saveChanges()` persists atomically with expected-version concurrency.

## Generator Integration Strategy
- The generator produces `*.g.dart` part files in consumer projects.
- v1 focuses on:
  - event discovery via `@Aggregate()` / `@Event(ofAggregate: ...)`,
  - generating handler mixins for non-creation events,
  - generating `applyEvent()` / `replayEvents()` dispatchers,
  - generating `createFromEvent()` factory dispatcher,
  - generating an `EventRegistry` for deserialization.

Generator behavior should be validated via an integration-style fixture package (a small test package under the mono-repo or `packages/continuum_generator/test/fixtures`) to ensure generated code compiles and runs.

## Risks / Trade-offs
- Generator complexity vs ergonomics: keep v1 minimal and explicit; avoid attempting schema upcasting or advanced features.
- API stability: choose names and exception types that generated code and store implementations can rely on.

## Migration / Rollback
- This is a greenfield initialization; rollback is removing newly added packages/specs.

## Open Questions
- Should `continuum_store_hive` ship in v1 (same change) or be split into a follow-up change after core/persistence/memory store are stable?
- Do we want a dedicated `continuum_generator` integration test package in-repo, or use golden-file tests only?
