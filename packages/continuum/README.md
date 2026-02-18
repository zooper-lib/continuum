# Continuum

Core types and annotations for the Continuum event sourcing framework.

## Overview

This package provides the **foundational Layer 0 types** used by all other Continuum packages. It defines annotations, event contracts, identity types, and dispatch registries — but does **not** include sessions, stores, or persistence logic.

## Installation

```yaml
dependencies:
  continuum: latest

dev_dependencies:
  build_runner: ^2.4.0
  continuum_generator: latest
```

## What This Package Provides

- **Annotations**: `@AggregateEvent()`, `@Projection()`
- **Event contract**: `ContinuumEvent` interface
- **Identity types**: `EventId`, `StreamId`
- **Operation enum**: `Operation.create`, `Operation.mutate`
- **Dispatch registries**: `AggregateFactory`, `EventApplier`, `EventRegistry`
- **Generated aggregate support**: `GeneratedAggregate` bundle type
- **Event application mode**: `EventApplicationMode` (eager / deferred)
- **Core exceptions**: `EventNotRegisteredException`, `AggregateNotRegisteredException`

## Multi-Package Architecture

Continuum is organized into four layers:

| Layer | Package | Purpose |
|-------|---------|---------|
| 0 | **`continuum`** (this package) | Core types, annotations, identity |
| 1 | `continuum_uow` | Unit of Work session engine |
| 2 | `continuum_event_sourcing` | Event sourcing persistence & projections |
| 2 | `continuum_state` | State-based persistence (REST/DB adapters) |
| 3 | `continuum_store_memory` / `_hive` / `_sembast` | Store implementations |

**Choose the right package for your use case:**

- **Event sourcing** (local persistence): `continuum` + `continuum_event_sourcing` + a store package
- **State-based** (backend-authoritative): `continuum` + `continuum_state`
- **Event-driven mutation only** (no persistence): `continuum` alone

## Quick Start

### Define Your Aggregate

```dart
import 'package:continuum/continuum.dart';

part 'user.g.dart';

class User extends AggregateRoot<String> with _$UserEventHandlers {
  String name;
  String email;

  User._({required super.id, required this.name, required this.email});

  static User createFromUserRegistered(UserRegistered event) {
    return User._(id: event.userId, name: event.name, email: event.email);
  }

  @override
  void applyEmailChanged(EmailChanged event) {
    email = event.newEmail;
  }
}
```

### Define Your Events

```dart
import 'package:continuum/continuum.dart';

@AggregateEvent(of: User, type: 'user.registered', creation: true)
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
}
```

### Generate Code

```bash
dart run build_runner build
```

This creates:
- `user.g.dart` with `_$UserEventHandlers` mixin
- `lib/continuum.g.dart` with `$aggregateList`

## Custom Lints (Recommended)

Surface common mistakes in the editor using `continuum_lints`:

```yaml
dev_dependencies:
  custom_lint: ^0.8.1
  continuum_lints: latest
```

```yaml
# analysis_options.yaml
analyzer:
  plugins:
    - custom_lint
```

## Contributing

See the [repository](https://github.com/zooper-lib/continuum) for contribution guidelines.
