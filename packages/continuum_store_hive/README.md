# Continuum Store Hive

Hive-backed `EventStore` implementation for [continuum](../continuum). Events are persisted locally using Hive and survive app restarts.

## Installation

```yaml
dependencies:
  continuum: latest
  continuum_store_hive: latest
  hive: ^2.2.3
```

## Usage

```dart
import 'package:continuum/continuum.dart';
import 'package:continuum_store_hive/continuum_store_hive.dart';
import 'package:hive/hive.dart';
import 'continuum.g.dart'; // Generated

void main() async {
  // Initialize Hive (required)
  Hive.init('/path/to/storage');
  
  // Create event store
  final eventStore = await HiveEventStore.openAsync(boxName: 'events');
  
  final store = EventSourcingStore(
    eventStore: eventStore,
    aggregates: $aggregateList,
  );

  // Use your aggregates
  final userId = StreamId('user-1');
  final session = store.openSession();
  session.startStream<User>(
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
- Flutter mobile apps (offline-first)
- Desktop applications
- Local-first architectures
- Prototypes that need persistence
- Development with realistic data

**Not suitable for:**
- Multi-user backends (use a proper database)
- Large-scale event stores (Hive is not optimized for millions of events)

## API

### HiveEventStore.openAsync()

Opens or creates a Hive box for event storage.

```dart
final eventStore = await HiveEventStore.openAsync(
  boxName: 'events', // Box name - defaults to 'events'
);
```

**Note:** You must call `Hive.init()` before opening the store. For Flutter apps:

```dart
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  Hive.init(dir.path);
  
  // Now open store
  final eventStore = await HiveEventStore.openAsync();
  // ...
}
```

### Closing the Store

Close when your app shuts down:

```dart
await eventStore.close();
```

## Example

See [example/lib/main.dart](example/lib/main.dart) for a complete example with two aggregates.

## License

MIT
