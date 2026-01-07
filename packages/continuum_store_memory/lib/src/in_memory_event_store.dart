import 'package:continuum/continuum.dart';

/// In-memory implementation of [EventStore].
///
/// Stores events in memory, suitable for testing and development.
/// Events are lost when the store instance is garbage collected.
///
/// Thread-safety: This implementation is not thread-safe. For concurrent
/// access, external synchronization is required.
final class InMemoryEventStore implements AtomicEventStore {
  /// Internal storage of events by stream ID.
  final Map<StreamId, List<StoredEvent>> _streams = {};

  /// Global sequence counter for optional global ordering.
  int _globalSequence = 0;

  @override
  Future<List<StoredEvent>> loadStreamAsync(StreamId streamId) async {
    // Return a copy of the events to prevent external modification
    final events = _streams[streamId];
    if (events == null) {
      return [];
    }
    return List.unmodifiable(events);
  }

  @override
  Future<void> appendEventsToStreamsAsync(
    Map<StreamId, StreamAppendBatch> batches,
  ) async {
    if (batches.isEmpty) {
      return;
    }

    final Map<StreamId, List<StoredEvent>> preparedEventsByStream = <StreamId, List<StoredEvent>>{};

    for (final MapEntry<StreamId, StreamAppendBatch> entry in batches.entries) {
      final StreamId streamId = entry.key;
      final StreamAppendBatch batch = entry.value;

      final List<StoredEvent>? existingStreamEvents = _streams[streamId];
      final int currentVersion = (existingStreamEvents == null || existingStreamEvents.isEmpty) ? -1 : existingStreamEvents.last.version;

      _throwIfExpectedVersionDoesNotMatch(
        streamId: streamId,
        expectedVersion: batch.expectedVersion,
        currentVersion: currentVersion,
      );

      final List<StoredEvent> preparedEvents = <StoredEvent>[];
      int nextVersion = currentVersion + 1;

      for (final StoredEvent event in batch.events) {
        preparedEvents.add(
          StoredEvent(
            eventId: event.eventId,
            streamId: streamId,
            version: nextVersion,
            eventType: event.eventType,
            data: event.data,
            occurredOn: event.occurredOn,
            metadata: event.metadata,
            globalSequence: _globalSequence++,
          ),
        );
        nextVersion++;
      }

      preparedEventsByStream[streamId] = preparedEvents;
    }

    for (final MapEntry<StreamId, List<StoredEvent>> entry in preparedEventsByStream.entries) {
      final StreamId streamId = entry.key;
      final List<StoredEvent> preparedEvents = entry.value;

      if (_streams.containsKey(streamId)) {
        _streams[streamId]!.addAll(preparedEvents);
      } else {
        _streams[streamId] = preparedEvents;
      }
    }
  }

  @override
  Future<void> appendEventsAsync(StreamId streamId, ExpectedVersion expectedVersion, List<StoredEvent> events) async {
    await appendEventsToStreamsAsync(
      <StreamId, StreamAppendBatch>{
        streamId: StreamAppendBatch(expectedVersion: expectedVersion, events: events),
      },
    );
  }

  /// Validates optimistic concurrency expectations.
  ///
  /// Throws a [ConcurrencyException] when the caller's [expectedVersion] does
  /// not match the current state of the stream.
  void _throwIfExpectedVersionDoesNotMatch({
    required StreamId streamId,
    required ExpectedVersion expectedVersion,
    required int currentVersion,
  }) {
    if (expectedVersion.isNoStream) {
      if (currentVersion != -1) {
        throw ConcurrencyException(streamId: streamId, expectedVersion: -1, actualVersion: currentVersion);
      }
      return;
    }

    if (currentVersion != expectedVersion.value) {
      throw ConcurrencyException(streamId: streamId, expectedVersion: expectedVersion.value, actualVersion: currentVersion);
    }
  }

  /// Clears all events from the store.
  ///
  /// Useful for resetting state between tests.
  void clear() {
    _streams.clear();
    _globalSequence = 0;
  }

  /// Returns the number of streams in the store.
  int get streamCount => _streams.length;

  /// Returns the total number of events across all streams.
  int get eventCount => _streams.values.fold(0, (sum, events) => sum + events.length);
}
