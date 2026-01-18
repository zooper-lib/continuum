import 'dart:async';
import 'dart:convert';

import 'package:continuum/continuum.dart';
import 'package:hive/hive.dart';
import 'package:zooper_flutter_core/zooper_flutter_core.dart';

/// Hive-backed implementation of [EventStore].
///
/// Stores events in a Hive box for local persistence.
/// Events survive app restarts and device reboots.
///
/// The store uses a composite key structure to efficiently query events
/// by stream ID while maintaining per-stream ordering.
final class HiveEventStore implements AtomicEventStore, ProjectionEventStore {
  /// Box suffix used for transaction-log metadata.
  static const String _transactionsBoxSuffix = '_transactions';

  /// The Hive box for storing events.
  final Box<String> _eventsBox;

  /// The Hive box for storing stream metadata (current version).
  final Box<int> _streamsBox;

  /// The Hive box for storing atomic multi-stream transaction records.
  ///
  /// Hive does not support cross-box transactions, so we use a write-ahead log
  /// to provide all-or-nothing multi-stream appends across restarts.
  final Box<String> _transactionsBox;

  /// Global sequence counter for ordered projections.
  int _globalSequence;

  /// Serializes operations to prevent observing partially written state.
  Future<void> _exclusiveOperation;

  /// Private constructor - use [openAsync] factory.
  HiveEventStore._({
    required Box<String> eventsBox,
    required Box<int> streamsBox,
    required Box<String> transactionsBox,
    required int globalSequence,
  }) : _eventsBox = eventsBox,
       _streamsBox = streamsBox,
       _transactionsBox = transactionsBox,
       _globalSequence = globalSequence,
       _exclusiveOperation = Future<void>.value();

  /// Opens a Hive event store with the given box names.
  ///
  /// If the boxes already exist, they are reopened with existing data.
  /// The [boxName] parameter is used as a prefix for the internal boxes.
  static Future<HiveEventStore> openAsync({required String boxName}) async {
    final eventsBox = await Hive.openBox<String>('${boxName}_events');
    final streamsBox = await Hive.openBox<int>('${boxName}_streams');
    final transactionsBox = await Hive.openBox<String>('$boxName$_transactionsBoxSuffix');

    await _recoverIncompleteTransactionsAsync(
      eventsBox: eventsBox,
      streamsBox: streamsBox,
      transactionsBox: transactionsBox,
    );

    // Determine the current global sequence by finding the max
    final globalSequence = eventsBox.isEmpty ? 0 : _findMaxGlobalSequence(eventsBox);

    return HiveEventStore._(
      eventsBox: eventsBox,
      streamsBox: streamsBox,
      transactionsBox: transactionsBox,
      globalSequence: globalSequence,
    );
  }

  /// Recovers incomplete atomic multi-stream appends.
  ///
  /// The implementation replays or rolls back based on the persisted
  /// transaction record.
  static Future<void> _recoverIncompleteTransactionsAsync({
    required Box<String> eventsBox,
    required Box<int> streamsBox,
    required Box<String> transactionsBox,
  }) async {
    for (final dynamic key in transactionsBox.keys.toList()) {
      final String transactionKey = key as String;
      final String? transactionJson = transactionsBox.get(transactionKey);
      if (transactionJson == null) {
        continue;
      }

      final Map<String, Object?> decoded = _decodeJsonObject(transactionJson);
      final String state = decoded['state'] as String? ?? 'committing';
      final List<Object?> operations = decoded['operations'] as List<Object?>? ?? const <Object?>[];

      if (state == 'aborting') {
        await _rollbackTransactionAsync(eventsBox: eventsBox, streamsBox: streamsBox, operations: operations);
        await transactionsBox.delete(transactionKey);
        continue;
      }

      final bool hasAnyApplied = _transactionHasAnyAppliedState(
        eventsBox: eventsBox,
        streamsBox: streamsBox,
        operations: operations,
      );

      if (hasAnyApplied) {
        await _replayTransactionAsync(eventsBox: eventsBox, streamsBox: streamsBox, operations: operations);
      } else {
        await _rollbackTransactionAsync(eventsBox: eventsBox, streamsBox: streamsBox, operations: operations);
      }

      await transactionsBox.delete(transactionKey);
    }
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
    return _runExclusiveAsync<List<StoredEvent>>(() async {
      // Get the current version for this stream
      final int? currentVersion = _streamsBox.get(streamId.value);
      if (currentVersion == null) {
        return <StoredEvent>[];
      }

      // Load all events for this stream in version order
      final List<StoredEvent> events = <StoredEvent>[];
      for (int version = 0; version <= currentVersion; version++) {
        final String key = _eventKey(streamId, version);
        final String? json = _eventsBox.get(key);
        if (json != null) {
          events.add(_deserializeEvent(json));
        }
      }

      return events;
    });
  }

  @override
  Future<void> appendEventsAsync(StreamId streamId, ExpectedVersion expectedVersion, List<StoredEvent> events) async {
    await appendEventsToStreamsAsync(
      <StreamId, StreamAppendBatch>{
        streamId: StreamAppendBatch(expectedVersion: expectedVersion, events: events),
      },
    );
  }

  @override
  Future<void> appendEventsToStreamsAsync(
    Map<StreamId, StreamAppendBatch> batches,
  ) async {
    if (batches.isEmpty) {
      return;
    }

    await _runExclusiveAsync<void>(() async {
      // Ensure deterministic global sequence assignment.
      final List<MapEntry<StreamId, StreamAppendBatch>> entries = batches.entries.toList()
        ..sort((MapEntry<StreamId, StreamAppendBatch> a, MapEntry<StreamId, StreamAppendBatch> b) {
          return a.key.value.compareTo(b.key.value);
        });

      final List<Map<String, Object?>> operations = <Map<String, Object?>>[];

      for (final MapEntry<StreamId, StreamAppendBatch> entry in entries) {
        final StreamId streamId = entry.key;
        final StreamAppendBatch batch = entry.value;

        final int currentVersion = _streamsBox.get(streamId.value) ?? -1;
        _throwIfExpectedVersionDoesNotMatch(
          streamId: streamId,
          expectedVersion: batch.expectedVersion,
          currentVersion: currentVersion,
        );

        final List<String> eventKeys = <String>[];
        final List<String> eventJson = <String>[];

        int nextVersion = currentVersion + 1;
        for (final StoredEvent event in batch.events) {
          final StoredEvent storedEvent = StoredEvent(
            eventId: event.eventId,
            streamId: streamId,
            version: nextVersion,
            eventType: event.eventType,
            data: event.data,
            occurredOn: event.occurredOn,
            metadata: event.metadata,
            globalSequence: _globalSequence++,
          );

          eventKeys.add(_eventKey(streamId, nextVersion));
          eventJson.add(_serializeEvent(storedEvent));
          nextVersion++;
        }

        operations.add(<String, Object?>{
          'streamId': streamId.value,
          'oldVersion': currentVersion,
          'newVersion': nextVersion - 1,
          'eventKeys': eventKeys,
          'eventJson': eventJson,
        });
      }

      final String transactionKey = DateTime.now().microsecondsSinceEpoch.toString();
      await _transactionsBox.put(
        transactionKey,
        jsonEncode(<String, Object?>{
          'state': 'committing',
          'operations': operations,
        }),
      );

      try {
        final Map<String, String> eventWrites = <String, String>{};
        final Map<String, int> streamVersionWrites = <String, int>{};

        for (final Map<String, Object?> operation in operations) {
          final String streamIdValue = operation['streamId'] as String;
          final int newVersion = operation['newVersion'] as int;
          final List<String> eventKeys = _decodeStringList(operation['eventKeys']);
          final List<String> eventJson = _decodeStringList(operation['eventJson']);

          for (int index = 0; index < eventKeys.length; index++) {
            eventWrites[eventKeys[index]] = eventJson[index];
          }
          streamVersionWrites[streamIdValue] = newVersion;
        }

        await _eventsBox.putAll(eventWrites);
        await _streamsBox.putAll(streamVersionWrites);
        await _transactionsBox.delete(transactionKey);
      } catch (error, stackTrace) {
        // Mark the record as aborting so recovery will always roll back.
        await _transactionsBox.put(
          transactionKey,
          jsonEncode(<String, Object?>{
            'state': 'aborting',
            'operations': operations,
          }),
        );

        await _rollbackTransactionAsync(eventsBox: _eventsBox, streamsBox: _streamsBox, operations: operations);
        await _transactionsBox.delete(transactionKey);
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
  }

  /// Closes the Hive boxes.
  ///
  /// Call this when the store is no longer needed to release resources.
  Future<void> closeAsync() async {
    await _runExclusiveAsync<void>(() async {
      await _eventsBox.close();
      await _streamsBox.close();
      await _transactionsBox.close();
    });
  }

  /// Creates a composite key for an event.
  String _eventKey(StreamId streamId, int version) => '${streamId.value}:$version';

  /// Runs [action] in a single-operation queue.
  ///
  /// This keeps reads and writes from interleaving and ensures callers do not
  /// observe partially applied multi-step persistence.
  Future<T> _runExclusiveAsync<T>(Future<T> Function() action) {
    final Completer<T> completer = Completer<T>();

    _exclusiveOperation = _exclusiveOperation.then((_) async {
      try {
        final T result = await action();
        completer.complete(result);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    return completer.future;
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

  /// Returns true when persisted state indicates partial application.
  static bool _transactionHasAnyAppliedState({
    required Box<String> eventsBox,
    required Box<int> streamsBox,
    required List<Object?> operations,
  }) {
    for (final Object? operationObject in operations) {
      final Map<String, Object?> operation = (operationObject as Map).cast<String, Object?>();
      final String streamIdValue = operation['streamId'] as String;
      final int newVersion = operation['newVersion'] as int;

      final int? persistedStreamVersion = streamsBox.get(streamIdValue);
      if (persistedStreamVersion == newVersion) {
        return true;
      }

      final List<String> eventKeys = _decodeStringList(operation['eventKeys']);
      for (final String key in eventKeys) {
        if (eventsBox.containsKey(key)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Replays a committing transaction to completion.
  static Future<void> _replayTransactionAsync({
    required Box<String> eventsBox,
    required Box<int> streamsBox,
    required List<Object?> operations,
  }) async {
    final Map<String, String> eventWrites = <String, String>{};
    final Map<String, int> streamVersionWrites = <String, int>{};

    for (final Object? operationObject in operations) {
      final Map<String, Object?> operation = (operationObject as Map).cast<String, Object?>();
      final String streamIdValue = operation['streamId'] as String;
      final int newVersion = operation['newVersion'] as int;
      final List<String> eventKeys = _decodeStringList(operation['eventKeys']);
      final List<String> eventJson = _decodeStringList(operation['eventJson']);

      for (int index = 0; index < eventKeys.length; index++) {
        final String key = eventKeys[index];
        if (!eventsBox.containsKey(key)) {
          eventWrites[key] = eventJson[index];
        }
      }

      streamVersionWrites[streamIdValue] = newVersion;
    }

    if (eventWrites.isNotEmpty) {
      await eventsBox.putAll(eventWrites);
    }
    await streamsBox.putAll(streamVersionWrites);
  }

  /// Rolls back an aborted transaction.
  static Future<void> _rollbackTransactionAsync({
    required Box<String> eventsBox,
    required Box<int> streamsBox,
    required List<Object?> operations,
  }) async {
    final List<String> eventDeletes = <String>[];
    final Map<String, int?> streamVersionWrites = <String, int?>{};

    for (final Object? operationObject in operations) {
      final Map<String, Object?> operation = (operationObject as Map).cast<String, Object?>();
      final String streamIdValue = operation['streamId'] as String;
      final int oldVersion = operation['oldVersion'] as int;
      final List<String> eventKeys = _decodeStringList(operation['eventKeys']);
      eventDeletes.addAll(eventKeys);

      streamVersionWrites[streamIdValue] = oldVersion == -1 ? null : oldVersion;
    }

    if (eventDeletes.isNotEmpty) {
      await eventsBox.deleteAll(eventDeletes);
    }

    for (final MapEntry<String, int?> entry in streamVersionWrites.entries) {
      if (entry.value == null) {
        await streamsBox.delete(entry.key);
      } else {
        await streamsBox.put(entry.key, entry.value!);
      }
    }
  }

  /// Decodes JSON into a typed object map.
  static Map<String, Object?> _decodeJsonObject(String json) {
    final Object? decoded = jsonDecode(json);
    return (decoded as Map).cast<String, Object?>();
  }

  /// Decodes a value that must be a list of strings.
  static List<String> _decodeStringList(Object? value) {
    final List<Object?> list = (value as List).cast<Object?>();
    return list.map((Object? item) => item as String).toList();
  }

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

  @override
  Future<List<StoredEvent>> loadEventsFromPositionAsync(
    int fromGlobalSequence,
    int limit,
  ) async {
    return _runExclusiveAsync<List<StoredEvent>>(() async {
      // Collect all events from the box.
      final List<StoredEvent> allEvents = <StoredEvent>[];

      for (final String json in _eventsBox.values) {
        final event = _deserializeEvent(json);
        if (event.globalSequence != null && event.globalSequence! >= fromGlobalSequence) {
          allEvents.add(event);
        }
      }

      // Sort by global sequence.
      allEvents.sort(
        (a, b) => (a.globalSequence ?? 0).compareTo(b.globalSequence ?? 0),
      );

      // Return up to limit events.
      return allEvents.take(limit).toList();
    });
  }

  @override
  Future<int?> getMaxGlobalSequenceAsync() async {
    return _runExclusiveAsync<int?>(() async {
      // The _globalSequence counter is one ahead of the max, so subtract 1.
      // If _globalSequence is 0, no events have been stored.
      if (_globalSequence == 0) {
        return null;
      }
      return _globalSequence - 1;
    });
  }
}
