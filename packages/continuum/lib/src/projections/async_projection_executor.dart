import '../persistence/stored_event.dart';
import 'projection_position_store.dart';
import 'projection_registration.dart';
import 'projection_registry.dart';

/// Executes async projections for background processing.
///
/// The executor processes events through all matching async projections,
/// tracking position for each projection to enable resumption after restarts.
///
/// Unlike inline projections, async projection failures are logged and
/// can be retried without affecting event persistence.
final class AsyncProjectionExecutor {
  /// The registry containing projection registrations.
  final ProjectionRegistry _registry;

  /// Store for tracking each projection's processing position.
  final ProjectionPositionStore _positionStore;

  /// Creates an async projection executor.
  AsyncProjectionExecutor({
    required ProjectionRegistry registry,
    required ProjectionPositionStore positionStore,
  }) : _registry = registry,
       _positionStore = positionStore;

  /// Processes events through all matching async projections.
  ///
  /// For each event, finds all matching async projections and applies
  /// the event to update their read models. Position is updated after
  /// each successful projection execution.
  ///
  /// Events must have a non-null [StoredEvent.globalSequence] for
  /// position tracking to work correctly.
  ///
  /// Returns a [ProcessingResult] indicating success/failure counts.
  Future<ProcessingResult> processEventsAsync(List<StoredEvent> events) async {
    if (!_registry.hasAsyncProjections || events.isEmpty) {
      return const ProcessingResult(processed: 0, failed: 0);
    }

    var processed = 0;
    var failed = 0;

    for (final event in events) {
      final result = await _processEventAsync(event);
      processed += result.processed;
      failed += result.failed;
    }

    return ProcessingResult(processed: processed, failed: failed);
  }

  /// Processes a single event through all matching async projections.
  Future<ProcessingResult> _processEventAsync(StoredEvent event) async {
    final projections = _registry.asyncProjections;
    var processed = 0;
    var failed = 0;

    for (final registration in projections) {
      try {
        await _applyEventToProjectionAsync(registration, event);
        processed++;

        // Update position after successful processing.
        if (event.globalSequence != null) {
          await _positionStore.savePositionAsync(
            registration.projectionName,
            event.globalSequence!,
          );
        }
      } catch (error) {
        // Log error but continue processing other projections.
        // In a production system, this would integrate with logging/monitoring.
        failed++;
      }
    }

    return ProcessingResult(processed: processed, failed: failed);
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

  /// Gets the last processed position for a projection.
  ///
  /// Returns `null` if the projection has never processed any events.
  Future<int?> getPositionAsync(String projectionName) async {
    return _positionStore.loadPositionAsync(projectionName);
  }

  /// Resets a projection's position to process from the beginning.
  ///
  /// Useful for rebuilding a projection's read models from scratch.
  Future<void> resetPositionAsync(String projectionName) async {
    final positionStore = _positionStore;
    if (positionStore is InMemoryProjectionPositionStore) {
      positionStore.remove(projectionName);
    }
    // For other implementations, setting position to -1 or similar would work.
  }
}

/// Result of processing events through async projections.
final class ProcessingResult {
  /// Number of successfully processed projection applications.
  final int processed;

  /// Number of failed projection applications.
  final int failed;

  /// Creates a processing result.
  const ProcessingResult({required this.processed, required this.failed});

  /// Whether all projection applications succeeded.
  bool get isSuccess => failed == 0;

  /// Total number of projection applications attempted.
  int get total => processed + failed;
}
