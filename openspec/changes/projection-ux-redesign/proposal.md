## Why

Inline projection execution currently receives only `List<Operation>`, which lacks stream identity. This forces single-stream projection authors to manually extract keys from every operation — duplicating identity that the session/persistence layer already knows. The wiring to bridge projections into the unit-of-work system also requires a hand-written adapter class, making "hello projections" far more ceremonial than it should be.

## What Changes

- **BREAKING**: Replace `CommitHandler.onCommitAsync(List<Operation>)` with `CommitHandler.onCommitAsync(CommitBatch)`, where `CommitBatch` carries `CommittedOperation` entries that pair each `Operation` with its `StreamId` and optional persistence metadata.
- **BREAKING**: Change `Session.saveChangesAsync()` return type from `Future<List<Operation>>` to `Future<CommitBatch>`, so `TransactionalRunner` can propagate the batch directly to commit handlers.
- **BREAKING**: Change `InlineProjectionExecutor.executeAsync` to accept `CommitBatch` (or its entries) instead of `List<Operation>`.
- **BREAKING**: Remove `extractKey` from `SingleStreamProjection`. The executor derives the key (`StreamId`) from the commit batch. `MultiStreamProjection` retains user-defined `extractKey`.
- Add a framework-provided `ProjectionCommitHandler` that implements `CommitHandler` and delegates to `InlineProjectionExecutor`, eliminating the need for a hand-written adapter.
- Add a framework-provided `AsyncProjectionCommitHandler` that implements `CommitHandler` and schedules async projection processing from commit batches.
- Extend the code generator to emit projection registration glue — a generated helper that registers all discovered projections with a `ProjectionRegistry` in a single call, reducing manual wiring.

## Capabilities

### New Capabilities

- `commit-batch`: Introduce `CommitBatch` and `CommittedOperation` types that carry stream identity and optional persistence metadata alongside operations, providing post-commit systems with the context they need without fattening domain events.
- `projection-commit-handlers`: Ship first-class `ProjectionCommitHandler` (inline) and `AsyncProjectionCommitHandler` (async) that implement `CommitHandler` and bridge commit batches to projection executors, removing the need for hand-written adapters.
- `projection-registration-glue`: Extend the code generator to emit a registration helper that wires all discovered projections into a `ProjectionRegistry` with a single call, collapsing manual per-projection registration boilerplate.

### Modified Capabilities

_(No existing specs to modify — `openspec/specs/` is empty.)_

## Impact

- **Packages affected**: `continuum` (L0), `continuum_uow` (L1), `continuum_event_sourcing` (L2), `continuum_generator`.
- **Breaking API surface**:
  - `CommitHandler` interface (L1) — signature change.
  - `CompositeCommitHandler` (L1) — follows `CommitHandler` change.
  - `Session` / `SessionBase` (L1) — `saveChangesAsync` return type change.
  - `TransactionalRunner` (L1) — propagates `CommitBatch` instead of `List<Operation>`.
  - `SingleStreamProjection` (L0) — `extractKey` removed.
  - `InlineProjectionExecutor` (L0) — accepts `CommitBatch` entries.
- **Layer constraint**: `CommitBatch` must live in `continuum` (L0) so both L0 projection executors and L1 commit handlers can reference it. `ProjectionCommitHandler` bridges L0 executor with L1 `CommitHandler` and may live in L1 or a dedicated wiring package.
- **Generator changes**: New code emission for registration glue; existing projection dispatch mixin generation is unaffected.
- **Downstream consumers**: All existing `CommitHandler` implementations, `Session.saveChangesAsync` call sites, and `SingleStreamProjection` subclasses must be updated.
