## Context

The Continuum monorepo currently bundles all persistence abstractions — session lifecycle (identity map, `applyAsync`, `saveChangesAsync`), event sourcing (event store, serialization, projections), and state-based persistence (adapter pattern) — into a single `continuum` package. This means any consumer who wants the session engine must also pull in ES serialization types, projection types, and adapter exception types they may never use.

The current type hierarchy uses `ContinuumEvent` throughout the session layer, even though the identity map, 3-path detection, and commit logic don't intrinsically require ES-specific metadata (event ID, timestamp). This tight coupling prevents the session layer from being extended for non-ES persistence strategies without depending on ES internals.

The workspace currently consists of six packages: `continuum` (core + persistence), `continuum_generator` (codegen), `continuum_store_memory`, `continuum_store_hive`, `continuum_store_sembast` (ES backends), and `continuum_lints`. All store implementations depend directly on `continuum`.

### Constraints

- `continuum_generator` depends on `continuum` for annotations and type references — it must continue to compile after the split
- Generated code emits `AggregateFactoryRegistry` and `EventApplierRegistry` entries — these must remain in the core package
- `Operation` cannot live in the UoW package because `ContinuumEvent implements Operation` would create a cycle (core depending on UoW)
- The workspace uses Dart SDK `^3.10.4` and `resolution: workspace`

## Goals / Non-Goals

**Goals:**

- Extract the session lifecycle engine into `continuum_uow` so it can be extended independently of any persistence strategy
- Extract event-sourcing types into `continuum_es` and state-based types into `continuum_state`
- Establish a clean four-layer dependency graph: core → UoW → ES/State → store implementations
- Widen the session layer to work with `Operation` (not `ContinuumEvent`) as the mutation type
- Provide backward-compatibility typedefs for renamed types (`ContinuumSession` → `Session`, `ContinuumStore` → `SessionStore`)
- Ensure all existing tests continue to pass with only import path changes

**Non-Goals:**

- Making `continuum_uow` standalone (independent of `continuum`) — the dependency on core is intentional
- Changing the public API semantics — this is a structural refactor, not a behavior change
- Deprecation period with re-exports from `continuum` — this is a clean break (major version bump)
- Changing `saveChangesAsync` return type from `Future<List<ContinuumEvent>>` to `Future<void>` on `Session` — the ES-specific return type stays on the ES session; the base `Session` interface uses `Future<void>`
- Adding new features to the UoW engine — extraction only

## Decisions

### Decision 1: `Operation` stays in `continuum` core, session layer widens to `Operation`

The `SessionBase` identity map and `applyAsync` logic currently use `ContinuumEvent` everywhere. This is unnecessarily narrow — the session engine only needs "something that mutates an aggregate," which is `Operation`.

**Choice:** Keep `Operation` in `continuum` core. Change `SessionBase`, `TrackedEntity`, and `Session.applyAsync` to use `Operation` instead of `ContinuumEvent`. ES sessions narrow back to `ContinuumEvent` at their persistence boundary (serialization, event store append).

**Why not move `Operation` to UoW:** `ContinuumEvent implements Operation` — if `Operation` were in UoW, `continuum` would need to depend on UoW for this implements clause, creating a dependency cycle.

**Why not keep `ContinuumEvent` in the session layer:** State-based and custom strategies don't generate event IDs or timestamps. Forcing them to implement `ContinuumEvent` adds pointless ceremony. `Operation` is the right abstraction level for the session engine.

### Decision 2: `Session.saveChangesAsync` returns `Future<void>`, ES session returns events

The current `ContinuumSession.saveChangesAsync` returns `Future<List<ContinuumEvent>>`. This is ES-specific — state-based saves don't produce event lists.

**Choice:** The base `Session` interface defines `Future<void> saveChangesAsync({int maxRetries})`. The ES `SessionImpl` keeps its `Future<List<ContinuumEvent>>` return type by overriding with a covariant return (or providing a separate method). Callers who need committed events use `SessionImpl` directly or cast.

**Alternative considered:** Generic session `Session<TResult>` — rejected due to complexity cascading through `SessionStore`, `TransactionalRunner`, and all consumer code.

### Decision 3: No re-exports from `continuum` — clean break

After extraction, `continuum`'s barrel file shrinks to Layer 0 types only. It does NOT re-export UoW, ES, or state types.

**Choice:** Clean break with major version bump. Consumers update their `pubspec.yaml` to add the appropriate Layer 1/2 packages.

**Why not re-exports:** `continuum` (Layer 0) must not depend on UoW (Layer 1). Re-exports would require a dependency, violating the layering. A `package:continuum/compat.dart` sub-library that somehow re-exports without a dependency is not possible in Dart.

**Why not deprecation period:** The types physically move packages. There's no mechanism to keep them in both places without either duplicating code or adding a circular dependency. A clean break is simpler and honest.

### Decision 4: Backward-compat typedefs live in `continuum_uow`

Renamed types get typedefs in the UoW package for migration ease:

- `typedef ContinuumSession = Session;`
- `typedef ContinuumStore = SessionStore;`
- `typedef UnsupportedEventException = UnsupportedOperationException;`

These help consumers migrate incrementally — old names still compile when importing from `continuum_uow`.

### Decision 5: `SessionBase.handleMutationOnUntrackedStream` renamed to `handleMutationOnUntrackedEntity`

The current name uses "stream" terminology, which is ES-specific. Since the UoW is persistence-agnostic, "entity" is the correct term.

Similarly: `StreamState` → `TrackedEntity`, `streams` map → `trackedEntities` map, `applyEventByRuntimeType` → `applyOperationByRuntimeType`, `applyDeferredEvents` → `applyDeferredOperations`, `pendingEvents` → `pendingOperations`.

### Decision 6: Five-phase implementation order

1. **Phase 1 — Create `continuum_uow`**: New package with moved types, tests, clean `dart analyze`
2. **Phase 2 — Create `continuum_es`**: Move ES types, projections, tests
3. **Phase 3 — Create `continuum_state`**: Move state-based types, tests
4. **Phase 4 — Update store implementations**: Change dependencies from `continuum` to `continuum_es`
5. **Phase 5 — Clean up `continuum` core**: Remove moved files, update barrel, verify generator

Each phase ends with a passing `dart analyze` and test suite. This allows incremental validation.

### Decision 7: Generator stays as-is, imports verified

`continuum_generator` depends on `continuum` for annotations and type metadata. Generated code references `AggregateFactoryRegistry`, `EventApplierRegistry`, `EventApplicationMode` — all of which stay in `continuum` core. No generator changes are expected.

However, if generated projection code references types that moved to `continuum_es` (e.g., `GeneratedProjection`, projection registration types), the generator must be updated to emit `package:continuum_es/...` imports. This needs verification during Phase 2.

### Decision 8: `ConcurrencyException` keeps integer version fields

The current `ConcurrencyException` has `expectedVersion` and `actualVersion` integer fields. These work for both ES (stream version) and state-based (version counter) strategies. Custom strategies using different concurrency tokens (ETags, timestamps) can subclass or use the `message` field.

**Alternative considered:** Making version fields optional or generic — rejected because integers cover the common case and the `message` field provides an escape hatch.

## Risks / Trade-offs

**[Breaking change scope]** → Every consumer must update `pubspec.yaml` and import paths. Mitigated by: clear migration guide, backward-compat typedefs in UoW, and the fact that import path changes are mechanical (find-and-replace).

**[Generator import drift]** → If generated projection code references types that moved to `continuum_es`, builds break until the generator is updated. Mitigated by: verifying generated output in Phase 2, fixing before proceeding.

**[`saveChangesAsync` return type divergence]** → Base `Session` returns `Future<void>` while ES `SessionImpl` returns `Future<List<ContinuumEvent>>`. Callers using `Session` (the interface) lose access to committed events. Mitigated by: callers who need events already work with `SessionImpl` directly or via `TransactionalRunner` + `CommitHandler`.

**[Increased package count]** → Workspace grows from 6 to 9 packages (adding `continuum_uow`, `continuum_es`, `continuum_state`). Mitigated by: clean dependency graph with no cycles, each package has a clear single responsibility.

**[Test migration effort]** → Tests for moved types relocate to new packages. Risk of missing tests or broken test imports. Mitigated by: tests should need only import path changes (no API changes), and `dart analyze` + `dart test` run after each phase.

**[`Operation` widening in `SessionBase`]** → Changing `ContinuumEvent` → `Operation` in the identity map means ES sessions must validate that pending operations are `ContinuumEvent` instances before serializing. If a user accidentally mixes plain `Operation` instances with an ES session, the error surfaces at save time rather than at `applyAsync` time. Mitigated by: clear `InvalidOperationException` with a descriptive message when non-event operations are found during ES save.
