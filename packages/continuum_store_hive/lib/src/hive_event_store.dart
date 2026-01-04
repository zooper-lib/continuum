import 'dart:convert';

import 'package:continuum/continuum.dart';
import 'package:hive/hive.dart';

/// Hive-backed implementation of [EventStore].
///
/// Stores events in a Hive box for local persistence.
/// Events survive app restarts and device reboots.
///
/// The store uses a composite key structure to efficiently query events
/// by stream ID while maintaining per-stream ordering.
final class HiveEventStore implements EventStore {
  /// The Hive box for storing events.
  final Box<String> _eventsBox;

  /// The Hive box for storing stream metadata (current version).
  final Box<int> _streamsBox;

  /// Global sequence counter for ordered projections.
  int _globalSequence;

  /// Private constructor - use [openAsync] factory.
  HiveEventStore._({required Box<String> eventsBox, required Box<int> streamsBox, required int globalSequence})
    : _eventsBox = eventsBox,
      _streamsBox = streamsBox,
      _globalSequence = globalSequence;

  /// Opens a Hive event store with the given box names.
  ///
  /// If the boxes already exist, they are reopened with existing data.
  /// The [boxName] parameter is used as a prefix for the internal boxes.
  static Future<HiveEventStore> openAsync({required String boxName}) async {
    final eventsBox = await Hive.openBox<String>('${boxName}_events');
    final streamsBox = await Hive.openBox<int>('${boxName}_streams');

    // Determine the current global sequence by finding the max
    final globalSequence = eventsBox.isEmpty ? 0 : _findMaxGlobalSequence(eventsBox);

    return HiveEventStore._(eventsBox: eventsBox, streamsBox: streamsBox, globalSequence: globalSequence);
  }

  /// Finds the maximum global sequence in the events box.
  static int _findMaxGlobalSequence(Box<String> eventsBox) {
    var maxSequence = 0;
    for (final json in eventsBox.values) {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final sequence = decoded['globalSequence'] as int? ?? 0;
      if (sequence > maxSequence) {
        maxSequence = sequence;
      }
    }
    return maxSequence + 1;
  }

  @override
  Future<List<StoredEvent>> loadStreamAsync(StreamId streamId) async {
    // Get the current version for this stream
    final currentVersion = _streamsBox.get(streamId.value);
    if (currentVersion == null) {
      return [];
    }

    // Load all events for this stream in version order
    final events = <StoredEvent>[];
    for (var version = 0; version <= currentVersion; version++) {
      final key = _eventKey(streamId, version);
      final json = _eventsBox.get(key);
      if (json != null) {
        events.add(_deserializeEvent(json));
      }
    }

    return events;
  }

  @override
  Future<void> appendEventsAsync(StreamId streamId, ExpectedVersion expectedVersion, List<StoredEvent> events) async {
    // Get the current version for this stream (-1 if not exists)
    final currentVersion = _streamsBox.get(streamId.value) ?? -1;

    // Check expected version for optimistic concurrency
    if (expectedVersion.isNoStream) {
      // Expecting a new stream - current version should be -1
      if (currentVersion != -1) {
        throw ConcurrencyException(streamId: streamId, expectedVersion: -1, actualVersion: currentVersion);
      }
    } else {
      // Expecting a specific version
      if (currentVersion != expectedVersion.value) {
        throw ConcurrencyException(streamId: streamId, expectedVersion: expectedVersion.value, actualVersion: currentVersion);
      }
    }

    // Append events with sequential versions
    var nextVersion = currentVersion + 1;

    for (final event in events) {
      final storedEvent = StoredEvent(
        eventId: event.eventId,
        streamId: streamId,
        version: nextVersion,
        eventType: event.eventType,
        data: event.data,
        occurredOn: event.occurredOn,
        metadata: event.metadata,
        globalSequence: _globalSequence++,
      );

      final key = _eventKey(streamId, nextVersion);
      await _eventsBox.put(key, _serializeEvent(storedEvent));
      nextVersion++;
    }

    // Update the stream's current version
    await _streamsBox.put(streamId.value, nextVersion - 1);
  }

  /// Closes the Hive boxes.
  ///
  /// Call this when the store is no longer needed to release resources.
  Future<void> closeAsync() async {
    await _eventsBox.close();
    await _streamsBox.close();
  }

  /// Creates a composite key for an event.
  String _eventKey(StreamId streamId, int version) => '${streamId.value}:$version';

  /// Serializes a stored event to JSON.
  String _serializeEvent(StoredEvent event) {
    return jsonEncode({
      'eventId': event.eventId.value,
      'streamId': event.streamId.value,
      'version': event.version,
      'eventType': event.eventType,
      'data': event.data,
      'occurredOn': event.occurredOn.toIso8601String(),
      'metadata': event.metadata,
      'globalSequence': event.globalSequence,
    });
  }

  /// Deserializes a stored event from JSON.
  StoredEvent _deserializeEvent(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return StoredEvent(
      eventId: EventId(map['eventId'] as String),
      streamId: StreamId(map['streamId'] as String),
      version: map['version'] as int,
      eventType: map['eventType'] as String,
      data: Map<String, dynamic>.from(map['data'] as Map),
      occurredOn: DateTime.parse(map['occurredOn'] as String),
      metadata: Map<String, dynamic>.from(map['metadata'] as Map),
      globalSequence: map['globalSequence'] as int?,
    );
  }
}
