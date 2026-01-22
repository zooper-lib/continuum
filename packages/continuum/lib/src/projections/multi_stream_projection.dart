import '../persistence/stored_event.dart';
import 'projection.dart';

/// Projection that builds a read model from events across multiple streams.
///
/// Multi-stream projections aggregate events from many streams into read models
/// grouped by a projection-defined key. Events are processed in global sequence
/// order, providing cross-stream ordering.
///
/// Use cases:
/// - Cross-aggregate views
/// - Dashboards and statistics
/// - Search indexes
/// - Counters across entities
///
/// Example:
/// ```dart
/// class LibraryStatisticsProjection extends MultiStreamProjection<LibraryStats, String> {
///   @override
///   Set<Type> get handledEventTypes => {AudioFileAdded, AudioFileRemoved};
///
///   @override
///   String get projectionName => 'library-statistics';
///
///   @override
///   String extractKey(StoredEvent event) {
///     // Group by library ID from event data
///     return event.data['libraryId'] as String;
///   }
///
///   @override
///   LibraryStats createInitial(String libraryId) =>
///       LibraryStats(libraryId: libraryId, fileCount: 0);
///
///   @override
///   LibraryStats apply(LibraryStats current, StoredEvent event) {
///     // Update statistics based on event type
///   }
/// }
/// ```
abstract class MultiStreamProjection<TReadModel, TKey> extends ProjectionBase<TReadModel, TKey> {
  /// Extracts the grouping key from the event.
  ///
  /// Multiple streams may contribute events to the same key,
  /// enabling cross-aggregate read models.
  @override
  TKey extractKey(StoredEvent event);

  /// Creates the initial read model state for a new key.
  ///
  /// Called when processing the first event for a given key.
  @override
  TReadModel createInitial(TKey key);

  /// Applies an event to update the read model.
  ///
  /// Events arrive in global sequence order, not per-stream order.
  /// Implementations must handle events from multiple streams.
  @override
  TReadModel apply(TReadModel current, StoredEvent event);
}
