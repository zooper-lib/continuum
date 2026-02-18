# Continuum UoW

Unit of Work session engine for [Continuum](https://github.com/zooper-lib/continuum). Provides the session lifecycle: identity map, operation recording, atomic commit, transactional runner, and the extension point for custom persistence strategies.

## Installation

```yaml
dependencies:
  continuum: latest
  continuum_uow: latest
```

## Key Concepts

### Session & SessionBase

`Session` is the interface for tracking pending operations against aggregate streams. `SessionBase` is the abstract implementation providing identity map, event application, and three-path detection (create / mutate / load). Persistence strategies extend `SessionBase` to plug in their own commit logic.

### SessionStore

`SessionStore` is the interface that persistence strategies implement to open sessions. Both `EventSourcingStore` and `StateBasedStore` implement this interface.

### TransactionalRunner

Manages the full session lifecycle: open → execute → commit → publish. Uses Dart zones to provide an **ambient session** accessible anywhere within the transaction scope.

```dart
final runner = TransactionalRunner(
  store: store,
  commitHandler: myCommitHandler, // Optional
);

await runner.runAsync(() async {
  final session = TransactionalRunner.currentSession;
  await session.applyAsync<User>(userId, UserRegistered(...));
  // Auto-commits on success. If the action throws, no events are saved.
});
```

### CommitHandler

A pluggable interface for post-commit side effects. After `saveChangesAsync()` succeeds, the handler receives the list of committed operations. The handler is **not** called when no operations were committed.

```dart
abstract interface class CommitHandler {
  Future<void> onCommitAsync(List<Operation> committedOperations);
}
```

### Exceptions

- `ConcurrencyException` — version conflict on save
- `InvalidOperationException` — invalid session operation
- `UnsupportedOperationException` — operation not supported by the store
- `PartialSaveException` — partial failures when saving multiple streams

## Architecture

This package sits at **Layer 1** of the Continuum architecture. It depends only on `continuum` (core types) and is consumed by both `continuum_event_sourcing` and `continuum_state`.

## License

MIT
