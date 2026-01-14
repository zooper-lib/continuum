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
  continuum: latest

dev_dependencies:
  build_runner: ^2.4.0
  continuum_generator: latest
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
      id: event.userId,
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
import 'package:continuum/continuum.dart';
import 'package:zooper_flutter_core/zooper_flutter_core.dart';

// For Mode 1 (no persistence) you can omit `type:` and serialization.
@AggregateEvent(of: User)
class EmailChanged implements ContinuumEvent {
  EmailChanged({
    required this.userId,
    required this.newEmail,
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  final String userId;
  final String newEmail;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;
}

// For Mode 2/3 (with persistence), add `type:` and `toJson`/`fromJson`.
@AggregateEvent(of: User, type: 'user.registered')
class UserRegistered implements ContinuumEvent {
  UserRegistered({
    required this.userId,
    required this.name,
    required this.email,
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  final String userId;
  final String name;
  final String email;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  factory UserRegistered.fromJson(Map<String, dynamic> json) {
    return UserRegistered(
      userId: json['userId'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      eventId: EventId(json['eventId'] as String),
      occurredOn: DateTime.parse(json['occurredOn'] as String),
      metadata: Map<String, Object?>.from(json['metadata'] as Map),
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'name': name,
    'email': email,
    'eventId': id.toString(),
    'occurredOn': occurredOn.toIso8601String(),
    'metadata': metadata,
  };
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
    UserRegistered(userId: userId.value, name: 'Alice', email: 'alice@example.com'),
  );

  // Apply events to mutate state
  user.applyEvent(EmailChanged(userId: userId.value, newEmail: 'alice@company.com'));

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
    UserRegistered(userId: userId.value, name: 'Alice', email: 'alice@example.com'),
  );
  session.append(userId, EmailChanged(userId: userId.value, newEmail: 'alice@company.com'));
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
  final pendingEvents = <ContinuumEvent>[];
  final emailChanged = EmailChanged(userId: userId.value, newEmail: 'new@email.com');
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
import 'package:continuum/continuum.dart';
import 'package:zooper_flutter_core/zooper_flutter_core.dart';

@AggregateEvent(of: Order, type: 'order.item_added') // type required for persistence
class ItemAdded implements ContinuumEvent {
  final String itemId;

  ItemAdded({
    required this.itemId,
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;
}
```

### Sessions

Sessions track pending events and manage aggregate versions. Call `saveChangesAsync()` to commit events atomically.

```dart
final session = store.openSession();

session.startStream<Order>(
  orderId,
  OrderCreated(orderId: orderId.value, customerId: customerId),
);
session.append(orderId, ItemAdded(itemId: 'item-1'));
session.append(orderId, ItemAdded(itemId: 'item-2'));

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

## Custom Lints (Recommended)

Continuum can optionally surface common mistakes *immediately in the editor* using a custom lint plugin.

### Why use it?

Some Continuum patterns rely on generated mixins (for example `_$UserEventHandlers`). If a concrete `@Aggregate()` class forgets to implement one of the required `apply<Event>(...)` handlers, Dart can sometimes delay the failure until runtime (or until the class is instantiated, depending on how the type is used).

The `continuum_lints` package detects this situation early and reports it as a diagnostic while you type.

### Setup

Add these dev dependencies:

```yaml
dev_dependencies:
  custom_lint: ^0.8.1
  continuum_lints: ^3.1.1
```

Enable the analyzer plugin in your `analysis_options.yaml`:

```yaml
analyzer:
  plugins:
    - custom_lint
```

Optionally, configure which rules are enabled (recommended to keep things explicit):

```yaml
custom_lint:
  enable_all_lint_rules: false
  rules:
    - continuum_missing_apply_handlers
```

### CI usage

`dart analyze` does not run custom lints. In CI, run:

```bash
dart run custom_lint
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
@AggregateEvent(of: User, type: 'user.email_changed')
import 'package:continuum/continuum.dart';
import 'package:zooper_flutter_core/zooper_flutter_core.dart';

@AggregateEvent(of: User, type: 'user.email_changed')
class EmailChanged implements ContinuumEvent {
  EmailChanged({
    required this.userId,
    required this.newEmail,
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  final String userId;
  final String newEmail;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  factory EmailChanged.fromJson(Map<String, dynamic> json) {
    return EmailChanged(
      userId: json['userId'] as String,
      newEmail: json['newEmail'] as String,
      eventId: EventId(json['eventId'] as String),
      occurredOn: DateTime.parse(json['occurredOn'] as String),
      metadata: Map<String, Object?>.from(json['metadata'] as Map),
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'newEmail': newEmail,
    'eventId': id.toString(),
    'occurredOn': occurredOn.toIso8601String(),
    'metadata': metadata,
  };
}
```

The `of` links the event to its aggregate. The `type` string identifies the event type in storage—make it unique and stable.

## Examples

- [Basic usage](example/continuum_example.dart) - All three modes demonstrated
- [Hybrid mode](example/hybrid_mode_example.dart) - Optimistic UI with backend
- [Memory store](../continuum_store_memory/example/lib/main.dart) - Event sourcing persistence
- [Hive store](../continuum_store_hive/example/lib/main.dart) - Local database persistence

## Contributing

See the [repository](https://github.com/zooper-lib/continuum) for contribution guidelines.
