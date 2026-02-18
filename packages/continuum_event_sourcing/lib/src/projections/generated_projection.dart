/// Metadata bundle for a generated projection.
///
/// Created by the code generator to carry projection metadata
/// (name, schema hash, handled event types) for registration.
final class GeneratedProjection {
  /// The unique name for the projection.
  final String projectionName;

  /// Hash of the projection schema for change detection.
  final String schemaHash;

  /// The event types this projection handles.
  final Set<Type> handledEventTypes;

  /// Creates a generated projection metadata bundle.
  const GeneratedProjection({
    required this.projectionName,
    required this.schemaHash,
    required this.handledEventTypes,
  });
}
