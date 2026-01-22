import '../persistence/stored_event.dart';
import 'projection_position.dart';
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
  /// The [schemaHash] is used to track schema versions and detect changes.
  ///
  /// Returns a [ProcessingResult] indicating success/failure counts.
  Future<ProcessingResult> processEventsAsync(
    List<StoredEvent> events, {
    String schemaHash = '',
  }) async {
    if (!_registry.hasAsyncProjections || events.isEmpty) {
      return const ProcessingResult(processed: 0, failed: 0);
    }

    var processed = 0;
    var failed = 0;

    for (final event in events) {
      final result = await _processEventAsync(event, schemaHash: schemaHash);
      processed += result.processed;
      failed += result.failed;
    }

    return ProcessingResult(processed: processed, failed: failed);
  }

  /// Processes a single event through all matching async projections.
  Future<ProcessingResult> _processEventAsync(
    StoredEvent event, {
    String schemaHash = '',
  }) async {
    final domainEvent = event.domainEvent;
    if (domainEvent == null) {
      // Without a deserialized domain event we cannot route by runtime type.
      // Count this as a failure for all async projections.
      return ProcessingResult(
        processed: 0,
        failed: _registry.asyncProjections.length,
      );
    }

    final projections = _registry.getAsyncProjectionsForEventType(
      domainEvent.runtimeType,
    );
    var processed = 0;
    var failed = 0;

    for (final registration in projections) {
      try {
        await _applyEventToProjectionAsync(registration, event);
        processed++;

        // Update position after successful processing.
        if (event.globalSequence != null) {
          final position = ProjectionPosition(
            lastProcessedSequence: event.globalSequence,
            schemaHash: schemaHash,
          );
          await _positionStore.savePositionAsync(
            registration.projectionName,
            position,
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
  Future<ProjectionPosition?> getPositionAsync(String projectionName) async {
    return _positionStore.loadPositionAsync(projectionName);
  }

  /// Resets a projection's position to process from the beginning.
  ///
  /// Useful for rebuilding a projection's read models from scratch.
  Future<void> resetPositionAsync(String projectionName) async {
    await _positionStore.resetPositionAsync(projectionName);
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
