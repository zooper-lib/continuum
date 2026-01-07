# Continuum Generator

Code generator for the [continuum](../continuum) event sourcing library. Automatically generates event handling code and discovers all aggregates in your project.

## What It Generates

### Per-Aggregate Files (`*.g.dart`)

For each `@Aggregate()` class, generates:

1. **Event handler mixin** (`_$YourAggregateEventHandlers`)
   - Connects your `applyEventName()` methods to events
   - Type-safe event dispatching

2. **Extensions**:
   - `applyEvent()` - Apply single event to aggregate
   - `replayEvents()` - Reconstruct aggregate from event stream
   - `createFromEvent()` - Factory for first event

3. **Registries** (for persistence):
   - Event serialization registry
   - Aggregate factory registry  
   - Event applier registry

### Global Discovery (`lib/continuum.g.dart`)

Automatically discovers all `@Aggregate()` classes and generates:

```dart
final List<GeneratedAggregate> $aggregateList = [
  $Account,
  $User,
  // ... all aggregates sorted alphabetically
];
```

This enables zero-configuration setup:

```dart
final store = EventSourcingStore(
  eventStore: myStore,
  aggregates: $aggregateList, // Just works!
);
```

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  continuum: ^0.1.0

dev_dependencies:
  build_runner: ^2.4.0
  continuum_generator: ^0.1.0
```

## Usage

### 1. Annotate Your Classes

```dart
import 'package:continuum/continuum.dart';

part 'user.g.dart';

@Aggregate()
class User with _$UserEventHandlers {
  final String id;
  String email;

  User._({required this.id, required this.email});

  static User createFromUserCreated(UserCreated event) {
    return User._(id: event.aggregateId.value, email: event.email);
  }

  @override
  void applyEmailChanged(EmailChanged event) {
    email = event.newEmail;
  }
}

@Event(ofAggregate: User, type: 'user.created')
class UserCreated extends DomainEvent {
  final String email;
  UserCreated(StreamId aggregateId, this.email) : super(aggregateId);
  
  Map<String, dynamic> toJson() => {'email': email};
  factory UserCreated.fromJson(StreamId id, Map<String, dynamic> json) {
    return UserCreated(id, json['email'] as String);
  }
}

@Event(ofAggregate: User, type: 'user.email_changed')
class EmailChanged extends DomainEvent {
  final String newEmail;
  EmailChanged(StreamId aggregateId, this.newEmail) : super(aggregateId);
  
  Map<String, dynamic> toJson() => {'newEmail': newEmail};
  factory EmailChanged.fromJson(StreamId id, Map<String, dynamic> json) {
    return EmailChanged(id, json['newEmail'] as String);
  }
}
```

### 2. Run Build Runner

```bash
# One-time build
dart run build_runner build

# Watch mode (rebuilds on file changes)
dart run build_runner watch

# Clean previous builds
dart run build_runner build --delete-conflicting-outputs
```

### 3. Use Generated Code

```dart
// Import your aggregate (with generated part)
import 'domain/user.dart';

// Import auto-discovered list
import 'continuum.g.dart';

void main() {
  // Zero-configuration setup!
  final store = EventSourcingStore(
    eventStore: InMemoryEventStore(),
    aggregates: $aggregateList,
  );

  final userId = StreamId('123');

  // Create + mutate within a session
  final session = store.openSession();
  session.startStream<User>(userId, UserCreated(userId, 'alice@example.com'));
  await session.saveChangesAsync();

  // Load aggregate (reconstructed from events)
  final readSession = store.openSession();
  final user = await readSession.loadAsync<User>(userId);
  print(user.email); // alice@example.com
}
```

## Generated Code Structure

### Event Handler Mixin

The generator creates a mixin that dispatches events to your apply methods:

```dart
// Generated in user.g.dart
mixin _$UserEventHandlers {
  void applyEmailChanged(EmailChanged event);
  
  void $applyEvent(DomainEvent event) {
    if (event is EmailChanged) return applyEmailChanged(event);
    throw UnknownEventException(event.runtimeType);
  }
}
```

### Extension Methods

```dart
// Generated in user.g.dart
extension UserEventSourcingExtensions on User {
  void applyEvent(DomainEvent event) {
    $applyEvent(event);
  }
  
  static User replayEvents(Iterable<DomainEvent> events) {
    // Replays events to reconstruct aggregate
  }
  
  static User createFromEvent(DomainEvent event) {
    // Calls User.createFromUserCreated() etc.
  }
}
```

## Build Configuration

### Custom Configuration (Optional)

Create `build.yaml` in your project root:

```yaml
targets:
  $default:
    builders:
      continuum_generator:
        enabled: true
        options:
          # Options can be added here in future versions
```

### Multiple Packages

If you have multiple packages with aggregates, run build_runner in each:

```bash
# In package A
cd packages/domain_a
dart run build_runner build

# In package B  
cd ../domain_b
dart run build_runner build
```

Each package gets its own `continuum.g.dart` with its aggregates.

## How Auto-Discovery Works

The generator scans all `.dart` files in your `lib/` directory for `@Aggregate()` annotations and collects them into `$aggregateList`. This happens in a separate build phase after all per-aggregate generators complete.

**You don't need to:**
- Manually import aggregate files
- Maintain a registry
- Merge multiple registries

**Just:**
1. Add `@Aggregate()` annotation
2. Run `build_runner`
3. Use `$aggregateList`

## Troubleshooting

### "part 'file.g.dart' not found"

Run the generator:
```bash
dart run build_runner build
```

### "Undefined name '_$MyAggregateEventHandlers'"

Make sure:
1. You have `part 'my_aggregate.g.dart';` directive
2. Your class has the `@Aggregate()` annotation
3. You've run `build_runner`

### "No apply method found for event"

Ensure your aggregate has a method like:
```dart
MyAggregate applyMyEvent(MyEvent event) { ... }
```

The method name must be `apply` + event class name.

### Changes not reflected

Try rebuilding with clean:
```bash
dart run build_runner build --delete-conflicting-outputs
```

## Examples

See the [continuum package examples](../continuum/example/) for complete usage examples.

## Contributing

See the [repository](https://github.com/zooper-lib/continuum) for contribution guidelines.

## License

MIT
