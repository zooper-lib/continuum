/// Marks a class as a projection that transforms events into read models.
///
/// When the generator scans the library, classes annotated with `@Projection()`
/// are treated as projection candidates for code generation.
///
/// The generator creates:
/// - `_$<Name>Handlers` mixin with abstract `apply<EventName>` methods
/// - `$<Name>EventDispatch` extension with `applyEvent()` dispatcher
/// - `$<Name>` bundle constant with metadata for registry
///
/// Example:
/// ```dart
/// @Projection(name: 'user-profile', events: [UserRegistered, EmailChanged])
/// class UserProfileProjection extends SingleStreamProjection<UserProfile>
///     with _$UserProfileProjectionHandlers {
///
///   @override
///   UserProfile createInitial(StreamId streamId) =>
///       UserProfile(id: streamId.value);
///
///   @override
///   UserProfile applyUserRegistered(UserProfile current, UserRegistered event) =>
///       current.copyWith(name: event.name, email: event.email);
///
///   @override
///   UserProfile applyEmailChanged(UserProfile current, EmailChanged event) =>
///       current.copyWith(email: event.newEmail);
/// }
/// ```
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

  /// Creates a projection annotation with the required [name] and [events].
  const Projection({required this.name, required this.events});
}
