/// Tracks the processing position for an async projection.
///
/// Stores the last processed global sequence number and a schema
/// hash for detecting projection schema changes that require replay.
final class ProjectionPosition {
  /// The last successfully processed global sequence number.
  ///
  /// Null when the projection has not yet processed any events.
  final int? lastProcessedSequence;

  /// Hash of the projection schema at the time of last processing.
  ///
  /// Used to detect schema changes that invalidate existing read models
  /// and require a full replay.
  final String schemaHash;

  /// Creates a projection position with the given state.
  const ProjectionPosition({
    required this.lastProcessedSequence,
    required this.schemaHash,
  });

  /// Creates an initial projection position with no processed events.
  const ProjectionPosition.initial({required this.schemaHash}) : lastProcessedSequence = null;

  /// Whether this position is the initial (no events processed) state.
  bool get isInitial => lastProcessedSequence == null;

  /// Whether the schema has changed from the [currentSchemaHash].
  bool hasSchemaChangedFrom(String currentSchemaHash) => schemaHash != currentSchemaHash;
}
