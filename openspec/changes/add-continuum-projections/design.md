## Context
Continuum’s persistence layer already includes `StoredEvent.globalSequence` as a hook for future projections. There is no built-in way to consume events in global order and update read models automatically.

## Goals / Non-Goals
- Goals:
  - Provide a first-class projection API for read models.
  - Ensure projections mutate and save automatically with ordered event processing.
  - Keep projections outside aggregates and avoid domain pollution.
  - Allow rebuilds from the event store with deterministic results.
- Non-Goals:
  - Real-time pub/sub or external message bus integration.
  - Snapshotting for projections.
  - Automatic projection inference from aggregate state.

## Decisions
- Decision: Projections are processed from the EventStore using a global sequence cursor.
  - Rationale: Global ordering enables deterministic, cross-stream projections without session coupling.
- Decision: Projection state and checkpoint persistence are handled by a `ProjectionStore` abstraction.
  - Rationale: Keeps storage concerns isolated and allows different backends.
- Decision: Projection processing is at-least-once; handlers must be idempotent.
  - Rationale: Simplifies failure handling and is compatible with most storage backends.

## Alternatives considered
- In-process session hooks for synchronous projection updates.
  - Rejected: couples projections to write-path sessions and blocks save latency.
- Per-stream projections without global ordering.
  - Rejected: cannot support read models that aggregate across streams.

## Risks / Trade-offs
- Breaking `EventStore` interface to support global ordered reads.
- Projection correctness depends on idempotent handlers.

## Migration Plan
- Update all `EventStore` implementations to return global sequence values when supported.
- Provide a default in-memory projection store for tests and examples.
- Document the new projection runner and its required event store capabilities.

## Open Questions
- Should projection processing allow configurable batch sizes and backoff strategies?
- Should projection runners be embedded in the same process or encouraged as separate workers?
