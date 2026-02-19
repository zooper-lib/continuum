# Continuum State

State-based persistence strategy for [Continuum](https://github.com/zooper-lib/continuum). Provides adapter-driven aggregate persistence for backends that store full aggregate state (REST APIs, databases, GraphQL) rather than event streams.

## Installation

```yaml
dependencies:
  continuum: latest
  continuum_state: latest

dev_dependencies:
  build_runner: ^2.4.0
  continuum_generator: latest
```

## Key Concepts

### StateBasedStore

The configuration root for state-based persistence. Instead of persisting events, each aggregate is loaded and saved through an `AggregatePersistenceAdapter`.

```dart
import 'package:continuum_state/continuum_state.dart';
import 'continuum.g.dart';

final store = StateBasedStore(
  adapters: {User: UserApiAdapter(httpClient)},
  aggregates: $aggregateList,
);

final session = store.openSession();
await session.applyAsync<User>(userId, UserRegistered(...));
await session.saveChangesAsync(); // Adapter persists to backend
```

### AggregatePersistenceAdapter

Each adapter implements two methods — `fetchAsync` to load an aggregate and `persistAsync` to save it:

```dart
class UserApiAdapter implements AggregatePersistenceAdapter<User> {
  final HttpClient _client;

  UserApiAdapter(this._client);

  @override
  Future<User> fetchAsync(StreamId streamId) async {
    final response = await _client.get('/users/${streamId.value}');
    return User.fromJson(response.body);
  }

  @override
  Future<void> persistAsync(
    StreamId streamId,
    User aggregate,
    List<ContinuumEvent> pendingEvents,
  ) async {
    await _client.put('/users/${streamId.value}', body: aggregate.toJson());
  }
}
```

### Exceptions

- `TransientAdapterException` — retriable adapter failure
- `PermanentAdapterException` — non-retriable adapter failure

## Architecture

This package sits at **Layer 2** of the Continuum architecture (alongside `continuum_event_sourcing`). It depends on `continuum` (core types) and `continuum_uow` (session engine).

## License

MIT
