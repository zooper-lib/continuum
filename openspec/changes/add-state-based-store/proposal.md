## Why

Continuum's persistence architecture is designed around swappable stores — workflow code stays identical regardless of how aggregates are persisted. Phase 1 (core refactoring) and Phase 2 (TransactionalRunner + CommitHandler) are complete, and the `ContinuumStore` interface, `ContinuumSession`, and `AggregatePersistenceAdapter<T>` interface are all in place. What's missing is the concrete `StateBasedStore` implementation that lets users point their aggregates at a backend API instead of a local event store. This is Phase 3: the reason the swappable architecture exists.

## What Changes

- Add `StateBasedStore` — a `ContinuumStore` implementation that uses `AggregatePersistenceAdapter<T>` instances (one per aggregate type) for fetch and persist, instead of an `EventStore`.
- Add `StateBasedSession` — a `ContinuumSession` implementation whose `loadAsync` delegates to the adapter's `fetchAsync`, and whose `saveChangesAsync` delegates to the adapter's `persistAsync` per stream. Shares the same `applyAsync` logic (creation detection, event application via registries) as `SessionImpl`.
- Add adapter exception types (`TransientAdapterException`, `PermanentAdapterException`) for backend-specific failures the session cannot retry. `ConcurrencyException` and `StreamNotFoundException` already exist and are reused.
- Add `PartialSaveException` for multi-stream saves where some streams succeed and others fail (no cross-aggregate atomicity in state-based mode).
- Extract shared `applyAsync` / event-tracking logic from `SessionImpl` so both session implementations reuse it without duplication.

## Capabilities

### New Capabilities

- `state-based-store`: The `StateBasedStore` class, its construction API (adapter map + event applier registries), and its `openSession()` contract.
- `state-based-session`: The `StateBasedSession` class — `loadAsync` via adapter fetch, `saveChangesAsync` via adapter persist, shared `applyAsync` logic, concurrency retry via adapter-thrown `ConcurrencyException`, and partial-save error reporting.
- `adapter-exceptions`: Backend-specific exception types (`TransientAdapterException`, `PermanentAdapterException`, `PartialSaveException`) and the session's handling contract for each.

### Modified Capabilities

_(none — the `AggregatePersistenceAdapter` interface is already defined and will not change; `ContinuumStore`, `ContinuumSession`, and existing exceptions remain unchanged)_

## Impact

- **`packages/continuum/lib/src/`**: New files for `StateBasedStore`, `StateBasedSession`, and adapter exception types. Possible extraction of shared session logic into a base class or mixin.
- **`packages/continuum/lib/continuum.dart`**: New public exports for `StateBasedStore` and the new exception types.
- **`packages/continuum/test/`**: New test suites for state-based store, state-based session (load, save, concurrency retry, partial failure, creation detection), and adapter exception handling.
- **Code generation (`packages/continuum_generator/`)**: No changes — `EventApplierRegistry` and `AggregateFactoryRegistry` are already generated and shared by both session types.
- **Store packages (`continuum_store_*`)**: No changes — these are `EventStore` implementations, not `ContinuumStore` implementations.
- **No breaking changes to existing public API.** This is purely additive.
