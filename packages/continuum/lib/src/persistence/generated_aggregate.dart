import 'event_serializer_registry.dart';
import 'event_sourcing_store.dart';

/// Bundles all generated registries for a single aggregate type.
///
/// Each aggregate generates one of these, containing its serializer
/// registry, aggregate factories, and event appliers. Pass a list
/// of these to [EventSourcingStore] for automatic merging.
///
/// ```dart
/// // Generated in user.g.dart:
/// const $User = GeneratedAggregate(
///   serializerRegistry: EventSerializerRegistry({...}),
///   aggregateFactories: AggregateFactoryRegistry({...}),
///   eventAppliers: EventApplierRegistry({...}),
/// );
///
/// // Usage:
/// final store = EventSourcingStore(
///   eventStore: InMemoryEventStore(),
///   aggregates: [$User, $Account],
/// );
/// ```
final class GeneratedAggregate {
  /// Serializer entries for all events of this aggregate.
  final EventSerializerRegistry serializerRegistry;

  /// Factory functions for creating this aggregate from creation events.
  final AggregateFactoryRegistry aggregateFactories;

  /// Applier functions for mutating this aggregate with events.
  final EventApplierRegistry eventAppliers;

  /// Creates a generated aggregate bundle with all required registries.
  const GeneratedAggregate({
    required this.serializerRegistry,
    required this.aggregateFactories,
    required this.eventAppliers,
  });
}
