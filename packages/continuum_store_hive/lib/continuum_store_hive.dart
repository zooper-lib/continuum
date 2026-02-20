/// Hive-backed store implementations for the continuum library.
///
/// Provides persistent local [EventStore], [ReadModelStore], and
/// [AggregatePersistenceAdapter] implementations using Hive.
library;

export 'src/hive_event_store.dart';
export 'src/hive_persistence_adapter.dart';
export 'src/hive_read_model_store.dart';
