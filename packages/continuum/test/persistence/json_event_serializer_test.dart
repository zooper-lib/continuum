import 'package:continuum/continuum.dart';
import 'package:test/test.dart';

final class ImmutableMapEvent implements ContinuumEvent {
  ImmutableMapEvent({
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

  factory ImmutableMapEvent.fromJson(Map<String, dynamic> json) {
    return ImmutableMapEvent(
      eventId: EventId(json['eventId'] as String),
      occurredOn: DateTime.parse(json['occurredOn'] as String),
      metadata: (json['metadata'] as Map<String, dynamic>),
    );
  }
}

void main() {
  group('JsonEventSerializer', () {
    test('deserialize injects stored metadata into fromJson payload', () {
      final registry = EventSerializerRegistry({
        ImmutableMapEvent: EventSerializerEntry(
          eventType: 'immutable',
          toJson: (_) => {},
          fromJson: (json) {
            final metadata = (json['metadata'] as Map?)?.cast<String, dynamic>();
            expect(metadata, isNotNull);
            expect(metadata!['correlationId'], equals('corr-1'));
            return ImmutableMapEvent.fromJson(json);
          },
        ),
      });

      final serializer = JsonEventSerializer(registry: registry);

      final event = serializer.deserialize(
        eventType: 'immutable',
        data: {
          'eventId': 'e-1',
          'occurredOn': DateTime.utc(2025, 1, 1).toIso8601String(),
        },
        storedMetadata: {'correlationId': 'corr-1'},
      );

      expect(event, isA<ImmutableMapEvent>());
      expect(event.metadata['correlationId'], equals('corr-1'));
    });

    test(
      'BUG: serialize should not require a mutable toJson Map',
      () {
        final registry = EventSerializerRegistry({
          ImmutableMapEvent: EventSerializerEntry(
            eventType: 'immutable',
            toJson: (_) => const <String, dynamic>{},
            fromJson: ImmutableMapEvent.fromJson,
          ),
        });

        final serializer = JsonEventSerializer(registry: registry);

        final serialized = serializer.serialize(
          ImmutableMapEvent(eventId: const EventId('e-1')),
        );

        expect(serialized.data['eventId'], equals('e-1'));
        expect(serialized.data['occurredOn'], isA<String>());
      },
    );
  });
}
