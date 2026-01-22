import 'package:continuum/continuum.dart';
import 'package:test/test.dart';

void main() {
  group('StoredEvent immutability', () {
    test('BUG: StoredEvent should snapshot data Map (defensive copy)', () {
      final mutableData = <String, dynamic>{'a': 1};

      final stored = StoredEvent(
        eventId: const EventId('e-1'),
        streamId: const StreamId('s-1'),
        version: 0,
        eventType: 'x',
        data: mutableData,
        occurredOn: DateTime.utc(2025, 1, 1),
        metadata: const {},
      );

      mutableData['a'] = 2;

      expect(stored.data['a'], equals(1));
    });

    test('BUG: StoredEvent.fromContinuumEvent should snapshot metadata (defensive copy)', () {
      final mutableMetadata = <String, dynamic>{'correlationId': 'corr-1'};

      final event = _TestEvent(
        eventId: const EventId('e-1'),
        metadata: mutableMetadata,
      );

      final stored = StoredEvent.fromContinuumEvent(
        continuumEvent: event,
        streamId: const StreamId('s-1'),
        version: 0,
        eventType: 'x',
        data: const {},
      );

      mutableMetadata['correlationId'] = 'corr-2';

      expect(stored.metadata['correlationId'], equals('corr-1'));
    });
  });
}

final class _TestEvent implements ContinuumEvent {
  _TestEvent({
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;
}
