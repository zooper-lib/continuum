# Continuum Store Memory

In-memory EventStore implementation for the continuum event sourcing library.

## Usage

```dart
import 'package:continuum_store_memory/continuum_store_memory.dart';

final store = InMemoryEventStore();
```

This implementation is suitable for testing and development. For production use, consider `continuum_store_hive` or other persistent implementations.
