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
    final domainEvent = event.domainEvent;
    if (domainEvent == null) {
      throw StateError(
        'StoredEvent.domainEvent is null. '
        'Projections require deserialized domain events.',
      );
    }

    final projections = _registry.getInlineProjectionsForEventType(
      domainEvent.runtimeType,
    );

    for (final registration in projections) {
      await _applyEventToProjectionAsync(registration, event);
    }
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
