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

    test('BUG: StoredEvent.fromDomainEvent should snapshot metadata (defensive copy)', () {
      final mutableMetadata = <String, dynamic>{'correlationId': 'corr-1'};

      final event = _TestEvent(
        eventId: const EventId('e-1'),
        metadata: mutableMetadata,
      );

      final stored = StoredEvent.fromDomainEvent(
        domainEvent: event,
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

final class _TestEvent extends DomainEvent {
  _TestEvent({
    required super.eventId,
    super.metadata,
  });
}
