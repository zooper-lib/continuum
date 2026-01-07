# Continuum

A flexible event sourcing and domain event modeling framework for Dart and Flutter.

## Philosophy

Continuum is built around **domain events as a modeling tool**. Events describe meaningful state transitions, and aggregates define how those transitions affect domain state. Unlike traditional event sourcing frameworks, Continuum supports multiple usage modes depending on where your source of truth lives.

## Three Usage Modes

### Mode 1: Event-Driven Mutation (No Persistence)

Use events as typed, explicit state transitions with aggregate validation. Only final state is persisted (CRUD style). Events are not stored or replayed.

**Use when:**
- Building clean domain models with strong invariants
- You want explicit mutations without event sourcing overhead
- Backend uses traditional CRUD persistence

### Mode 2: Frontend-Only Event Sourcing

The frontend is the source of truth. Events are persisted locally (SQLite, Hive, etc.) and aggregates are reconstructed by replaying events.

**Use when:**
- Building offline-first applications
- Single-user desktop tools
- No backend or backend is just for sync/backup

### Mode 3: Hybrid Mode (Backend as Source of Truth)

Backend is authoritative, frontend uses events for optimistic UI. Frontend events are transient and discarded after backend confirms. The backend may use its own event sourcing or CRUD—your frontend doesn't care.

**Use when:**
- Building responsive UIs with optimistic updates
- Need undo/cancel before committing
- Backend handles validation and persistence

## Quick Start

### Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  continuum: ^0.1.0

dev_dependencies:
  build_runner: ^2.4.0
  continuum_generator: ^0.1.0
```

### 1. Define Your Aggregate

```dart
import 'package:continuum/continuum.dart';

part 'user.g.dart';

@Aggregate()
class User with _$UserEventHandlers {
  final String id;
  String name;
  String email;

  User._({required this.id, required this.name, required this.email});

  // Static factory for creating from first event
  static User createFromUserRegistered(UserRegistered event) {
    return User._(
      id: event.aggregateId.value,
      name: event.name,
      email: event.email,
    );
  }

  // Apply methods define state transitions (override generated mixin)
  @override
  void applyEmailChanged(EmailChanged event) {
    email = event.newEmail;
  }

  @override
  void applyNameChanged(NameChanged event) {
    name = event.newName;
  }
}
```

### 2. Define Your Events

```dart
// For Mode 1 (no persistence):
@Event(ofAggregate: User)
class EmailChanged extends DomainEvent {
  final String newEmail;
  EmailChanged(StreamId aggregateId, this.newEmail) : super(aggregateId);
}

// For Mode 2/3 (with persistence), add type strings:
@Event(ofAggregate: User, type: 'user.email_changed')
class EmailChanged extends DomainEvent {
  final String newEmail;
  EmailChanged(StreamId aggregateId, this.newEmail) : super(aggregateId);

  // Serialization for persistence
  Map<String, dynamic> toJson() => {'newEmail': newEmail};
  factory EmailChanged.fromJson(StreamId id, Map<String, dynamic> json) {
    return EmailChanged(id, json['newEmail'] as String);
  }
}

@Event(ofAggregate: User, type: 'user.registered')
class UserRegistered extends DomainEvent {
  final String name;
  final String email;
  
  UserRegistered(StreamId aggregateId, this.name, this.email) 
    : super(aggregateId);

  Map<String, dynamic> toJson() => {'name': name, 'email': email};
  factory UserRegistered.fromJson(StreamId id, Map<String, dynamic> json) {
    return UserRegistered(id, json['name'] as String, json['email'] as String);
  }
}
```

### 3. Generate Code

```bash
dart run build_runner build
```

This creates:
- `user.g.dart` with event handling mixin
- `lib/continuum.g.dart` with `$aggregateList` (auto-discovered!)

### 4. Use Your Aggregate

#### Mode 1: Simple State Transitions

```dart
void main() {
  final userId = StreamId('123');

  // Create from a creation event
  final user = User.createFromUserRegistered(
    UserRegistered(userId, 'Alice', 'alice@example.com'),
  );

  // Apply events to mutate state
  user.applyEvent(EmailChanged(userId, 'alice@company.com'));

  print(user.email); // alice@company.com

  // Save final state to your database (events not persisted)
}
```

#### Mode 2: Frontend Event Sourcing

```dart
import 'package:continuum_store_memory/continuum_store_memory.dart';

void main() async {
  // Setup (zero configuration - $aggregateList auto-discovered!)
  final store = EventSourcingStore(
    eventStore: InMemoryEventStore(),
    aggregates: $aggregateList, // Generated automatically!
  );

  final userId = StreamId('user-123');

  // Create + mutate within a session
  final session = store.openSession();
  session.startStream<User>(
    userId,
    UserRegistered(userId, 'Alice', 'alice@example.com'),
  );
  session.append(userId, EmailChanged(userId, 'alice@company.com'));
  await session.saveChangesAsync();

  // Load aggregate (reconstructed from events)
  final readSession = store.openSession();
  final user = await readSession.loadAsync<User>(userId);
  print(user.email); // alice@company.com
}
```

#### Mode 3: Hybrid with Backend

```dart
void main() async {
  // Backend is source of truth.
  // On the frontend, keep transient domain events for optimistic UI.

  final userId = StreamId('user-123');
  final user = await backendApi.fetchUser(userId);

  // User edits email in UI (optimistic)
  final pendingEvents = <DomainEvent>[];
  final emailChanged = EmailChanged(userId, 'new@email.com');
  pendingEvents.add(emailChanged);
  user.applyEvent(emailChanged);

  updateUI(user); // Show immediately

  // Convert to a request DTO and send to backend
  final dto = {'email': user.email};
  final confirmed = await backendApi.updateUser(userId, dto);

  // Discard local events; replace with backend response
  pendingEvents.clear();
  displayUser(User.fromBackend(confirmed));
}
```

See [hybrid_mode_example.dart](example/hybrid_mode_example.dart) for a complete example.

## Core Concepts

### Aggregates

Aggregates are domain objects that encapsulate business logic and invariants. They transition between states by applying events.

```dart
@Aggregate()
class Order with _$OrderEventHandlers {
  final String id;
  final List<String> items;
  final OrderStatus status;
  
  // Constructor, factories, and apply methods...
}
```

### Events

Events represent things that have happened. They are immutable and describe state changes.

```dart
@Event(ofAggregate: Order, type: 'order.item_added') // type required for persistence
class ItemAdded extends DomainEvent {
  final String itemId;
  ItemAdded(StreamId aggregateId, this.itemId) : super(aggregateId);
}
```

### Sessions

Sessions track pending events and manage aggregate versions. Call `saveChangesAsync()` to commit events atomically.

```dart
final session = store.openSession();

session.startStream<Order>(orderId, OrderCreated(orderId, customerId));
session.append(orderId, ItemAdded(orderId, 'item-1'));
session.append(orderId, ItemAdded(orderId, 'item-2'));

await session.saveChangesAsync(); // All or nothing
```

### Event Sourcing Store

The `EventSourcingStore` is your configuration root. It automatically merges all aggregate registries.

```dart
final store = EventSourcingStore(
  eventStore: InMemoryEventStore(), // or HiveEventStore
  aggregates: $aggregateList, // Auto-discovered - just run build_runner!
);
```

## Code Generation

Continuum uses code generation to eliminate boilerplate. When you run `build_runner`, it generates:

1. **Per-aggregate files** (`user.g.dart`):
   - `_$UserEventHandlers` mixin with event dispatcher
   - `applyEvent()` extension method
   - `replayEvents()` for reconstruction
   - `createFromEvent()` factory
   - Event serialization registry

2. **Global file** (`lib/continuum.g.dart`):
   - `$aggregateList` with all aggregates in your project
   - Auto-discovered from `@Aggregate()` annotations

### Build Configuration

Add to `build.yaml` (optional, for customization):

```yaml
targets:
  $default:
    builders:
      continuum_generator:
        enabled: true
```

## Working with Persistence

### Event Stores

Continuum provides pluggable event storage:

- `continuum_store_memory`: In-memory (testing/development)
- `continuum_store_hive`: Local Hive persistence (production)
- Custom: Implement `EventStore` interface for your own backend

### Optimistic Concurrency

Prevent conflicting writes with version checks:

```dart
try {
  await session.saveChangesAsync();
} on ConcurrencyException catch (e) {
  // Handle conflict: reload and retry, or show error to user
  print('Conflict: expected ${e.expectedVersion}, got ${e.actualVersion}');
}
```

### Event Serialization

Events are serialized to JSON for storage. Implement `toJson()` and `fromJson()`:

```dart
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

The `ofAggregate` links the event to its aggregate. The `type` string identifies the event type in storage—make it unique and stable.

## Examples

- [Basic usage](example/continuum_example.dart) - All three modes demonstrated
- [Hybrid mode](example/hybrid_mode_example.dart) - Optimistic UI with backend
- [Memory store](../continuum_store_memory/example/lib/main.dart) - Event sourcing persistence
- [Hive store](../continuum_store_hive/example/lib/main.dart) - Local database persistence

## Contributing

See the [repository](https://github.com/zooper-lib/continuum) for contribution guidelines.
