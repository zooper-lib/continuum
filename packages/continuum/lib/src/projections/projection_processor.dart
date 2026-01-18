import 'dart:async';

import '../persistence/stored_event.dart';
import 'async_projection_executor.dart';
import 'projection_position_store.dart';

/// Abstraction for background projection processing.
///
/// The processor polls for new events and applies them to async projections.
/// It manages its own lifecycle and can be started/stopped as needed.
abstract interface class ProjectionProcessor {
  /// Starts the background projection processor.
  ///
  /// After calling this, the processor will continuously poll for
  /// new events and apply them to registered async projections.
  Future<void> startAsync();

  /// Stops the background projection processor.
  ///
  /// Completes any in-progress work before stopping.
  /// After calling this, no more events will be processed until
  /// [startAsync] is called again.
  Future<void> stopAsync();

  /// Processes a single batch of events.
  ///
  /// Useful for manual control of projection processing, testing,
  /// or when continuous background processing is not desired.
  ///
  /// Returns the result of processing the batch.
  Future<ProcessingResult> processBatchAsync();
}

/// Function type for loading events from a position.
///
/// Used to decouple the processor from the event store implementation.
typedef EventLoader =
    Future<List<StoredEvent>> Function(
      int fromGlobalSequence,
      int limit,
    );

/// Polling-based implementation of [ProjectionProcessor].
///
/// Periodically polls for new events using a configurable interval
/// and processes them through the async projection executor.
final class PollingProjectionProcessor implements ProjectionProcessor {
  /// Default batch size for loading events.
  static const int defaultBatchSize = 100;

  /// Default polling interval.
  static const Duration defaultPollingInterval = Duration(seconds: 1);

  /// The async projection executor.
  final AsyncProjectionExecutor _executor;

  /// The position store for tracking overall processing position.
  final ProjectionPositionStore _positionStore;

  /// Function to load events from a position.
  final EventLoader _eventLoader;

  /// Batch size for loading events.
  final int _batchSize;

  /// Interval between polling attempts.
  final Duration _pollingInterval;

  /// Key used to track the processor's overall position.
  final String _positionKey;

  /// Timer for periodic polling.
  Timer? _timer;

  /// Flag indicating whether the processor is running.
  bool _isRunning = false;

  /// Flag to prevent concurrent batch processing.
  bool _isProcessing = false;

  /// Creates a polling projection processor.
  ///
  /// Parameters:
  /// - [executor]: The async projection executor to use.
  /// - [positionStore]: Store for tracking processing position.
  /// - [eventLoader]: Function to load events from a global sequence.
  /// - [batchSize]: Number of events to load per batch.
  /// - [pollingInterval]: Time between polling attempts.
  /// - [positionKey]: Key for storing the processor's position.
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
      return; // Already running.
    }

    _isRunning = true;

    // Start periodic polling.
    _timer = Timer.periodic(_pollingInterval, (_) {
      // Fire and forget - don't await to avoid blocking the timer.
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

    // Wait for any in-progress processing to complete.
    while (_isProcessing) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  @override
  Future<ProcessingResult> processBatchAsync() async {
    if (_isProcessing) {
      // Already processing, return empty result.
      return const ProcessingResult(processed: 0, failed: 0);
    }

    _isProcessing = true;
    try {
      return await _processBatchInternalAsync();
    } finally {
      _isProcessing = false;
    }
  }

  /// Internal polling method.
  Future<void> _pollAsync() async {
    if (!_isRunning || _isProcessing) {
      return;
    }

    await processBatchAsync();
  }

  /// Processes a batch of events.
  Future<ProcessingResult> _processBatchInternalAsync() async {
    // Load current position (null means start from beginning).
    final lastPosition = await _positionStore.loadPositionAsync(_positionKey);
    final fromPosition = (lastPosition ?? -1) + 1;

    // Load next batch of events.
    final events = await _eventLoader(fromPosition, _batchSize);

    if (events.isEmpty) {
      return const ProcessingResult(processed: 0, failed: 0);
    }

    // Process events through the executor.
    final result = await _executor.processEventsAsync(events);

    // Update overall processor position to the last event's global sequence.
    final lastEvent = events.last;
    if (lastEvent.globalSequence != null) {
      await _positionStore.savePositionAsync(
        _positionKey,
        lastEvent.globalSequence!,
      );
    }

    return result;
  }
}
