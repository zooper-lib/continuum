import 'dart:async';

import '../persistence/stored_event.dart';
import 'async_projection_executor.dart';
import 'projection_position.dart';
import 'projection_position_store.dart';

/// Abstraction for continuous projection processing.
abstract interface class ProjectionProcessor {
  /// Starts continuous projection processing.
  Future<void> startAsync();

  /// Stops continuous projection processing.
  Future<void> stopAsync();

  /// Processes a single batch of events.
  Future<ProcessingResult> processBatchAsync();
}

/// Function type for loading events from a global sequence position.
typedef EventLoader =
    Future<List<StoredEvent>> Function(
      int fromGlobalSequence,
      int limit,
    );

/// Polling-based implementation of [ProjectionProcessor].
///
/// Periodically checks for new events and processes them through
/// async projections. Uses a configurable batch size and polling
/// interval.
final class PollingProjectionProcessor implements ProjectionProcessor {
  /// Default batch size for event loading.
  static const int defaultBatchSize = 100;

  /// Default polling interval between batch checks.
  static const Duration defaultPollingInterval = Duration(seconds: 1);

  /// The async projection executor.
  final AsyncProjectionExecutor _executor;

  /// Store for tracking the processor's global position.
  final ProjectionPositionStore _positionStore;

  /// Function to load events from the event store.
  final EventLoader _eventLoader;

  /// Maximum events per batch.
  final int _batchSize;

  /// Time between polling cycles.
  final Duration _pollingInterval;

  /// Key used to store the processor's position.
  final String _positionKey;

  /// Timer for periodic polling.
  Timer? _timer;

  /// Whether the processor is currently running.
  bool _isRunning = false;

  /// Whether a batch is currently being processed.
  bool _isProcessing = false;

  /// Creates a polling projection processor with the given configuration.
  PollingProjectionProcessor({
    required AsyncProjectionExecutor executor,
    required ProjectionPositionStore positionStore,
    required EventLoader eventLoader,
    int batchSize = defaultBatchSize,
    Duration pollingInterval = defaultPollingInterval,
    String positionKey = '_processor_position',
  }) : _executor = executor,
       _positionStore = positionStore,
       _eventLoader = eventLoader,
       _batchSize = batchSize,
       _pollingInterval = pollingInterval,
       _positionKey = positionKey;

  /// Whether the processor is currently running.
  bool get isRunning => _isRunning;

  @override
  Future<void> startAsync() async {
    if (_isRunning) {
      return;
    }

    _isRunning = true;

    _timer = Timer.periodic(_pollingInterval, (_) {
      _pollAsync();
    });

    // Process immediately on start.
    await _pollAsync();
  }

  @override
  Future<void> stopAsync() async {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;

    // Wait for any in-progress batch to complete.
    while (_isProcessing) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  @override
  Future<ProcessingResult> processBatchAsync() async {
    if (_isProcessing) {
      return const ProcessingResult(processed: 0, failed: 0);
    }

    _isProcessing = true;
    try {
      return await _processBatchInternalAsync();
    } finally {
      _isProcessing = false;
    }
  }

  /// Internal polling cycle handler.
  Future<void> _pollAsync() async {
    if (!_isRunning || _isProcessing) {
      return;
    }

    await processBatchAsync();
  }

  /// Core batch processing logic.
  Future<ProcessingResult> _processBatchInternalAsync() async {
    final lastPosition = await _positionStore.loadPositionAsync(_positionKey);
    final lastSequence = lastPosition?.lastProcessedSequence ?? -1;
    final fromPosition = lastSequence + 1;

    final events = await _eventLoader(fromPosition, _batchSize);

    if (events.isEmpty) {
      return const ProcessingResult(processed: 0, failed: 0);
    }

    final schemaHash = lastPosition?.schemaHash ?? '';
    final result = await _executor.processEventsAsync(
      events,
      schemaHash: schemaHash,
    );

    // Only advance position if all projections succeeded.
    if (result.failed != 0) {
      return result;
    }

    final lastEvent = events.last;
    if (lastEvent.globalSequence != null) {
      await _positionStore.savePositionAsync(
        _positionKey,
        ProjectionPosition(
          lastProcessedSequence: lastEvent.globalSequence,
          schemaHash: schemaHash,
        ),
      );
    }

    return result;
  }
}
