/// Represents the expected version for optimistic concurrency control.
///
/// Used when appending events to ensure no concurrent modifications
/// have occurred since the stream was loaded.
final class ExpectedVersion {
  /// The expected version value.
  ///
  /// Special values:
  /// - `-1`: No stream should exist (for new streams)
  /// - `>= 0`: Specific version expected
  final int value;

  /// Creates an expected version with a specific [value].
  const ExpectedVersion._(this.value);

  /// Expects that no stream exists yet.
  ///
  /// Use this when starting a new stream with a creation event.
  static const ExpectedVersion noStream = ExpectedVersion._(-1);

  /// Expects a specific version.
  ///
  /// The append will succeed only if the stream's current version
  /// matches this value exactly.
  factory ExpectedVersion.exact(int version) {
    // Validate that version is non-negative
    if (version < 0) {
      throw ArgumentError.value(
        version,
        'version',
        'Version must be non-negative. Use ExpectedVersion.noStream for new streams.',
      );
    }
    return ExpectedVersion._(version);
  }

  /// Whether this expects a new stream with no events.
  bool get isNoStream => value == -1;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpectedVersion && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() =>
      isNoStream ? 'ExpectedVersion.noStream' : 'ExpectedVersion($value)';
}
