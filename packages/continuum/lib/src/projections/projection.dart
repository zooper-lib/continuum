import '../persistence/stored_event.dart';

/// Base abstraction for projections that transform events into read models.
///
/// Projections are pure event consumers that:
/// - Do NOT load aggregates
/// - Do NOT issue commands
/// - Do NOT have side effects beyond updating the read model
///
/// Subclasses define the specific read model type and key extraction logic.
///
/// Note: This class is named `ProjectionBase` to avoid collision with the
/// `@Projection()` annotation. Users should extend [SingleStreamProjection]
/// or [MultiStreamProjection] instead of this class directly.
abstract class ProjectionBase<TReadModel, TKey> {
  /// The set of event types this projection handles.
  ///
  /// Only events with runtime types in this set will be routed to this projection.
  /// Subclasses must override to declare their event dependencies.
  Set<Type> get handledEventTypes;

  /// A unique name identifying this projection.
  ///
  /// Used for position tracking in async projections and for debugging.
  String get projectionName;

  /// Extracts the key used to identify the read model instance.
  ///
  /// For single-stream projections, this is typically the stream ID.
  /// For multi-stream projections, this is a grouping key derived from event data.
  TKey extractKey(StoredEvent event);

  /// Creates the initial read model state for a new key.
  ///
  /// Called when processing the first event for a given key.
  TReadModel createInitial(TKey key);

  /// Applies an event to update the read model.
  ///
  /// Returns the updated read model. Implementations must be pure and
  /// deterministic—the same event applied to the same read model must
  /// always produce the same result.
  TReadModel apply(TReadModel current, StoredEvent event);

  /// Checks whether this projection handles the given event type.
  bool handles(Type eventType) => handledEventTypes.contains(eventType);
}
