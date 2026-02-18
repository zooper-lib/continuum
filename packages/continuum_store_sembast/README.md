# Continuum Store Sembast

Sembast-backed `EventStore` implementation for [Continuum](https://github.com/zooper-lib/continuum). Events are persisted locally using Sembast and survive app restarts.

## Installation

```yaml
dependencies:
  continuum: latest
  continuum_event_sourcing: latest
  continuum_store_sembast: latest
  sembast: ^3.8.6
```

## Usage

```dart
import 'package:continuum_event_sourcing/continuum_event_sourcing.dart';
import 'package:continuum_store_sembast/continuum_store_sembast.dart';
import 'package:sembast/sembast_io.dart';
import 'continuum.g.dart'; // Generated

void main() async {
  // Open the Sembast event store
  final eventStore = await SembastEventStore.openAsync(
    databaseFactory: databaseFactoryIo,
    dbPath: '/path/to/events.db',
  );

  final store = EventSourcingStore(
    eventStore: eventStore,
    aggregates: $aggregateList,
  );

  // Use your aggregates
  final userId = StreamId('user-1');
  final session = store.openSession();
  await session.applyAsync<User>(
    userId,
    UserRegistered(userId: userId.value, name: 'Alice', email: 'alice@example.com'),
  );
  await session.saveChangesAsync();

  // Events are persisted - survive app restart
  final readSession = store.openSession();
  final user = await readSession.loadAsync<User>(userId);
}
```

## When to Use

**Good for:**
- Flutter mobile apps (offline-first, no native plugins needed)
- Desktop applications
- Web applications (via `sembast_web`)
- Local-first architectures
- Cross-platform persistence with a pure Dart solution

**Not suitable for:**
- Multi-user backends (use a proper database)
- Large-scale event stores (Sembast loads the database into memory)

## API

### SembastEventStore.openAsync()

Opens or creates a Sembast database for event storage.

```dart
final eventStore = await SembastEventStore.openAsync(
  databaseFactory: databaseFactoryIo,
  dbPath: 'events.db',
);
```

The `databaseFactory` parameter lets you choose the storage backend:
- `databaseFactoryIo` from `package:sembast/sembast_io.dart` for Dart VM / Flutter.
- `databaseFactoryWeb` from `package:sembast_web/sembast_web.dart` for Flutter Web.

### Closing the Store

Close when your app shuts down:

```dart
await eventStore.closeAsync();
```

## Example

See [example/lib/main.dart](example/lib/main.dart) for a complete example with two aggregates.
