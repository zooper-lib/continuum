/// Result of loading a read model with staleness information.
///
/// Wraps a read model value with metadata about whether the value
/// may be stale (e.g., async projections have not yet processed
/// recent events).
final class ReadModelResult<T> {
  /// The read model value, or null if not found.
  final T? value;

  /// Whether the value may be stale due to pending async projections.
  final bool isStale;

  /// Creates a read model result with the given value and staleness.
  const ReadModelResult({this.value, required this.isStale});

  /// Creates a fresh (not stale) result with a value.
  const ReadModelResult.fresh(T this.value) : isStale = false;

  /// Creates a stale result with a value.
  const ReadModelResult.stale(T this.value) : isStale = true;

  /// Creates a not-found result (not stale).
  const ReadModelResult.notFound() : value = null, isStale = false;

  /// Creates a stale not-found result.
  const ReadModelResult.staleNotFound() : value = null, isStale = true;

  /// Whether a value is present.
  bool get hasValue => value != null;

  /// Returns the value or throws if absent.
  T get requireValue {
    final v = value;
    if (v == null) {
      throw StateError('ReadModelResult has no value');
    }
    return v;
  }

  /// Returns the value or the [defaultValue] if absent.
  T valueOr(T defaultValue) => value ?? defaultValue;
}
