import '../persistence/stored_event.dart';
import 'projection_registration.dart';
import 'projection_registry.dart';

/// Executes inline projections synchronously during event persistence.
///
/// The executor is invoked by the session after events are persisted.
/// It applies each event to all matching inline projections, updating
/// read models immediately.
///
/// If any projection fails, the executor throws an exception, which
/// should cause the caller to abort the transaction.
final class InlineProjectionExecutor {
  /// The registry containing projection registrations.
  final ProjectionRegistry _registry;

  /// Creates an inline projection executor.
  ///
  /// The [registry] must contain all projections that should be
  /// executed inline.
  InlineProjectionExecutor({required ProjectionRegistry registry}) : _registry = registry;

  /// Executes inline projections for the given events.
  ///
  /// For each event, finds all matching inline projections and applies
  /// the event to update their read models.
  ///
  /// Events are processed in order. For each event:
  /// 1. Find all inline projections that handle the event's type
  /// 2. For each projection:
  ///    a. Load the current read model (or create initial if missing)
  ///    b. Apply the event to produce updated read model
  ///    c. Save the updated read model
  ///
  /// Throws if any projection fails. The caller is responsible for
  /// handling the failure (e.g., rolling back the event persistence).
  Future<void> executeAsync(List<StoredEvent> events) async {
    if (!_registry.hasInlineProjections) {
      // Fast path: no inline projections registered.
      return;
    }

    for (final event in events) {
      await _processEventAsync(event);
    }
  }

  /// Processes a single event through all matching inline projections.
  Future<void> _processEventAsync(StoredEvent event) async {
    // Look up projections by the stored event type string.
    // Since we don't have the runtime Type, we need to check all inline projections.
    final projections = _registry.inlineProjections;

    for (final registration in projections) {
      // Check if this projection handles this event type by checking the eventType string.
      // Since we store event type as string, we need the projection to declare string-based matching
      // or we use the registered Type set. For now, we'll iterate and let the projection decide.
      if (_shouldProcess(registration, event)) {
        await _applyEventToProjectionAsync(registration, event);
      }
    }
  }

  /// Checks if a projection should process the given event.
  ///
  /// This is a temporary implementation. In practice, projections should
  /// declare which event type strings they handle, or the registry should
  /// maintain a mapping from event type strings to projections.
  bool _shouldProcess(
    ProjectionRegistration<Object, Object> registration,
    StoredEvent event,
  ) {
    // For now, always process. The projection's apply method should be
    // designed to handle only events it cares about.
    // A more sophisticated implementation would use event type string matching.
    return true;
  }

  /// Applies an event to a projection, updating its read model.
  Future<void> _applyEventToProjectionAsync(
    ProjectionRegistration<Object, Object> registration,
    StoredEvent event,
  ) async {
    final projection = registration.projection;
    final store = registration.readModelStore;

    // Extract the key for this event.
    final key = projection.extractKey(event);

    // Load existing read model or create initial.
    var readModel = await store.loadAsync(key);
    readModel ??= projection.createInitial(key);

    // Apply the event to produce updated read model.
    final updatedReadModel = projection.apply(readModel, event);

    // Persist the updated read model.
    await store.saveAsync(key, updatedReadModel);
  }
}
