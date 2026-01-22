/// Bundles all generated metadata for a single projection type.
///
/// Each projection generates one of these, containing its name,
/// schema hash, and handled event types. Pass a list of these to
/// [ProjectionRegistry] for automatic configuration.
///
/// ```dart
/// // Generated in user_profile_projection.g.dart:
/// final $UserProfileProjection = GeneratedProjection(
///   projectionName: 'user-profile',
///   schemaHash: 'a1b2c3d4',
///   handledEventTypes: {UserRegistered, EmailChanged},
/// );
///
/// // Usage:
/// final registry = ProjectionRegistry();
/// registry.registerGeneratedInline(
///   $UserProfileProjection,
///   userProfileProjection,
///   userProfileStore,
/// );
/// ```
final class GeneratedProjection {
  /// The unique name identifying this projection.
  ///
  /// Used for position tracking and debugging.
  final String projectionName;

  /// Hash of the projection's event schema.
  ///
  /// Computed from sorted event type names. Changes when events
  /// are added, removed, or renamed, triggering a rebuild.
  final String schemaHash;

  /// The set of event types this projection handles.
  ///
  /// Used by the registry for event routing.
  final Set<Type> handledEventTypes;

  /// Creates a generated projection bundle with all required metadata.
  const GeneratedProjection({
    required this.projectionName,
    required this.schemaHash,
    required this.handledEventTypes,
  });
}
