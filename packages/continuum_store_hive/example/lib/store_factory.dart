import 'package:continuum/continuum.dart';
import 'package:continuum_store_hive/continuum_store_hive.dart';
import 'package:continuum_store_hive_example/continuum.g.dart';

/// Creates an [EventSourcingStore] configured for the example package.
EventSourcingStore createStore({required HiveEventStore hiveStore}) {
  return EventSourcingStore(
    eventStore: hiveStore,
    aggregates: $aggregateList,
  );
}
