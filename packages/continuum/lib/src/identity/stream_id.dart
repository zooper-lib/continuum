/// A strongly-typed identifier for event streams (aggregate instances).
///
/// Wraps a string value to provide type safety and prevent accidental
/// interchange with other identifier types like [EventId].
///
/// ```dart
/// final streamId = StreamId('cart_456');
/// print(streamId.value); // 'cart_456'
/// ```
final class StreamId {
  /// The underlying string value of this stream identifier.
  final String value;

  /// Creates a stream identifier from a string [value].
  const StreamId(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is StreamId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'StreamId($value)';
}
