import 'dart:async';
import 'dart:convert';

import 'package:continuum/continuum.dart';
import 'package:sembast/sembast.dart';

/// Sembast-backed implementation of [EventStore].
///
/// Stores events in a Sembast database for local persistence.
/// Events survive app restarts and device reboots.
///
/// The store uses separate Sembast stores for events, stream metadata,
/// and transaction records to efficiently query events by stream ID
/// while maintaining per-stream ordering.
final class SembastEventStore implements AtomicEventStore, ProjectionEventStore {
  /// Store name for persisted events.
  static const String _eventsStoreName = 'events';

  /// Store name for per-stream version metadata.
  static const String _streamsStoreName = 'streams';

  /// Store name for write-ahead transaction log entries.
  static const String _transactionsStoreName = 'transactions';

  /// The Sembast database instance.
  final Database _database;

  /// The Sembast store for events, keyed by composite "streamId:version".
  final StoreRef<String, String> _eventsStore;

  /// The Sembast store for per-stream version metadata, keyed by stream ID.
  final StoreRef<String, int> _streamsStore;

  /// The Sembast store for atomic multi-stream transaction records.
  ///
  /// Sembast supports native transactions, but we persist a write-ahead log
  /// to mirror the same crash-recovery pattern used by HiveEventStore.
  final StoreRef<String, String> _transactionsStore;

  /// Global sequence counter for ordered projections.
  int _globalSequence;

  /// Private constructor - use [openAsync] factory.
  SembastEventStore._({
    required Database database,
    required int globalSequence,
  }) : _database = database,
       _eventsStore = StoreRef<String, String>(_eventsStoreName),
       _streamsStore = StoreRef<String, int>(_streamsStoreName),
       _transactionsStore = StoreRef<String, String>(_transactionsStoreName),
       _globalSequence = globalSequence;

  /// Opens a Sembast event store using the provided [databaseFactory] and [dbPath].
  ///
  /// The caller is responsible for choosing the correct [DatabaseFactory]:
  /// - `databaseFactoryIo` for Dart VM / Flutter mobile / desktop.
  /// - `databaseFactoryWeb` for Flutter Web (from `sembast_web`).
  ///
  /// If the database already exists at [dbPath], it is reopened with existing data.
  static Future<SembastEventStore> openAsync({
    required DatabaseFactory databaseFactory,
    required String dbPath,
  }) async {
    final Database database = await databaseFactory.openDatabase(dbPath);

    final StoreRef<String, String> eventsStore = StoreRef<String, String>(_eventsStoreName);
    final StoreRef<String, int> streamsStore = StoreRef<String, int>(_streamsStoreName);
    final StoreRef<String, String> transactionsStore = StoreRef<String, String>(_transactionsStoreName);

    // Recover any incomplete transactions from a prior crash.
    await _recoverIncompleteTransactionsAsync(
      database: database,
      eventsStore: eventsStore,
      streamsStore: streamsStore,
      transactionsStore: transactionsStore,
    );

    // Determine the current global sequence by scanning all events.
    final int globalSequence = await _findMaxGlobalSequenceAsync(database, eventsStore);

    return SembastEventStore._(
      database: database,
      globalSequence: globalSequence,
    );
  }

  // ---------------------------------------------------------------------------
  // EventStore interface
  // ---------------------------------------------------------------------------

  @override
  Future<List<StoredEvent>> loadStreamAsync(StreamId streamId) async {
    // Look up the current version for this stream.
    final RecordSnapshot<String, int>? streamRecord = await _streamsStore.record(streamId.value).getSnapshot(_database);

    if (streamRecord == null) {
      return <StoredEvent>[];
    }

    final int currentVersion = streamRecord.value;

    // Load all events for this stream in version order.
    final List<StoredEvent> events = <StoredEvent>[];
    for (int version = 0; version <= currentVersion; version++) {
      final String key = _eventKey(streamId, version);
      final String? json = await _eventsStore.record(key).get(_database);
      if (json != null) {
        events.add(_deserializeEvent(json));
      }
    }

    return events;
  }

  @override
  Future<void> appendEventsAsync(
    StreamId streamId,
    ExpectedVersion expectedVersion,
    List<StoredEvent> events,
  ) async {
    // Delegate to the multi-stream path for consistency.
    await appendEventsToStreamsAsync(
      <StreamId, StreamAppendBatch>{
        streamId: StreamAppendBatch(expectedVersion: expectedVersion, events: events),
      },
    );
  }

  // ---------------------------------------------------------------------------
  // AtomicEventStore interface
  // ---------------------------------------------------------------------------

  @override
  Future<void> appendEventsToStreamsAsync(
    Map<StreamId, StreamAppendBatch> batches,
  ) async {
    if (batches.isEmpty) {
      return;
    }

    // Sort entries for deterministic global sequence assignment.
    final List<MapEntry<StreamId, StreamAppendBatch>> entries = batches.entries.toList()
      ..sort((MapEntry<StreamId, StreamAppendBatch> a, MapEntry<StreamId, StreamAppendBatch> b) {
        return a.key.value.compareTo(b.key.value);
      });

    // Build operations list (validate version expectations and assign sequences).
    final List<Map<String, Object?>> operations = <Map<String, Object?>>[];

    // Read current versions for all streams inside a read transaction to get a
    // consistent snapshot, then validate outside of it.
    final Map<String, int> currentVersions = <String, int>{};
    await _database.transaction((Transaction txn) async {
      for (final MapEntry<StreamId, StreamAppendBatch> entry in entries) {
        final int? storedVersion = await _streamsStore.record(entry.key.value).get(txn);
        currentVersions[entry.key.value] = storedVersion ?? -1;
      }
    });

    for (final MapEntry<StreamId, StreamAppendBatch> entry in entries) {
      final StreamId streamId = entry.key;
      final StreamAppendBatch batch = entry.value;

      final int currentVersion = currentVersions[streamId.value]!;
      _throwIfExpectedVersionDoesNotMatch(
        streamId: streamId,
        expectedVersion: batch.expectedVersion,
        currentVersion: currentVersion,
      );

      final List<String> eventKeys = <String>[];
      final List<String> eventJsonValues = <String>[];

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
          domainEvent: event.domainEvent,
        );

        eventKeys.add(_eventKey(streamId, nextVersion));
        eventJsonValues.add(_serializeEvent(storedEvent));
        nextVersion++;
      }

      operations.add(<String, Object?>{
        'streamId': streamId.value,
        'oldVersion': currentVersion,
        'newVersion': nextVersion - 1,
        'eventKeys': eventKeys,
        'eventJson': eventJsonValues,
      });
    }

    // Persist a write-ahead log record, then apply all writes atomically.
    final String transactionKey = DateTime.now().microsecondsSinceEpoch.toString();

    await _transactionsStore
        .record(transactionKey)
        .put(
          _database,
          jsonEncode(<String, Object?>{
            'state': 'committing',
            'operations': operations,
          }),
        );

    try {
      // Apply all event and stream-version writes in a single Sembast transaction.
      await _database.transaction((Transaction txn) async {
        for (final Map<String, Object?> operation in operations) {
          final String streamIdValue = operation['streamId'] as String;
          final int newVersion = operation['newVersion'] as int;
          final List<String> eventKeys = _decodeStringList(operation['eventKeys']);
          final List<String> eventJsonValues = _decodeStringList(operation['eventJson']);

          for (int index = 0; index < eventKeys.length; index++) {
            await _eventsStore.record(eventKeys[index]).put(txn, eventJsonValues[index]);
          }

          await _streamsStore.record(streamIdValue).put(txn, newVersion);
        }
      });

      // Commit succeeded — remove the write-ahead record.
      await _transactionsStore.record(transactionKey).delete(_database);
    } catch (error, stackTrace) {
      // Mark as aborting so recovery always rolls back.
      await _transactionsStore
          .record(transactionKey)
          .put(
            _database,
            jsonEncode(<String, Object?>{
              'state': 'aborting',
              'operations': operations,
            }),
          );

      await _rollbackTransactionAsync(operations);
      await _transactionsStore.record(transactionKey).delete(_database);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  // ---------------------------------------------------------------------------
  // ProjectionEventStore interface
  // ---------------------------------------------------------------------------

  @override
  Future<List<StoredEvent>> loadEventsFromPositionAsync(
    int fromGlobalSequence,
    int limit,
  ) async {
    // Collect all events from the store.
    final List<RecordSnapshot<String, String>> records = await _eventsStore.find(_database);

    final List<StoredEvent> matchingEvents = <StoredEvent>[];
    for (final RecordSnapshot<String, String> record in records) {
      final StoredEvent event = _deserializeEvent(record.value);
      if (event.globalSequence != null && event.globalSequence! >= fromGlobalSequence) {
        matchingEvents.add(event);
      }
    }

    // Sort by global sequence.
    matchingEvents.sort(
      (StoredEvent a, StoredEvent b) => (a.globalSequence ?? 0).compareTo(b.globalSequence ?? 0),
    );

    // Return up to [limit] events.
    return matchingEvents.take(limit).toList();
  }

  @override
  Future<int?> getMaxGlobalSequenceAsync() async {
    // The _globalSequence counter is one ahead of the max, so subtract 1.
    // If _globalSequence is 0, no events have been stored.
    if (_globalSequence == 0) {
      return null;
    }
    return _globalSequence - 1;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Closes the underlying Sembast database.
  ///
  /// Call this when the store is no longer needed to release resources.
  Future<void> closeAsync() async {
    await _database.close();
  }

  // ---------------------------------------------------------------------------
  // Crash recovery helpers
  // ---------------------------------------------------------------------------

  /// Recovers incomplete atomic multi-stream appends after a crash.
  ///
  /// Replays or rolls back based on the persisted transaction record state.
  static Future<void> _recoverIncompleteTransactionsAsync({
    required Database database,
    required StoreRef<String, String> eventsStore,
    required StoreRef<String, int> streamsStore,
    required StoreRef<String, String> transactionsStore,
  }) async {
    final List<RecordSnapshot<String, String>> snapshots = await transactionsStore.find(database);

    for (final RecordSnapshot<String, String> snapshot in snapshots) {
      final String transactionKey = snapshot.key;
      final Map<String, Object?> decoded = _decodeJsonObject(snapshot.value);
      final String state = decoded['state'] as String? ?? 'committing';
      final List<Object?> operations = decoded['operations'] as List<Object?>? ?? const <Object?>[];

      if (state == 'aborting') {
        await _rollbackTransactionStaticAsync(
          database: database,
          eventsStore: eventsStore,
          streamsStore: streamsStore,
          operations: operations,
        );
        await transactionsStore.record(transactionKey).delete(database);
        continue;
      }

      // Check whether any writes from this transaction have been applied.
      final bool hasAnyApplied = await _transactionHasAnyAppliedStateAsync(
        database: database,
        eventsStore: eventsStore,
        streamsStore: streamsStore,
        operations: operations,
      );

      if (hasAnyApplied) {
        await _replayTransactionAsync(
          database: database,
          eventsStore: eventsStore,
          streamsStore: streamsStore,
          operations: operations,
        );
      } else {
        await _rollbackTransactionStaticAsync(
          database: database,
          eventsStore: eventsStore,
          streamsStore: streamsStore,
          operations: operations,
        );
      }

      await transactionsStore.record(transactionKey).delete(database);
    }
  }

  /// Returns true when persisted state indicates partial application.
  static Future<bool> _transactionHasAnyAppliedStateAsync({
    required Database database,
    required StoreRef<String, String> eventsStore,
    required StoreRef<String, int> streamsStore,
    required List<Object?> operations,
  }) async {
    for (final Object? operationObject in operations) {
      final Map<String, Object?> operation = (operationObject as Map).cast<String, Object?>();
      final String streamIdValue = operation['streamId'] as String;
      final int newVersion = operation['newVersion'] as int;

      final int? persistedStreamVersion = await streamsStore.record(streamIdValue).get(database);
      if (persistedStreamVersion == newVersion) {
        return true;
      }

      final List<String> eventKeys = _decodeStringList(operation['eventKeys']);
      for (final String key in eventKeys) {
        final String? existingEvent = await eventsStore.record(key).get(database);
        if (existingEvent != null) {
          return true;
        }
      }
    }

    return false;
  }

  /// Replays a committing transaction to completion.
  static Future<void> _replayTransactionAsync({
    required Database database,
    required StoreRef<String, String> eventsStore,
    required StoreRef<String, int> streamsStore,
    required List<Object?> operations,
  }) async {
    await database.transaction((Transaction txn) async {
      for (final Object? operationObject in operations) {
        final Map<String, Object?> operation = (operationObject as Map).cast<String, Object?>();
        final String streamIdValue = operation['streamId'] as String;
        final int newVersion = operation['newVersion'] as int;
        final List<String> eventKeys = _decodeStringList(operation['eventKeys']);
        final List<String> eventJsonValues = _decodeStringList(operation['eventJson']);

        for (int index = 0; index < eventKeys.length; index++) {
          final String key = eventKeys[index];
          final String? existing = await eventsStore.record(key).get(txn);
          // Only write events that were not already applied.
          if (existing == null) {
            await eventsStore.record(key).put(txn, eventJsonValues[index]);
          }
        }

        await streamsStore.record(streamIdValue).put(txn, newVersion);
      }
    });
  }

  /// Rolls back an aborted transaction (instance method variant).
  Future<void> _rollbackTransactionAsync(List<Map<String, Object?>> operations) async {
    await _rollbackTransactionStaticAsync(
      database: _database,
      eventsStore: _eventsStore,
      streamsStore: _streamsStore,
      operations: operations.cast<Object?>(),
    );
  }

  /// Rolls back an aborted transaction (static variant for recovery).
  static Future<void> _rollbackTransactionStaticAsync({
    required Database database,
    required StoreRef<String, String> eventsStore,
    required StoreRef<String, int> streamsStore,
    required List<Object?> operations,
  }) async {
    await database.transaction((Transaction txn) async {
      for (final Object? operationObject in operations) {
        final Map<String, Object?> operation = (operationObject as Map).cast<String, Object?>();
        final String streamIdValue = operation['streamId'] as String;
        final int oldVersion = operation['oldVersion'] as int;
        final List<String> eventKeys = _decodeStringList(operation['eventKeys']);

        for (final String key in eventKeys) {
          await eventsStore.record(key).delete(txn);
        }

        if (oldVersion == -1) {
          await streamsStore.record(streamIdValue).delete(txn);
        } else {
          await streamsStore.record(streamIdValue).put(txn, oldVersion);
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Global sequence helpers
  // ---------------------------------------------------------------------------

  /// Finds the maximum global sequence in the events store.
  ///
  /// Returns the next sequence value to assign (max + 1), or 0 when empty.
  static Future<int> _findMaxGlobalSequenceAsync(
    Database database,
    StoreRef<String, String> eventsStore,
  ) async {
    final List<RecordSnapshot<String, String>> records = await eventsStore.find(database);

    if (records.isEmpty) {
      return 0;
    }

    var maxSequence = 0;
    for (final RecordSnapshot<String, String> record in records) {
      final Map<String, Object?> decoded = jsonDecode(record.value) as Map<String, Object?>;
      final int sequence = decoded['globalSequence'] as int? ?? 0;
      if (sequence > maxSequence) {
        maxSequence = sequence;
      }
    }

    // Return one past the max so the next event gets the correct sequence.
    return maxSequence + 1;
  }

  // ---------------------------------------------------------------------------
  // Concurrency validation
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // Serialization helpers
  // ---------------------------------------------------------------------------

  /// Creates a composite key for an event.
  static String _eventKey(StreamId streamId, int version) => '${streamId.value}:$version';

  /// Serializes a stored event to JSON.
  static String _serializeEvent(StoredEvent event) {
    return jsonEncode(<String, Object?>{
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
  static StoredEvent _deserializeEvent(String json) {
    final Map<String, Object?> map = jsonDecode(json) as Map<String, Object?>;
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
}
