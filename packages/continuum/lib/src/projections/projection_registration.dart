import 'projection.dart';
import 'projection_lifecycle.dart';
import 'read_model_store.dart';

/// Holds a projection along with its configuration metadata.
///
/// This class bundles a projection instance with its execution lifecycle
/// and read model storage, enabling the registry and executors to
/// correctly route and process events.
final class ProjectionRegistration<TReadModel, TKey> {
  /// The projection instance that processes events.
  final Projection<TReadModel, TKey> projection;

  /// The execution lifecycle (inline or async).
  final ProjectionLifecycle lifecycle;

  /// The store for persisting this projection's read models.
  final ReadModelStore<TReadModel, TKey> readModelStore;

  /// Creates a projection registration.
  ///
  /// All parameters are required—projections must have a defined lifecycle
  /// and storage to function correctly.
  const ProjectionRegistration({
    required this.projection,
    required this.lifecycle,
    required this.readModelStore,
  });

  /// The unique name identifying this projection.
  String get projectionName => projection.projectionName;

  /// The set of event types this projection handles.
  Set<Type> get handledEventTypes => projection.handledEventTypes;

  /// Checks whether this projection handles the given event type.
  bool handles(Type eventType) => projection.handles(eventType);
}
