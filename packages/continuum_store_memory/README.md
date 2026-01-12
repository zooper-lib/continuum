# Continuum Store Memory

In-memory `EventStore` implementation for [continuum](../continuum). Events are stored in memory and lost when the application exits.

## Installation

```yaml
dependencies:
  continuum: latest
  continuum_store_memory: latest
```

## Usage

```dart
import 'package:continuum/continuum.dart';
import 'package:continuum_store_memory/continuum_store_memory.dart';
import 'continuum.g.dart'; // Generated

void main() async {
  final store = EventSourcingStore(
    eventStore: InMemoryEventStore(),
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

  final readSession = store.openSession();
  final user = await readSession.loadAsync<User>(userId);
}
```

## When to Use

**Good for:**
- Unit tests and integration tests
- Development and prototyping
- Demos and examples
- Short-lived processes

**Not suitable for:**
- Production applications (data is not persisted)
- Long-running applications that need durability

For production, use [continuum_store_hive](../continuum_store_hive) or implement your own `EventStore`.

## API

### InMemoryEventStore()

Creates a new in-memory event store.

```dart
final eventStore = InMemoryEventStore();
```

All events are stored in memory and will be lost when the instance is garbage collected or the application exits.

## Example

See [example/lib/main.dart](example/lib/main.dart) for a complete example.

## License

MIT
