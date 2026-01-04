import 'package:continuum/continuum.dart';
import 'package:test/test.dart';

void main() {
  group('EventId', () {
    test('should store the value correctly', () {
      // Arrange
      const value = 'evt_123';

      // Act
      final eventId = EventId(value);

      // Assert - the value should be accessible
      expect(eventId.value, equals(value));
    });

    test('should be equal when values are the same', () {
      // Arrange
      const value = 'evt_abc';

      // Act
      final eventId1 = EventId(value);
      final eventId2 = EventId(value);

      // Assert - equality should be based on value
      expect(eventId1, equals(eventId2));
      expect(eventId1.hashCode, equals(eventId2.hashCode));
    });

    test('should not be equal when values differ', () {
      // Arrange & Act
      final eventId1 = EventId('evt_1');
      final eventId2 = EventId('evt_2');

      // Assert - different values should not be equal
      expect(eventId1, isNot(equals(eventId2)));
    });

    test('should have meaningful toString representation', () {
      // Arrange
      const value = 'evt_xyz';

      // Act
      final eventId = EventId(value);

      // Assert - toString should include the value
      expect(eventId.toString(), contains(value));
    });
  });
}
