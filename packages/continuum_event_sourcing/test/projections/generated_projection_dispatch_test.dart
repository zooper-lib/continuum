import 'package:continuum/continuum.dart';
import 'package:test/test.dart';

void main() {
  group('Generated projection dispatch (domainEvent)', () {
    test('apply dispatches based on Operation runtime type', () {
      final projection = _GeneratedStyleProjection();

      final eventA = _TestEventA(eventId: EventId.fromUlid());

      // Act: apply directly with the Operation (ContinuumEvent).
      final resultA = projection.apply(0, eventA);
      expect(resultA, equals(1));

      final eventB = _TestEventB(eventId: EventId.fromUlid());

      final resultB = projection.apply(resultA, eventB);
      expect(resultB, equals(11));
    });

    test('apply throws UnsupportedOperationException for unsupported Operation type', () {
      // Arrange: A projection that supports only A and B.
      final projection = _GeneratedStyleProjection();

      final eventC = _TestEventC(eventId: EventId.fromUlid());

      // Act/Assert: Unsupported operations must fail fast.
      // This matters because applying the wrong operation type is a programming error.
      expect(
        () => projection.apply(0, eventC),
        throwsA(isA<UnsupportedProjectionOperationException>()),
      );
    });
  });
}

final class _GeneratedStyleProjection extends SingleStreamProjection<int> with _$_GeneratedStyleProjectionHandlers {
  @override
  StreamId extractKey(Operation operation) => const StreamId('default');

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

  int apply(int current, Operation operation) {
    return switch (operation) {
      _TestEventA() => applyTestEventA(current, operation),
      _TestEventB() => applyTestEventB(current, operation),
      _ => throw UnsupportedProjectionOperationException(
        operationType: operation.runtimeType,
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
