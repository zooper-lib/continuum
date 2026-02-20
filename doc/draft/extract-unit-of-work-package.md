# Extract Unit of Work Package

## Goal

Extract the session lifecycle layer from the Continuum monorepo into its own package. This package provides the **Unit of Work engine**: identity map, operation recording via `applyAsync`, atomic commit, concurrency retry, and a zone-scoped transactional runner.

The UoW package **depends on Continuum**. It is not a standalone library. Continuum is the event-driven mutation framework (operations, events, registries, code generation). The UoW package consumes those primitives and adds the session lifecycle on top. This coupling is intentional — it enforces a consistent architecture regardless of which persistence strategy the user picks.

The value of the split is the **extension point**: if none of the provided persistence strategies (event sourcing, state-based) fit a user's backend, they extend `SessionBase` from the UoW package and implement their own — same `applyAsync`, same `TransactionalRunner`, same `CommitHandler`, same programming model.

## Architecture Overview

Four layers, clean dependency graph, no cycles:

```
Layer 0 ─ continuum (core)
           Operations, Events, Registries, Codegen, Annotations
              │
Layer 1 ─ continuum_uow (this package)
           Session, SessionBase, TransactionalRunner, CommitHandler
           Depends on: continuum
              │
       ┌──────┴──────┐
Layer 2a              Layer 2b
continuum_es          continuum_state
EventSourcingStore    StateBasedStore
SessionImpl           StateBasedSession
EventStore            AggregatePersistenceAdapter
Serialization         Depends on: continuum, continuum_uow
Projections
Depends on: continuum, continuum_uow
       │                    │
Layer 3 ─ Store implementations
  continuum_store_memory    (ES backend)
  continuum_store_hive      (ES backend)
  continuum_store_sembast   (ES backend)
  (future state backends)
```

### What lives where

| Layer | Package | Contains |
|---|---|---|
| 0 | `continuum` | `Operation`, `ContinuumEvent`, `@OperationTarget`, `@OperationFor`, `@Projection`, `AggregateFactoryRegistry`, `EventApplierRegistry`, `EventApplicationMode`, `StreamId`, `GeneratedAggregate`, codegen annotations, all operation/event base contracts |
| 1 | `continuum_uow` | `Session`, `SessionBase`, `TrackedEntity`, `SessionStore`, `TransactionalRunner`, `CommitHandler`, `ConcurrencyException`, `InvalidOperationException`, `UnsupportedOperationException`, `PartialSaveException` |
| 2a | `continuum_es` | `EventSourcingStore`, `SessionImpl`, `EventStore`, `AtomicEventStore`, `EventSerializer`, `EventSerializerRegistry`, `JsonEventSerializer`, `StoredEvent`, `ExpectedVersion`, `StreamAppendBatch`, `ProjectionEventStore`, all projection types |
| 2b | `continuum_state` | `StateBasedStore`, `StateBasedSession`, `AggregatePersistenceAdapter`, `PermanentAdapterException`, `TransientAdapterException` |
| 3 | `continuum_store_*` | Concrete ES backends (memory, hive, sembast) |

### Why `continuum` stays at Layer 0

Registries, events, and codegen outputs belong to the core because:

1. **Codegen produces them.** `continuum_generator` emits `AggregateFactoryRegistry` and `EventApplierRegistry` entries. These must exist in the package the generator depends on.
2. **Every layer needs them.** UoW's `SessionBase` uses the registries. ES and state sessions use events. Splitting registries out would create a diamond dependency.
3. **`Operation` must live here.** `ContinuumEvent implements Operation` — if `Operation` were in UoW, Continuum would need to depend on UoW for this implements clause, creating a cycle. `Operation` is the lightweight base; `ContinuumEvent` enriches it with identity and temporal metadata for ES.

### Why UoW depends on Continuum (not standalone)

The UoW cannot function without `applyAsync`, and `applyAsync` works with `Operation`, `AggregateFactoryRegistry`, and `EventApplierRegistry` — all Continuum core types. Making UoW standalone would mean either:
- Duplicating all of these as generic types (then Continuum wraps them — pointless indirection), or
- Making UoW so thin it provides no value.

The dependency on Continuum is a **feature**: it guarantees every persistence strategy speaks the same operation/event language, uses the same registries, and benefits from the same code generation.

---

## Package Identity

- **Name**: TBD (working name: `continuum_uow` — confirm before implementation)
- **Location**: `packages/<name>/`
- **SDK constraint**: `^3.10.4` (same as workspace)
- **Runtime dependencies**: `continuum`, `meta`
- **Dev dependencies**: `lints`, `test`, `mockito`
- **Must be added** to the workspace `pubspec.yaml` under `workspace:`

---

## Core Design Principle

**Operations are tracked on the session, NOT on the entity.**

Entities are plain Dart classes. No base class. No `Tracked` interface. No `pendingOperations` list. The session's identity map holds the entity, its type, its loaded version, and its **pending operations**. On `saveChangesAsync`, the persistence layer receives the entity + its operation list and decides how to persist (append events to an event store, call REST endpoints, upsert to a DB, etc.).

---

## Public API Surface

Each type lives in its own file under `lib/src/`. All are exported from the barrel file.

### Operation / Event Type Hierarchy

`Operation` is a lightweight marker interface in Continuum core. `ContinuumEvent` extends it for ES.

```dart
// In continuum package — lib/src/operations/operation.dart

/// Marker interface for any mutation recorded within a session.
///
/// An operation describes what happened. It carries only domain data —
/// no identity, no timestamp, no metadata. Those are concerns of
/// [ContinuumEvent], which extends this for event sourcing.
abstract interface class Operation {}
```

```dart
// In continuum package — lib/src/events/continuum_event.dart

/// An operation enriched with identity and temporal metadata.
///
/// Required for event sourcing (serialization, replay, projections).
/// State-based and custom strategies can use plain [Operation]
/// implementations instead.
abstract interface class ContinuumEvent
    implements Operation, BoundedDomainEvent<EventId> {}
```

The UoW session layer works with `Operation` — the lowest common denominator. ES sessions narrow to `ContinuumEvent` at the persistence boundary (serialization, event store append). State-based and custom strategies work with plain `Operation` implementations — no `EventId` generation, no timestamp, no metadata map.

### Types moved FROM Continuum to UoW

These types currently exist in `packages/continuum/lib/src/persistence/`. They move to the UoW package using `Operation` as the mutation type (imported from Continuum via the `continuum` dependency). Registries (`AggregateFactoryRegistry`, `EventApplierRegistry`) already use `Object` internally — no changes needed.

---

### `ContinuumSession` → `Session` (`lib/src/session.dart`)

The core UoW interface. This is the current `ContinuumSession` interface, renamed to `Session` to reflect its role as the generic session contract.

```dart
import 'package:continuum/continuum.dart';

/// Unit of work abstraction for aggregate operations.
///
/// A session tracks loaded aggregates and pending operations, applying
/// changes optimistically and persisting them atomically on save.
abstract interface class Session {
  /// Loads an aggregate by its stream ID.
  Future<TAggregate> loadAsync<TAggregate>(StreamId streamId);

  /// Loads all aggregates of the given type.
  Future<List<TAggregate>> loadAllAsync<TAggregate>();

  /// Records an operation against a stream and applies it through
  /// the registered applier.
  ///
  /// Three detection paths:
  /// 1. Already tracked — stream is in the identity map, apply directly.
  /// 2. Creation operation — a registered factory exists. Creates the
  ///    aggregate and begins tracking.
  /// 3. Mutation operation — no factory found. Loads from the persistence
  ///    backend, then applies.
  ///
  /// The operation can be a plain [Operation] or a [ContinuumEvent].
  /// The persistence strategy decides what it requires at save time.
  Future<TAggregate> applyAsync<TAggregate>(
    StreamId streamId,
    Operation operation,
  );

  /// Persists all pending operations atomically.
  Future<void> saveChangesAsync({int maxRetries = 1});

  /// Discards pending operations for a specific stream.
  void discardStream(StreamId streamId);

  /// Discards all pending operations across all tracked streams.
  void discardAll();
}
```

Continuum re-exports `Session` as `ContinuumSession` via a typedef for backward compatibility:

```dart
// In continuum package
typedef ContinuumSession = Session;
```

---

### `StreamState` → `TrackedEntity` (`lib/src/tracked_entity.dart`)

Identity map entry. Renamed from `StreamState` for clarity outside the ES context.

```dart
import 'package:continuum/continuum.dart';

final class TrackedEntity {
  /// The cached aggregate instance.
  final Object entity;

  /// The runtime type of the aggregate.
  final Type entityType;

  /// The version when the aggregate was loaded (or -1 for new aggregates).
  final int loadedVersion;

  /// Pending operations not yet persisted.
  final List<Operation> pendingOperations;

  // Constructor, withClearedPendingOperations, etc.
  // Same structure as current StreamState, with ContinuumEvent → Operation.
}
```

---

### `SessionBase` (`lib/src/session_base.dart`)

Abstract base class containing persistence-agnostic session logic. This is the **core engine** — moves from Continuum as-is, using the same Continuum types.

Contains:
- The identity map (`Map<StreamId, TrackedEntity>`)
- The 3-path `applyAsync` detection (tracked / creation / mutation)
- Eager/deferred branching via `EventApplicationMode`
- Creation guard (creation operation on tracked entity throws)
- `append()` — records an operation and optionally applies it
- `applyOperationByRuntimeType()` — applies a single operation using the registry
- `applyDeferredOperations()` — flushes deferred operations before save
- `discardStream()` and `discardAll()`

```dart
import 'package:continuum/continuum.dart';
import 'package:meta/meta.dart';

abstract class SessionBase implements Session {
  @protected
  final AggregateFactoryRegistry aggregateFactories;

  @protected
  final EventApplierRegistry eventAppliers;

  final EventApplicationMode applicationMode;

  @protected
  final Map<StreamId, TrackedEntity> trackedEntities = {};

  // ... same logic as current Continuum SessionBase.
  // Uses Operation (not ContinuumEvent) for the mutation type.
  // Uses StreamId, AggregateFactoryRegistry, EventApplierRegistry,
  // EventApplicationMode — all from continuum package.
  // Internal method renames: applyEventByRuntimeType → applyOperationByRuntimeType,
  // applyDeferredEvents → applyDeferredOperations, etc.
}
```

Subclasses implement:
- `loadAsync` — how to fetch an aggregate from the persistence backend
- `loadAllAsync` — how to fetch all aggregates of a type
- `saveChangesAsync` — how to persist pending operations
- `handleMutationOnUntrackedEntity` — Path 3 of `applyAsync`

**This is the extension point.** A user whose backend doesn't fit `EventSourcingStore` or `StateBasedStore` extends `SessionBase` directly and implements these four methods.

---

### `SessionStore` (`lib/src/session_store.dart`)

Session factory. Renamed from `ContinuumStore`.

```dart
/// Abstract interface for opening persistence sessions.
///
/// Provides a single entry point for creating [Session] instances,
/// decoupling workflow code from the concrete persistence strategy.
abstract interface class SessionStore {
  /// Opens a new session for aggregate operations.
  Session openSession();
}
```

Continuum re-exports as `ContinuumStore` via typedef:

```dart
// In continuum package
typedef ContinuumStore = SessionStore;
```

---

### `TransactionalRunner` (`lib/src/transactional_runner.dart`)

Zone-scoped session lifecycle manager. Moves from Continuum as-is, using `SessionStore` / `Session` / `CommitHandler`.

```dart
final class TransactionalRunner {
  final SessionStore _store;
  final CommitHandler? _commitHandler;

  TransactionalRunner({
    required SessionStore store,
    CommitHandler? commitHandler,
  });

  Future<T> runAsync<T>(Future<T> Function() action) async { ... }

  static Session get currentSession { ... }
  static Session? get currentSessionOrNull { ... }
}
```

---

### `CommitHandler` (`lib/src/commit_handler.dart`)

Post-commit side-effect hook.

```dart
abstract interface class CommitHandler {
  Future<void> onCommitAsync();
}
```

---

### Exception Types

These move from Continuum to UoW. Continuum re-exports them.

#### `ConcurrencyException` (`lib/src/concurrency_exception.dart`)

```dart
class ConcurrencyException implements Exception {
  final StreamId streamId;
  final int expectedVersion;
  final int actualVersion;
  final String message;
  const ConcurrencyException({
    required this.streamId,
    required this.expectedVersion,
    required this.actualVersion,
    required this.message,
  });
}
```

Keeps the version fields — they are useful for any strategy that does optimistic concurrency (ES with integer versions, state-based with version counters). Strategies using different concurrency tokens (ETags, timestamps) can ignore these fields and put details in `message`, or subclass.

#### `InvalidOperationException` (`lib/src/invalid_operation_exception.dart`)

```dart
final class InvalidOperationException implements Exception {
  final String message;
  const InvalidOperationException({required this.message});
}
```

#### `UnsupportedOperationException` (`lib/src/unsupported_operation_exception.dart`)

Thrown when no applier or factory is registered for an operation type.

```dart
final class UnsupportedOperationException implements Exception {
  final Type operationType;
  final Type aggregateType;
  const UnsupportedOperationException({
    required this.operationType,
    required this.aggregateType,
  });
}
```

Continuum re-exports as `UnsupportedEventException` via typedef for backward compatibility.

#### `PartialSaveException` (`lib/src/partial_save_exception.dart`)

```dart
final class PartialSaveException implements Exception {
  final List<StreamId> savedStreams;
  final List<StreamId> failedStreams;
  final Object cause;
  const PartialSaveException({
    required this.savedStreams,
    required this.failedStreams,
    required this.cause,
  });
}
```

---

## Barrel File

`lib/continuum_uow.dart`:

```dart
library;

export 'src/commit_handler.dart';
export 'src/concurrency_exception.dart';
export 'src/invalid_operation_exception.dart';
export 'src/partial_save_exception.dart';
export 'src/session.dart';
export 'src/session_base.dart';
export 'src/session_store.dart';
export 'src/tracked_entity.dart';
export 'src/transactional_runner.dart';
export 'src/unsupported_operation_exception.dart';
```

---

## Changes to Continuum Package

After the UoW package exists, Continuum removes the moved types and re-exports them from UoW for backward compatibility.

### Dependency Direction

Continuum (Layer 0) does **not** depend on UoW at the `pubspec.yaml` level. The dependency flows upward:

```
continuum ← continuum_uow ← continuum_es / continuum_state ← continuum_store_*
```

This means Continuum's barrel file does NOT automatically re-export UoW types. Consumers who need session lifecycle add `continuum_uow` (or a Layer 2 package that transitively depends on it) to their own `pubspec.yaml`. This is a **breaking change** — acceptable for a major version bump.

### 1. Remove Moved Types

Delete from `packages/continuum/lib/src/persistence/`:
- `session.dart` (ContinuumSession → now `Session` in UoW)
- `session_base.dart` (SessionBase → now in UoW)
- `transactional_runner.dart` (→ now in UoW)
- `commit_handler.dart` (→ now in UoW)
- `continuum_store.dart` (ContinuumStore → now `SessionStore` in UoW)

Delete from `packages/continuum/lib/src/exceptions/`:
- `concurrency_exception.dart` (→ now in UoW)
- `invalid_operation_exception.dart` (→ now in UoW)
- `unsupported_event_exception.dart` (→ now in UoW)
- `partial_save_exception.dart` (→ now in UoW)

### 2. Backward-Compatibility Typedefs

These live in the UoW package (not Continuum, since Continuum doesn't depend on UoW):

```dart
// In continuum_uow barrel or a compat file:
typedef ContinuumSession = Session;
typedef ContinuumStore = SessionStore;
```

Consumers migrating from the old API can use either name.

### 3. Update Barrel File

Update `lib/continuum.dart` to remove deleted exports. Continuum's barrel shrinks to only Layer 0 types:
- Events, annotations, registries, `StreamId`, `GeneratedAggregate`, `EventApplicationMode`
- `EventRegistry`
- `StreamNotFoundException`, `InvalidCreationEventException`

### 4. What STAYS in Continuum

These are Continuum core — the mutation framework primitives:

- `Operation` marker interface
- `ContinuumEvent` (`implements Operation` + `BoundedDomainEvent` integration)
- `@OperationTarget`, `@OperationFor`, `@Projection` annotations
- `AggregateFactoryRegistry`, `EventApplierRegistry`
- `EventApplicationMode`
- `StreamId`
- `GeneratedAggregate`
- `EventRegistry`
- `InvalidCreationEventException`
- `StreamNotFoundException`

---

## Extracting ES and State Packages (Layer 2)

### `continuum_es` Package

**Location**: `packages/continuum_es/`
**Dependencies**: `continuum`, `continuum_uow`

Contains everything event-sourcing-specific:

| Type | Source |
|---|---|
| `EventSourcingStore` | `persistence/event_sourcing_store.dart` |
| `SessionImpl` | `persistence/session_impl.dart` |
| `EventStore` | `persistence/event_store.dart` |
| `AtomicEventStore` | `persistence/atomic_event_store.dart` |
| `EventSerializer` | `persistence/event_serializer.dart` |
| `EventSerializerRegistry` | `persistence/event_serializer_registry.dart` |
| `JsonEventSerializer` | `persistence/json_event_serializer.dart` |
| `StoredEvent` | `persistence/stored_event.dart` |
| `ExpectedVersion` | `persistence/expected_version.dart` |
| `ProjectionEventStore` | `persistence/projection_event_store.dart` |
| All projection types | `projections/` |

`EventSourcingStore` implements `SessionStore` (from UoW) and creates `SessionImpl` instances. `SessionImpl` extends `SessionBase` (from UoW).

### `continuum_state` Package

**Location**: `packages/continuum_state/`
**Dependencies**: `continuum`, `continuum_uow`

Contains everything state-based-persistence-specific:

| Type | Source |
|---|---|
| `StateBasedStore` | `persistence/state_based_store.dart` |
| `StateBasedSession` | `persistence/state_based_session.dart` |
| `AggregatePersistenceAdapter` | `persistence/aggregate_persistence_adapter.dart` |
| `PermanentAdapterException` | `exceptions/permanent_adapter_exception.dart` |
| `TransientAdapterException` | `exceptions/transient_adapter_exception.dart` |

`StateBasedStore` implements `SessionStore` (from UoW) and creates `StateBasedSession` instances. `StateBasedSession` extends `SessionBase` (from UoW).

---

## Consumer Dependency Examples

### Mode 1: Event-Driven Mutation (No Persistence)

```yaml
dependencies:
  continuum: ^2.0.0
```

User defines aggregates and events, tests with `applyAsync` in unit tests. No session, no store.

### Mode 2: Local Event Sourcing

```yaml
dependencies:
  continuum: ^2.0.0
  continuum_es: ^1.0.0
  continuum_store_hive: ^2.0.0  # or memory, sembast
```

`continuum_es` transitively brings in `continuum_uow`.

### Mode 3: State-Based Backend

```yaml
dependencies:
  continuum: ^2.0.0
  continuum_state: ^1.0.0
```

`continuum_state` transitively brings in `continuum_uow`.

### Mode 4: Custom Persistence Strategy

```yaml
dependencies:
  continuum: ^2.0.0
  continuum_uow: ^1.0.0
```

User extends `SessionBase` directly and implements `loadAsync`, `loadAllAsync`, `saveChangesAsync`, and `handleMutationOnUntrackedEntity`. Full access to identity map, 3-path detection, concurrency retry — just plugs in their own persistence backend.

---

## Custom Strategy Extension Point

This is the key value of extracting UoW as a separate package. A user whose backend doesn't fit the provided strategies extends `SessionBase`:

```dart
import 'package:continuum/continuum.dart';
import 'package:continuum_uow/continuum_uow.dart';

class GraphQLSession extends SessionBase {
  final GraphQLClient _client;

  GraphQLSession({
    required GraphQLClient client,
    required AggregateFactoryRegistry factories,
    required EventApplierRegistry appliers,
  }) : _client = client,
       super(
         aggregateFactories: factories,
         eventAppliers: appliers,
         applicationMode: EventApplicationMode.eager,
       );

  @override
  Future<TAggregate> loadAsync<TAggregate>(StreamId streamId) async {
    // Check identity map, then fetch via GraphQL query.
    // Track in identity map.
  }

  @override
  Future<List<TAggregate>> loadAllAsync<TAggregate>() async {
    // GraphQL query for all entities of type.
  }

  @override
  Future<void> saveChangesAsync({int maxRetries = 1}) async {
    // Iterate tracked entities, map pending Operations
    // to GraphQL mutations via pattern matching.
  }

  @override
  Future<TAggregate> handleMutationOnUntrackedEntity<TAggregate>(
    StreamId streamId,
    Operation operation,
    bool hasExplicitType,
  ) async {
    // Load via GraphQL, then apply.
  }
}

class GraphQLSessionStore implements SessionStore {
  @override
  Session openSession() => GraphQLSession(/* ... */);
}
```

The user gets for free:
- Identity map (no duplicate loads within a session)
- 3-path `applyAsync` detection
- Eager/deferred application mode
- Creation guard
- `TransactionalRunner` with zone-scoped session access
- `CommitHandler` post-commit hooks
- Concurrency retry scaffolding

They only implement the four persistence-specific methods.

---

## Testing Strategy

### UoW Package Tests

Write tests in `packages/continuum_uow/test/` covering:

1. **`TrackedEntity`**: construction, `withClearedPendingOperations`, operation accumulation
2. **`SessionBase` (via a concrete test subclass)**:
   - 3-path `applyAsync` detection (tracked / creation / mutation)
   - Identity map caching (load once, return same instance)
   - Creation guard (creation operation on tracked entity throws)
   - Eager mode: entity mutated immediately on `applyAsync`
   - Deferred mode: entity NOT mutated until `saveChangesAsync`
   - `discardStream` clears pending operations for one stream
   - `discardAll` clears pending operations for all streams
   - Pending operations accumulate across multiple `applyAsync` calls
   - Works with plain `Operation` implementations (no `ContinuumEvent` required)
3. **`TransactionalRunner`**:
   - Opens session, executes action, calls `saveChangesAsync` on success
   - Does NOT call `saveChangesAsync` when action throws
   - Calls `CommitHandler.onCommitAsync` after successful save
   - Does NOT call `CommitHandler` when no handler provided
   - `currentSession` returns ambient session inside `runAsync`
   - `currentSession` throws `StateError` outside `runAsync`
   - `currentSessionOrNull` returns null outside `runAsync`
   - Nested `runAsync` calls get independent sessions
4. **Exception types**: constructor, field access

Use test-only fakes implementing `Session` / `SessionStore` for `TransactionalRunner` tests. Use a concrete `SessionBase` subclass (e.g., `InMemoryTestSession`) for `SessionBase` tests. The test subclass depends on Continuum for `Operation`, `AggregateFactoryRegistry`, etc. Tests should use plain `Operation` implementations (not `ContinuumEvent`) to prove the session layer is ES-agnostic.

### Continuum Tests

After migration, ALL existing Continuum tests must continue to pass. Test code changes are acceptable for import paths (since types moved packages) but NOT for API usage — the programming model must be identical.

### ES / State Package Tests

Existing tests for `SessionImpl`, `StateBasedSession`, `EventSourcingStore`, `StateBasedStore` move to their respective packages. The tests themselves should need only import path changes.

---

## Implementation Order

### Phase 1: Create UoW Package

1. Create `packages/continuum_uow/` with `pubspec.yaml`, `analysis_options.yaml`, `LICENSE`
2. Add to workspace `pubspec.yaml` under `workspace:`
3. Move `Session` interface (from `ContinuumSession`, renamed)
4. Move `TrackedEntity` (from `StreamState`, renamed)
5. Move `SessionBase` (as-is, same Continuum type imports)
6. Move `SessionStore` interface (from `ContinuumStore`, renamed)
7. Move `TransactionalRunner` (as-is)
8. Move `CommitHandler` (as-is)
9. Move exception types (`ConcurrencyException`, `InvalidOperationException`, `UnsupportedOperationException`, `PartialSaveException`)
10. Write barrel file
11. Write tests for `SessionBase`, `TransactionalRunner`, exceptions
12. Run `dart analyze` — must be clean

### Phase 2: Create ES Package

13. Create `packages/continuum_es/` with `pubspec.yaml`, `analysis_options.yaml`, `LICENSE`
14. Add to workspace `pubspec.yaml`
15. Move `EventSourcingStore`, `SessionImpl`
16. Move event store types (`EventStore`, `AtomicEventStore`, `ExpectedVersion`, `StoredEvent`, `StreamAppendBatch`)
17. Move serialization types (`EventSerializer`, `EventSerializerRegistry`, `JsonEventSerializer`)
18. Move `ProjectionEventStore`
19. Move all projection types
20. Write barrel file
21. Move relevant tests
22. Run `dart analyze` — must be clean

### Phase 3: Create State Package

23. Create `packages/continuum_state/` with `pubspec.yaml`, `analysis_options.yaml`, `LICENSE`
24. Add to workspace `pubspec.yaml`
25. Move `StateBasedStore`, `StateBasedSession`
26. Move `AggregatePersistenceAdapter`
27. Move `PermanentAdapterException`, `TransientAdapterException`
28. Write barrel file
29. Move relevant tests
30. Run `dart analyze` — must be clean

### Phase 4: Update Store Implementations

31. Update `continuum_store_memory` to depend on `continuum_es` instead of `continuum`
32. Update `continuum_store_hive` to depend on `continuum_es` instead of `continuum`
33. Update `continuum_store_sembast` to depend on `continuum_es` instead of `continuum`
34. Update import paths in all store packages
35. Run all store package tests — must pass

### Phase 5: Clean Up Continuum Core

36. Remove all moved files from `packages/continuum/`
37. Update `lib/continuum.dart` barrel file — remove deleted exports
38. Verify Continuum only exports Layer 0 types
39. Update `continuum_generator` if generated code references moved types
40. Run `dart analyze` on ALL packages — must be clean
41. Run ALL tests across ALL packages — must pass

---

## Open Design Questions

Resolve during implementation:

1. **Package name**: `continuum_uow`, `continuum_session`, or something else?
2. **`saveChangesAsync` return type**: Current `SessionImpl.saveChangesAsync` returns `Future<List<ContinuumEvent>>`. The base `Session` interface returns `Future<void>`. If ES needs to return committed events, options:
   - ES session adds a separate `saveAndGetCommittedEventsAsync` method
   - Base returns `Future<void>` and ES session exposes committed events via a getter after save
   - Base is generic: `Session<TResult>` — evaluate complexity
3. **Generator impact**: `continuum_generator` currently emits `AggregateFactoryRegistry` and `EventApplierRegistry` references. These stay in `continuum` core, so generated code should need no changes. Verify.
4. **`ConcurrencyException` field compatibility**: Current Continuum `ConcurrencyException` has `expectedVersion` / `actualVersion` integer fields. State-based backends may use different concurrency tokens. Keep integer fields in the base (they cover the common case) or make them optional? Evaluate.
5. **Projection codegen**: `@Projection` annotation stays in `continuum` core. Generated projection code references projection types that move to `continuum_es`. Ensure the generator produces correct imports.
6. **Backward compatibility strategy**: Is a clean break (major version bump) acceptable, or do we need a deprecation period with re-exports from `continuum`? A clean break is simpler but forces all consumers to update their `pubspec.yaml`.
7. **`AggregatePersistenceAdapter.persistAsync` signature**: Currently takes `List<ContinuumEvent>`. Should change to `List<Operation>` since state-based users may use plain operations. The adapter can pattern-match or cast as needed. Verify this doesn't break existing adapter implementations.
8. **ES session validation**: `SessionImpl.saveChangesAsync` needs to validate that all pending operations are `ContinuumEvent` instances before serializing. Define the error behavior — throw `InvalidOperationException` if a non-event `Operation` is found? This is a configuration error, not a runtime error.
