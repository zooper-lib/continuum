import 'package:continuum/continuum.dart';
import 'package:test/test.dart';

void main() {
  group('StreamId', () {
    test('should store the value correctly', () {
      // Arrange
      const value = 'cart_123';

      // Act
      final streamId = const StreamId(value);

      // Assert - the value should be accessible
      expect(streamId.value, equals(value));
    });

    test('should be equal when values are the same', () {
      // Arrange
      const value = 'order_abc';

      // Act
      final streamId1 = const StreamId(value);
      final streamId2 = const StreamId(value);

      // Assert - equality should be based on value
      expect(streamId1, equals(streamId2));
      expect(streamId1.hashCode, equals(streamId2.hashCode));
    });

    test('should not be equal when values differ', () {
      // Arrange & Act
      final streamId1 = const StreamId('stream_1');
      final streamId2 = const StreamId('stream_2');

      // Assert - different values should not be equal
      expect(streamId1, isNot(equals(streamId2)));
    });

    test('should not be interchangeable with EventId', () {
      // Arrange - same string value but different types
      const value = 'same_id';
      final streamId = const StreamId(value);
      final eventId = const EventId(value);

      // Assert - type safety prevents equality (at compile time too)
      // These are different types and cannot be compared as equal
      expect(streamId.runtimeType, isNot(equals(eventId.runtimeType)));
    });

    test('should have meaningful toString representation', () {
      // Arrange
      const value = 'user_xyz';

      // Act
      final streamId = const StreamId(value);

      // Assert - toString should include the value
      expect(streamId.toString(), contains(value));
    });
  });
}
