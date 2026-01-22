import '../identity/stream_id.dart';
import '../persistence/stored_event.dart';
import 'projection.dart';

/// Projection that builds a read model from a single event stream.
///
/// Single-stream projections create one read model instance per aggregate,
/// identified by the stream's [StreamId]. Events are processed in per-stream
/// version order, providing deterministic ordering.
///
/// Use cases:
/// - Aggregate summaries
/// - Per-entity query models
/// - State snapshots
///
/// Example:
/// ```dart
/// class UserProfileProjection extends SingleStreamProjection<UserProfile> {
///   @override
///   Set<Type> get handledEventTypes => {UserRegistered, ProfileUpdated};
///
///   @override
///   String get projectionName => 'user-profile';
///
///   @override
///   UserProfile createInitial(StreamId streamId) =>
///       UserProfile(id: streamId.value);
///
///   @override
///   UserProfile apply(UserProfile current, StoredEvent event) {
///     // Apply event to update the profile
///   }
/// }
/// ```
abstract class SingleStreamProjection<TReadModel> extends ProjectionBase<TReadModel, StreamId> {
  /// Extracts the stream ID from the event.
  ///
  /// For single-stream projections, the key is always the event's stream ID,
  /// ensuring one read model per aggregate instance.
  @override
  StreamId extractKey(StoredEvent event) => event.streamId;

  /// Creates the initial read model state for a new stream.
  ///
  /// Called when processing the first event for a given stream ID.
  @override
  TReadModel createInitial(StreamId streamId);

  /// Applies an event to update the read model.
  ///
  /// Events arrive in per-stream version order (0, 1, 2, ...).
  @override
  TReadModel apply(TReadModel current, StoredEvent event);
}
