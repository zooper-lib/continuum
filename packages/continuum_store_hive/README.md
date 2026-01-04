# Continuum Store Hive

Hive-backed EventStore implementation for the continuum event sourcing library.

## Usage

```dart
import 'package:continuum_store_hive/continuum_store_hive.dart';
import 'package:hive/hive.dart';

// Initialize Hive first
Hive.init('/path/to/storage');

// Create the store
final store = await HiveEventStore.openAsync(boxName: 'events');
```

This implementation provides local persistence using Hive. Events are stored in a Hive box and persist across app restarts.
