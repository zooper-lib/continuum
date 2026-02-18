import 'package:continuum/continuum.dart';

import '../persistence/stored_event.dart';
import 'projection_position.dart';
import 'projection_position_store.dart';

/// Executes async projections for background processing.
///
/// The executor processes events through all matching async projections,
/// tracking position for each projection to enable resumption after restarts.
///
/// Unlike inline projections, async projection failures are logged and
/// can be retried without affecting event persistence.
final class AsyncProjectionExecutor {
  /// The registry of projections to check for matches.
  final ProjectionRegistry _registry;

  /// Store for tracking projection positions.
  final ProjectionPositionStore _positionStore;

  /// Creates an async projection executor with the given dependencies.
  AsyncProjectionExecutor({
    required ProjectionRegistry registry,
    required ProjectionPositionStore positionStore,
  }) : _registry = registry,
       _positionStore = positionStore;

  /// Processes events through all matching async projections.
  ///
  /// Returns a [ProcessingResult] summarizing successes and failures.
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

        // Save position after successful processing.
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
        failed++;
      }
    }

    return ProcessingResult(processed: processed, failed: failed);
  }

  /// Applies a single event to a single projection's read model.
  ///
  /// Extracts the domain event (an [Operation]) from the [StoredEvent]
  /// and delegates to the projection's [extractKey] and [apply] methods.
  Future<void> _applyEventToProjectionAsync(
    ProjectionRegistration<Object, Object> registration,
    StoredEvent event,
  ) async {
    final projection = registration.projection;
    final store = registration.readModelStore;

    // Extract the typed operation from the ES storage envelope.
    final domainEvent = event.domainEvent;
    if (domainEvent == null) {
      throw StateError(
        'StoredEvent.domainEvent is null. '
        'Async projections require deserialized domain events.',
      );
    }

    final key = projection.extractKey(domainEvent);

    var readModel = await store.loadAsync(key);
    readModel ??= projection.createInitial(key);

    final updatedReadModel = projection.apply(readModel, domainEvent);

    await store.saveAsync(key, updatedReadModel);
  }

  /// Gets the current position for the named projection.
  Future<ProjectionPosition?> getPositionAsync(String projectionName) async {
    return _positionStore.loadPositionAsync(projectionName);
  }

  /// Resets the position for the named projection, triggering a full replay.
  Future<void> resetPositionAsync(String projectionName) async {
    await _positionStore.resetPositionAsync(projectionName);
  }
}

/// Result of processing a batch of events through async projections.
final class ProcessingResult {
  /// The number of successfully processed projection applications.
  final int processed;

  /// The number of failed projection applications.
  final int failed;

  /// Creates a processing result with the given counts.
  const ProcessingResult({required this.processed, required this.failed});

  /// Whether all projection applications succeeded.
  bool get isSuccess => failed == 0;

  /// The total number of projection applications attempted.
  int get total => processed + failed;
}
