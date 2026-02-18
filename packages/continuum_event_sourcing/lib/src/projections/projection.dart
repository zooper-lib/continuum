import '../persistence/stored_event.dart';

/// Base class for all projection types.
///
/// Projections transform stored events into read models. Each projection
/// specifies which event types it handles, how to extract a key from
/// an event, how to create an initial read model, and how to apply
/// an event to update the read model.
abstract class ProjectionBase<TReadModel, TKey> {
  /// The event types this projection handles.
  Set<Type> get handledEventTypes;

  /// The unique name for this projection.
  String get projectionName;

  /// Extracts the key for the read model from a stored event.
  TKey extractKey(StoredEvent event);

  /// Creates an initial read model for the given key.
  TReadModel createInitial(TKey key);

  /// Applies a stored event to an existing read model, returning the updated model.
  TReadModel apply(TReadModel current, StoredEvent event);

  /// Whether this projection handles events of the given [eventType].
  bool handles(Type eventType) => handledEventTypes.contains(eventType);
}
