/// Represents the tracked position of a projection with schema version.
///
/// Combines the last processed event sequence number with the schema hash
/// to enable detection of schema changes that require rebuilding.
final class ProjectionPosition {
  /// The global sequence number of the last successfully processed event.
  ///
  /// Null if the projection has never processed any events.
  final int? lastProcessedSequence;

  /// The schema hash at the time of the last save.
  ///
  /// Used to detect schema changes that require rebuilding.
  final String schemaHash;

  /// Creates a projection position.
  const ProjectionPosition({
    required this.lastProcessedSequence,
    required this.schemaHash,
  });

  /// Creates a position for a projection that has never processed events.
  const ProjectionPosition.initial({required this.schemaHash}) : lastProcessedSequence = null;

  /// Returns whether this position indicates the projection should start fresh.
  bool get isInitial => lastProcessedSequence == null;

  /// Returns whether the schema has changed from the given hash.
  bool hasSchemaChangedFrom(String currentSchemaHash) => schemaHash != currentSchemaHash;
}
