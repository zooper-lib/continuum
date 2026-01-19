/// Result of a read model query with staleness information.
///
/// During schema migration or projection rebuild, read models may be
/// temporarily stale. This class communicates that state to callers
/// so they can display appropriate UI indicators.
///
/// ```dart
/// final result = await readModelStore.loadAsync(streamId);
/// if (result.isStale) {
///   // Show data with stale indicator
///   showWithStaleIndicator(result.value);
/// } else {
///   show(result.value);
/// }
/// ```
final class ReadModelResult<T> {
  /// The read model value, or null if not found.
  final T? value;

  /// Whether the read model may be stale due to an ongoing rebuild.
  ///
  /// When `true`, the data is available but may not reflect recent events.
  /// The UI should display an appropriate indicator.
  final bool isStale;

  /// Creates a read model result.
  const ReadModelResult({this.value, required this.isStale});

  /// Creates a fresh (non-stale) result with a value.
  const ReadModelResult.fresh(T this.value) : isStale = false;

  /// Creates a stale result with a value.
  const ReadModelResult.stale(T this.value) : isStale = true;

  /// Creates a not-found result.
  const ReadModelResult.notFound() : value = null, isStale = false;

  /// Creates a stale not-found result (during rebuild).
  const ReadModelResult.staleNotFound() : value = null, isStale = true;

  /// Returns whether a value is present.
  bool get hasValue => value != null;

  /// Returns the value or throws if not present.
  T get requireValue {
    final v = value;
    if (v == null) {
      throw StateError('ReadModelResult has no value');
    }
    return v;
  }

  /// Returns the value or a default if not present.
  T valueOr(T defaultValue) => value ?? defaultValue;
}
