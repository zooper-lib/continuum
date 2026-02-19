import 'projection_base.dart';
import 'projection_lifecycle.dart';
import 'read_model_store.dart';

/// Bundles a projection with its lifecycle mode and read model store.
///
/// Used by [ProjectionRegistry] to manage registered projections.
final class ProjectionRegistration<TReadModel, TKey> {
  /// The projection implementation.
  final ProjectionBase<TReadModel, TKey> projection;

  /// Whether this projection runs inline or async.
  final ProjectionLifecycle lifecycle;

  /// The store for the projection's read models.
  final ReadModelStore<TReadModel, TKey> readModelStore;

  /// Creates a projection registration with the given configuration.
  const ProjectionRegistration({
    required this.projection,
    required this.lifecycle,
    required this.readModelStore,
  });

  /// The unique name of the registered projection.
  String get projectionName => projection.projectionName;

  /// The event types handled by the registered projection.
  Set<Type> get handledEventTypes => projection.handledEventTypes;

  /// Whether the registered projection handles the given [eventType].
  bool handles(Type eventType) => projection.handles(eventType);
}
