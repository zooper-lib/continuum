import 'package:continuum/continuum.dart';
import 'package:test/test.dart';
import 'package:zooper_flutter_core/zooper_flutter_core.dart';

void main() {
  group('Generated projection dispatch (domainEvent)', () {
    test('apply dispatches based on StoredEvent.domainEvent runtime type', () {
      final projection = _GeneratedStyleProjection();

      final eventA = _TestEventA(eventId: EventId.fromUlid());
      final storedA = StoredEvent.fromContinuumEvent(
        continuumEvent: eventA,
        streamId: const StreamId('s1'),
        version: 0,
        eventType: 'test.a',
        data: const {'a': 1},
      );

      final resultA = projection.apply(0, storedA);
      expect(resultA, equals(1));

      final eventB = _TestEventB(eventId: EventId.fromUlid());
      final storedB = StoredEvent.fromContinuumEvent(
        continuumEvent: eventB,
        streamId: const StreamId('s1'),
        version: 1,
        eventType: 'test.b',
        data: const {'b': 1},
      );

      final resultB = projection.apply(resultA, storedB);
      expect(resultB, equals(11));
    });

    test('apply throws StateError when StoredEvent.domainEvent is null', () {
      final projection = _GeneratedStyleProjection();

      final stored = StoredEvent(
        eventId: EventId.fromUlid(),
        streamId: const StreamId('s1'),
        version: 0,
        eventType: 'test.a',
        data: const {'a': 1},
        occurredOn: DateTime.now(),
        metadata: const {},
        domainEvent: null,
      );

      expect(
        () => projection.apply(0, stored),
        throwsA(isA<StateError>()),
      );
    });

    test('apply throws UnsupportedEventException for unsupported domainEvent type', () {
      // Arrange: A projection that supports only A and B.
      final projection = _GeneratedStyleProjection();

      final eventC = _TestEventC(eventId: EventId.fromUlid());
      final storedC = StoredEvent.fromContinuumEvent(
        continuumEvent: eventC,
        streamId: const StreamId('s1'),
        version: 0,
        eventType: 'test.c',
        data: const {'c': 1},
      );

      // Act/Assert: Unsupported events must fail fast.
      // This matters because applying the wrong event type is a programming error.
      expect(
        () => projection.apply(0, storedC),
        throwsA(isA<UnsupportedEventException>()),
      );
    });
  });
}

final class _GeneratedStyleProjection extends SingleStreamProjection<int> with _$_GeneratedStyleProjectionHandlers {
  @override
  int createInitial(StreamId streamId) => 0;

  @override
  int applyTestEventA(int current, _TestEventA event) => current + 1;

  @override
  int applyTestEventB(int current, _TestEventB event) => current + 10;
}

// A minimal stand-in for generated code.
mixin _$_GeneratedStyleProjectionHandlers {
  Set<Type> get handledEventTypes => const {_TestEventA, _TestEventB};

  String get projectionName => 'generated-style';

  int apply(int current, StoredEvent event) {
    final domainEvent = event.domainEvent;
    if (domainEvent == null) {
      throw StateError(
        'StoredEvent.domainEvent is null. '
        'Projections require deserialized domain events.',
      );
    }

    return switch (domainEvent) {
      _TestEventA() => applyTestEventA(current, domainEvent),
      _TestEventB() => applyTestEventB(current, domainEvent),
      _ => throw UnsupportedEventException(
        eventType: domainEvent.runtimeType,
        projectionType: _GeneratedStyleProjection,
      ),
    };
  }

  int applyTestEventA(int current, _TestEventA event);

  int applyTestEventB(int current, _TestEventB event);
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

final class _TestEventB implements ContinuumEvent {
  _TestEventB({
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

final class _TestEventC implements ContinuumEvent {
  _TestEventC({
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
