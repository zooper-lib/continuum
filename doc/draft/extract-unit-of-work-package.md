# Extract Unit of Work Package

## Goal

Extract a standalone, persistence-strategy-agnostic Unit of Work (UoW) package from the Continuum monorepo. The package provides session lifecycle management (identity map, atomic commit, discard, concurrency retry) and a zone-scoped transactional runner — without any dependency on Continuum, event sourcing, domain events, or code generation.

Continuum will then depend on this package and extend its abstractions for event-sourcing-specific concerns.

## Package Identity

- **Name**: `synchron`
- **Location**: `packages/synchron/`
- **SDK constraint**: `^3.10.4` (same as workspace)
- **Runtime dependencies**: none
- **Dev dependencies**: `lints`, `test`
- **Must be added** to the workspace `pubspec.yaml` under `workspace:`

## Why This Package Exists

The Continuum codebase already contains types that are not event-sourcing-specific but are currently locked inside the `continuum` package:

- `TransactionalRunner` — zone-scoped session lifecycle. Its only coupling to Continuum is that `saveChangesAsync()` returns `List<ContinuumEvent>` and `CommitHandler` receives that list.
- `ContinuumStore` — a pure session factory (`openSession()`). No ES concepts.
- `ContinuumSession` — the session interface. `loadAsync`, `loadAllAsync`, `saveChangesAsync`, `discardStream`, `discardAll` are generic UoW operations. Only `applyAsync(StreamId, ContinuumEvent)` is ES-specific.
- `StreamId` — a typed string wrapper with no event-sourcing behavior. Functions as a generic entity ID.
- `ConcurrencyException` — optimistic concurrency error. Generic concept.
- `InvalidOperationException` — general-purpose domain error. Generic concept.
- `PartialSaveException` — multi-entity partial commit failure. Generic concept (currently coupled only via `StreamId` naming).

The package should capture these generic UoW concerns so they can be used independently by:
1. Plain CRUD repositories (no events at all)
2. Event-sourced aggregates (via Continuum, which extends the base types)
3. Mixed use-cases where both strategies coexist in one transactional scope

## Public API Surface

### Types to Create

Each type below lives in its own file under `lib/src/`. All are exported from the barrel `lib/synchron.dart`.

---

### `EntityId` (`lib/src/entity_id.dart`)

Replaces `StreamId` as the generic entity identifier.

```dart
final class EntityId {
  final String value;
  const EntityId(this.value);
  // == , hashCode, toString
}
```

Same implementation as current `StreamId`. Pure value object, no behavior.

---

### `Session` (`lib/src/session.dart`)

The core UoW interface. Equivalent to the generic subset of `ContinuumSession`.

```dart
abstract interface class Session {
  /// Loads an entity by ID. Returns cached instance if already loaded (identity map).
  Future<TEntity> loadAsync<TEntity>(EntityId id);

  /// Loads all entities of the given type.
  Future<List<TEntity>> loadAllAsync<TEntity>();

  /// Persists all pending changes atomically.
  /// Returns a commit result that subclasses can specialize.
  Future<void> saveChangesAsync({int maxRetries = 1});

  /// Discards pending changes for a specific entity.
  void discard(EntityId id);

  /// Discards all pending changes across all tracked entities.
  void discardAll();
}
```

Key design decisions:
- `saveChangesAsync` returns `Future<void>` — not `Future<List<ContinuumEvent>>`. The event list is an ES concern; Continuum's `ContinuumSession` extends `Session` and overrides the return type to provide it.
- No `applyAsync` method — that is an event-driven concept. Continuum adds it.
- `discard` instead of `discardStream` — generic naming.

---

### `SessionStore` (`lib/src/session_store.dart`)

Session factory. Equivalent to current `ContinuumStore`.

```dart
abstract interface class SessionStore {
  Session openSession();
}
```

---

### `TransactionalRunner` (`lib/src/transactional_runner.dart`)

Zone-scoped session lifecycle manager. Same logic as current `TransactionalRunner` but generic.

```dart
final class TransactionalRunner {
  final SessionStore _store;
  final CommitHandler? _commitHandler;

  TransactionalRunner({
    required SessionStore store,
    CommitHandler? commitHandler,
  });

  Future<T> runAsync<T>(Future<T> Function() action) async {
    final session = _store.openSession();
    final result = await runZoned(action, zoneValues: {_sessionKey: session});
    await session.saveChangesAsync();
    if (_commitHandler != null) {
      await _commitHandler.onCommitAsync();
    }
    return result;
  }

  static Session get currentSession { ... }
  static Session? get currentSessionOrNull { ... }
}
```

Key difference from current implementation:
- Depends on `SessionStore` and `Session` (generic), not `ContinuumStore` and `ContinuumSession`.
- `CommitHandler.onCommitAsync()` takes no arguments in the base version. See below.

---

### `CommitHandler` (`lib/src/commit_handler.dart`)

Post-commit side-effect hook.

```dart
abstract interface class CommitHandler {
  Future<void> onCommitAsync();
}
```

The base `CommitHandler` is a pure lifecycle hook — "commit succeeded, do side effects." It receives no arguments because the generic UoW does not know what a "change" looks like (events? dirty entities? nothing?).

Continuum will define its own `EventCommitHandler` that extends or replaces this with `onCommitAsync(List<ContinuumEvent> events)`. The `TransactionalRunner` in Continuum can be configured with the Continuum-specific handler. Alternatively, Continuum may override `TransactionalRunner` behavior via its own extended session that publishes events during `saveChangesAsync`.

---

### `ConcurrencyException` (`lib/src/concurrency_exception.dart`)

Generic optimistic concurrency error.

```dart
final class ConcurrencyException implements Exception {
  final EntityId entityId;
  final String message;
  const ConcurrencyException({required this.entityId, required this.message});
}
```

Simpler than current version. Drops `expectedVersion` / `actualVersion` fields because version semantics vary by strategy (ES uses integer stream versions; a REST API might use ETags). Subclasses can add strategy-specific details. Consider keeping `expectedVersion` and `actualVersion` as optional fields if they are useful generically.

**Decision needed during implementation**: keep it minimal (just `entityId` + `message`) or carry version info. Prefer minimal — Continuum can subclass or use its own.

---

### `InvalidOperationException` (`lib/src/invalid_operation_exception.dart`)

Identical to current implementation. No changes needed.

```dart
final class InvalidOperationException implements Exception {
  final String message;
  const InvalidOperationException({required this.message});
}
```

---

### `PartialSaveException` (`lib/src/partial_save_exception.dart`)

Multi-entity partial commit failure.

```dart
final class PartialSaveException implements Exception {
  final List<EntityId> savedEntities;
  final List<EntityId> failedEntities;
  final Object cause;
  const PartialSaveException({
    required this.savedEntities,
    required this.failedEntities,
    required this.cause,
  });
}
```

Same as current but uses `EntityId` instead of `StreamId`.

---

## Barrel File

`lib/synchron.dart`:

```dart
library;

export 'src/commit_handler.dart';
export 'src/concurrency_exception.dart';
export 'src/entity_id.dart';
export 'src/invalid_operation_exception.dart';
export 'src/partial_save_exception.dart';
export 'src/session.dart';
export 'src/session_store.dart';
export 'src/transactional_runner.dart';
```

---

## Changes to Continuum Package

After `synchron` exists, Continuum must be updated to depend on it and extend its abstractions. These changes happen in `packages/continuum/`.

### 1. Add Dependency

In `packages/continuum/pubspec.yaml`, add:
```yaml
dependencies:
  synchron: ^1.0.0
```

### 2. `StreamId` → Re-export or Subtype of `EntityId`

**Option A (preferred)**: Make `StreamId` a typedef for `EntityId`:
```dart
typedef StreamId = EntityId;
```

**Option B**: Keep `StreamId` as a separate class but make it extend or wrap `EntityId`. This adds complexity for little gain.

**Option C**: Replace all `StreamId` usages with `EntityId` directly. This is a breaking change for Continuum consumers.

**Recommendation**: Option A (typedef). Zero breaking change — `StreamId` continues to work everywhere. The `EntityId` type flows through the UoW layer, and `StreamId` is just a domain-specific alias.

### 3. `ContinuumSession` Extends `Session`

```dart
abstract interface class ContinuumSession implements Session {
  // Inherited from Session:
  //   loadAsync, loadAllAsync, saveChangesAsync, discard, discardAll

  // ES-specific additions:
  Future<TAggregate> applyAsync<TAggregate>(StreamId streamId, ContinuumEvent event);

  // Override return type to provide committed events:
  @override
  Future<List<ContinuumEvent>> saveChangesAsync({int maxRetries = 1});
}
```

Note: `saveChangesAsync` return type changes from `Future<void>` (base) to `Future<List<ContinuumEvent>>` (Continuum). This is a covariant return type widening — Dart allows this on interface overrides. **Verify this compiles.**

If covariant return widening from `void` to `List<ContinuumEvent>` is not valid in Dart, the base `Session.saveChangesAsync` should return `Future<Object?>` or use a generic type parameter. Alternatively, the base returns `Future<void>` and Continuum adds a separate `saveAndReturnEventsAsync` method. Determine the cleanest approach during implementation.

### 4. `ContinuumStore` Implements `SessionStore`

```dart
abstract interface class ContinuumStore implements SessionStore {
  @override
  ContinuumSession openSession();
}
```

Covariant return type: `SessionStore.openSession()` returns `Session`; `ContinuumStore.openSession()` returns `ContinuumSession` (which implements `Session`). This is valid in Dart.

### 5. Exception Migration

- `InvalidOperationException` — Continuum re-exports from `synchron`. Remove the Continuum copy.
- `ConcurrencyException` — Continuum keeps its own version (with `expectedVersion` / `actualVersion` integer fields) OR extends the UoW base. Decide during implementation.
- `PartialSaveException` — Continuum re-exports from `synchron`. Remove the Continuum copy. Since `StreamId` is now a typedef for `EntityId`, the types align.

### 6. `TransactionalRunner` Migration

Continuum should re-export `TransactionalRunner` from `synchron`, OR provide a thin Continuum-specific wrapper that passes committed events to a Continuum-specific `CommitHandler`. Evaluate which approach is cleaner. The current `CommitHandler` in Continuum receives `List<ContinuumEvent>` — this needs a bridge.

**Possible approach**: Continuum keeps its own `CommitHandler` (with events) and wraps the UoW `TransactionalRunner`:

```dart
// In Continuum:
final class ContinuumTransactionalRunner {
  final TransactionalRunner _runner;
  final ContinuumCommitHandler? _commitHandler;

  Future<T> runAsync<T>(Future<T> Function() action) async {
    return _runner.runAsync(() async {
      final result = await action();
      // Post-commit: the session is a ContinuumSession, so we can get events
      return result;
    });
  }
}
```

Alternatively, the base `TransactionalRunner` could be generic over session type, allowing Continuum to use it directly. Evaluate during implementation.

### 7. Barrel File Updates

Remove from `lib/continuum.dart`:
- Direct exports of `InvalidOperationException`, `PartialSaveException` (re-export from `synchron` instead)
- Consider re-exporting `synchron.dart` so Continuum consumers get the base types automatically

Add to `lib/continuum.dart`:
```dart
export 'package:synchron/synchron.dart' show EntityId, Session, SessionStore, TransactionalRunner;
```

Or re-export the entire barrel if appropriate.

---

## What Is NOT Extracted

The following remain in Continuum. They are inherently event-sourcing-specific:

- `ContinuumEvent` and all event types
- `AggregateFactoryRegistry`, `EventApplierRegistry`
- `EventApplicationMode` (eager/deferred)
- `SessionBase` (the shared event-application logic base class)
- `SessionImpl` (event-store-backed session)
- `StateBasedSession` (adapter-backed session — still uses event application internally)
- `EventStore`, `AtomicEventStore`, `EventSerializer`, `StoredEvent`, `ExpectedVersion`
- `AggregatePersistenceAdapter`
- `EventSourcingStore`, `StateBasedStore`
- All projection types
- All annotations and code generation

---

## Testing Strategy

### `synchron` Tests

Write tests in `packages/synchron/test/` covering:

1. **`EntityId`**: equality, hashCode, toString
2. **`TransactionalRunner`**:
   - Opens a session, executes action, calls `saveChangesAsync` on success
   - Does NOT call `saveChangesAsync` when action throws
   - Calls `CommitHandler.onCommitAsync` after successful save
   - Does NOT call `CommitHandler` when no handler provided
   - `currentSession` returns the ambient session inside `runAsync`
   - `currentSession` throws `StateError` outside `runAsync`
   - `currentSessionOrNull` returns `null` outside `runAsync`
   - Nested `runAsync` calls get independent sessions
3. **Exception types**: constructor, toString, equality of fields

Use a `FakeSession` implementing `Session` and a `FakeSessionStore` implementing `SessionStore` for testing. These are test-only — not exported.

### Continuum Tests

After migration, all existing Continuum tests must continue to pass. The `StreamId` typedef and `ContinuumSession extends Session` changes must be transparent to existing test code.

---

## Implementation Order

1. Create `packages/synchron/` with `pubspec.yaml`, `analysis_options.yaml`, `LICENSE`
2. Add to workspace `pubspec.yaml`
3. Implement `EntityId`
4. Implement exception types (`ConcurrencyException`, `InvalidOperationException`, `PartialSaveException`)
5. Implement `Session` interface
6. Implement `SessionStore` interface
7. Implement `CommitHandler` interface
8. Implement `TransactionalRunner`
9. Write barrel file
10. Write tests for all types
11. Add `synchron` dependency to `packages/continuum/pubspec.yaml`
12. Make `StreamId` a typedef for `EntityId`
13. Make `ContinuumSession` extend `Session`
14. Make `ContinuumStore` implement `SessionStore`
15. Migrate shared exceptions (remove duplicates from Continuum, re-export from UoW)
16. Migrate or wrap `TransactionalRunner` in Continuum
17. Update Continuum barrel file
18. Run all Continuum tests — must pass with zero changes to test code
19. Run `dart analyze` on both packages — must pass clean

---

## Open Design Questions

These should be resolved during implementation:

1. **`saveChangesAsync` return type**: Can `ContinuumSession` override `Future<void>` with `Future<List<ContinuumEvent>>`? If not, what's the cleanest alternative?
2. **`ConcurrencyException` shape**: Minimal (`entityId` + `message`) or carry version fields? Continuum needs versions — should the base carry them as optional fields, or should Continuum subclass?
3. **`TransactionalRunner` + `CommitHandler` bridge**: Does Continuum re-use the base `TransactionalRunner` and wrap its `CommitHandler`, or provide its own runner subclass?
4. **Re-export strategy**: Does `continuum.dart` re-export all of `synchron.dart`, or only specific types?
