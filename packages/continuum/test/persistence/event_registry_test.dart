import 'package:continuum/continuum.dart';
import 'package:test/test.dart';

/// Test event for registry testing.
final class TestRegistryEvent extends ContinuumEvent {
  final String value;

  TestRegistryEvent({
    required super.eventId,
    required this.value,
    super.occurredOn,
    super.metadata,
  });

  /// Factory for deserialization.
  factory TestRegistryEvent.fromJson(Map<String, dynamic> json) {
    return TestRegistryEvent(
      eventId: EventId(json['eventId'] as String),
      value: json['value'] as String,
    );
  }
}

/// Another test event for testing multiple registrations.
final class AnotherTestEvent extends ContinuumEvent {
  final int number;

  AnotherTestEvent({
    required super.eventId,
    required this.number,
    super.occurredOn,
    super.metadata,
  });

  factory AnotherTestEvent.fromJson(Map<String, dynamic> json) {
    return AnotherTestEvent(
      eventId: EventId(json['eventId'] as String),
      number: json['number'] as int,
    );
  }
}

void main() {
  group('EventRegistry', () {
    group('fromStored', () {
      test('should deserialize known event type', () {
        // Arrange
        final registry = const EventRegistry({
          'test.event': TestRegistryEvent.fromJson,
        });
        final data = {'eventId': 'evt_123', 'value': 'hello'};

        // Act
        final event = registry.fromStored('test.event', data);

        // Assert - should return the correct event type with data
        expect(event, isA<TestRegistryEvent>());
        expect((event as TestRegistryEvent).value, equals('hello'));
      });

      test('should throw UnknownEventTypeException for unknown type', () {
        // Arrange
        final registry = const EventRegistry({
          'test.event': TestRegistryEvent.fromJson,
        });
        final data = {'eventId': 'evt_123', 'value': 'hello'};

        // Act & Assert
        expect(
          () => registry.fromStored('unknown.type', data),
          throwsA(isA<UnknownEventTypeException>()),
        );
      });
    });

    group('containsType', () {
      test('should return true for registered type', () {
        // Arrange
        final registry = const EventRegistry({
          'test.event': TestRegistryEvent.fromJson,
        });

        // Act & Assert
        expect(registry.containsType('test.event'), isTrue);
      });

      test('should return false for unregistered type', () {
        // Arrange
        final registry = const EventRegistry({
          'test.event': TestRegistryEvent.fromJson,
        });

        // Act & Assert
        expect(registry.containsType('other.event'), isFalse);
      });
    });

    group('registeredTypes', () {
      test('should return all registered types', () {
        // Arrange
        final registry = const EventRegistry({
          'type.one': TestRegistryEvent.fromJson,
          'type.two': AnotherTestEvent.fromJson,
        });

        // Act
        final types = registry.registeredTypes.toList();

        // Assert
        expect(types, containsAll(['type.one', 'type.two']));
        expect(types.length, equals(2));
      });

      test('should return empty for empty registry', () {
        // Arrange
        const registry = EventRegistry.empty();

        // Act & Assert
        expect(registry.registeredTypes, isEmpty);
      });
    });

    group('merge', () {
      test('should combine registries', () {
        // Arrange
        final registry1 = const EventRegistry({
          'type.one': TestRegistryEvent.fromJson,
        });
        final registry2 = const EventRegistry({
          'type.two': AnotherTestEvent.fromJson,
        });

        // Act
        final merged = registry1.merge(registry2);

        // Assert - should contain both types
        expect(merged.containsType('type.one'), isTrue);
        expect(merged.containsType('type.two'), isTrue);
      });

      test('should prefer second registry on conflict', () {
        // Arrange
        final registry1 = const EventRegistry({
          'conflicting.type': TestRegistryEvent.fromJson,
        });
        final registry2 = const EventRegistry({
          'conflicting.type': AnotherTestEvent.fromJson,
        });

        // Act
        final merged = registry1.merge(registry2);
        final result = merged.fromStored('conflicting.type', {
          'eventId': 'evt_1',
          'number': 42,
        });

        // Assert - should use the second registry's factory
        expect(result, isA<AnotherTestEvent>());
      });
    });
  });
}
