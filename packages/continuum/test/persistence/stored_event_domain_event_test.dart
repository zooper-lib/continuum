import 'package:continuum/continuum.dart';
import 'package:test/test.dart';
import 'package:zooper_flutter_core/zooper_flutter_core.dart';

void main() {
  group('StoredEvent.domainEvent', () {
    test('fromContinuumEvent populates domainEvent', () {
      final domainEvent = _TestEventA(eventId: EventId.fromUlid());

      final stored = StoredEvent.fromContinuumEvent(
        continuumEvent: domainEvent,
        streamId: const StreamId('s1'),
        version: 0,
        eventType: 'test.a',
        data: const {'k': 'v'},
        globalSequence: 42,
      );

      expect(stored.domainEvent, same(domainEvent));
      expect(stored.data, containsPair('k', 'v'));
      expect(stored.eventType, equals('test.a'));
      expect(stored.globalSequence, equals(42));
    });

    test('constructor accepts explicit domainEvent', () {
      final domainEvent = _TestEventA(eventId: EventId.fromUlid());

      final stored = StoredEvent(
        eventId: domainEvent.id,
        streamId: const StreamId('s1'),
        version: 0,
        eventType: 'test.a',
        data: const {'k': 'v'},
        occurredOn: domainEvent.occurredOn,
        metadata: domainEvent.metadata,
        domainEvent: domainEvent,
      );

      expect(stored.domainEvent, same(domainEvent));
    });
  });
}

final class _TestEventA implements ContinuumEvent {
  _TestEventA({
    required EventId eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId,
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;
}
