import '../projections/projection_lifecycle.dart';

/// Marks a class as a projection that transforms events into read models.
///
/// When the generator scans the library, classes annotated with `@Projection()`
/// are treated as projection candidates for code generation.
///
/// The generator creates:
/// - `_$<Name>Handlers` mixin with abstract `apply<EventName>` methods
/// - `$<Name>EventDispatch` extension with `applyEvent()` dispatcher
/// - `$<Name>` bundle constant with metadata for registry
/// - Registration glue in the combining builder's `registerAll` extension
class Projection {
  /// A unique name identifying this projection.
  ///
  /// Used for position tracking in async projections and for debugging.
  /// This name is persisted, so renaming breaks position recovery.
  final String name;

  /// The list of event types this projection handles.
  ///
  /// The generator uses this list to create the required `apply<EventName>`
  /// methods in the generated mixin. The Dart compiler then enforces that
  /// the user implements all handlers.
  final List<Type> events;

  /// The execution lifecycle for this projection.
  ///
  /// Determines whether the projection runs synchronously during
  /// [Session.saveChangesAsync] ([ProjectionLifecycle.inline]) or is
  /// scheduled for background processing ([ProjectionLifecycle.async]).
  ///
  /// Defaults to [ProjectionLifecycle.inline].
  final ProjectionLifecycle lifecycle;

  /// Creates a projection annotation with the required [name] and [events].
  const Projection({
    required this.name,
    required this.events,
    this.lifecycle = ProjectionLifecycle.inline,
  });
}
