## Why

The session lifecycle layer (identity map, operation recording, atomic commit, concurrency retry, transactional runner) currently lives inside the `continuum` package alongside the core mutation primitives. This couples the Unit of Work engine to a single package and prevents users from extending it with custom persistence strategies without depending on all of Continuum's event-sourcing internals. Extracting it into a dedicated package creates a clean extension point: users who need a persistence strategy not covered by the provided event-sourcing or state-based stores can extend `SessionBase` directly, getting the full session engine for free while implementing only four persistence-specific methods.

## What Changes

- **BREAKING**: New `continuum_uow` package at `packages/continuum_uow/` containing the session lifecycle engine: `Session`, `SessionBase`, `TrackedEntity`, `SessionStore`, `TransactionalRunner`, `CommitHandler`, and all session-related exception types
- **BREAKING**: New `continuum_es` package at `packages/continuum_es/` containing all event-sourcing-specific types: `EventSourcingStore`, `SessionImpl`, `EventStore`, `AtomicEventStore`, serialization, projections
- **BREAKING**: New `continuum_state` package at `packages/continuum_state/` containing state-based persistence types: `StateBasedStore`, `StateBasedSession`, `AggregatePersistenceAdapter`, adapter exceptions
- **BREAKING**: Session lifecycle types removed from `continuum` package — consumers must add `continuum_uow` (or a Layer 2 package that transitively depends on it) to their `pubspec.yaml`
- **BREAKING**: Event-sourcing types removed from `continuum` package — consumers must add `continuum_es` to their `pubspec.yaml`
- **BREAKING**: State-based types removed from `continuum` package — consumers must add `continuum_state` to their `pubspec.yaml`
- **BREAKING**: Store implementation packages (`continuum_store_memory`, `continuum_store_hive`, `continuum_store_sembast`) depend on `continuum_es` instead of `continuum`
- Rename `ContinuumSession` → `Session`, `ContinuumStore` → `SessionStore`, `StreamState` → `TrackedEntity` in the UoW package (backward-compat typedefs provided in UoW)
- `continuum` package shrinks to Layer 0: operations, events, annotations, registries, codegen primitives, `StreamId`, `GeneratedAggregate`, `EventApplicationMode`
- Internal method renames in `SessionBase`: `applyEventByRuntimeType` → `applyOperationByRuntimeType`, `applyDeferredEvents` → `applyDeferredOperations`
- Session layer works with `Operation` (not `ContinuumEvent`) as the mutation type, proving ES-agnosticism

## Capabilities

### New Capabilities

- `continuum-uow`: Unit of Work session engine — `Session`, `SessionBase`, `TrackedEntity`, `SessionStore`, `TransactionalRunner`, `CommitHandler`, session-related exceptions, and the extension point for custom persistence strategies
- `continuum-es`: Event-sourcing persistence layer — `EventSourcingStore`, `SessionImpl`, `EventStore`, `AtomicEventStore`, event serialization, projections, `StoredEvent`, `ExpectedVersion`
- `continuum-state`: State-based persistence layer — `StateBasedStore`, `StateBasedSession`, `AggregatePersistenceAdapter`, adapter exceptions

### Modified Capabilities

- `continuum-core`: `Operation` marker interface must be explicitly defined as the lowest-common-denominator mutation type; `ContinuumEvent implements Operation` relationship formalized
- `continuum-store`: `ContinuumStore` interface replaced by `SessionStore` in UoW; `ContinuumStore` becomes a backward-compat typedef; `TransactionalRunner` moves to UoW
- `continuum-persistence`: `EventSourcingStore` and `SessionImpl` move to `continuum_es`; projection integration moves with them
- `continuum-store-memory`: Dependency changes from `continuum` to `continuum_es`
- `continuum-store-hive`: Dependency changes from `continuum` to `continuum_es`
- `state-based-store`: `StateBasedStore` and `StateBasedSession` move to `continuum_state`; dependency on `continuum_uow` for `SessionBase`
- `state-based-session`: Session implementation moves to `continuum_state` package
- `adapter-exceptions`: `PermanentAdapterException` and `TransientAdapterException` move to `continuum_state`
- `commit-handler`: `CommitHandler` interface moves to `continuum_uow`
- `transactional-runner`: `TransactionalRunner` moves to `continuum_uow`
- `continuum-generator`: Generated code may need updated imports if references point to moved types; projection codegen must emit `continuum_es` imports
- `continuum-projections`: All projection types move to `continuum_es`

## Impact

- **Package structure**: Three new packages added to the workspace (`continuum_uow`, `continuum_es`, `continuum_state`); dependency graph becomes a clean four-layer architecture with no cycles
- **Consumer migration**: All existing consumers must update their `pubspec.yaml` to add the appropriate Layer 1/2 packages; import paths change for all moved types
- **Code generation**: `continuum_generator` must be verified/updated to emit correct imports for types that moved to `continuum_es` (projections, serialization)
- **Store implementations**: `continuum_store_memory`, `continuum_store_hive`, `continuum_store_sembast` all change their dependency from `continuum` to `continuum_es`
- **Test migration**: Tests for moved types relocate to their respective packages; only import path changes expected, no API usage changes
- **Breaking change scope**: Major version bump required for `continuum`; new packages start at `^1.0.0`
