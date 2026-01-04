/// Marks a class as a domain event belonging to a specific aggregate.
///
/// The generator uses this annotation to discover events and associate them
/// with their parent aggregate for code generation.
///
/// The [type] parameter is optional when using the core layer without
/// persistence. When persistence is needed, [type] provides a stable string
/// discriminator for serialization.
///
/// ```dart
/// @Event(ofAggregate: ShoppingCart)
/// class ItemAdded extends DomainEvent {
///   // event implementation
/// }
/// ```
class Event {
  /// The aggregate type this event belongs to.
  ///
  /// This creates a compile-time association between the event and its
  /// aggregate, enabling the generator to build proper mappings.
  final Type ofAggregate;

  /// Optional stable type discriminator for persistence serialization.
  ///
  /// When null, the event can still be used for in-memory event-driven
  /// mutation, but cannot be persisted without explicit type mapping.
  final String? type;

  /// Creates an event annotation associating this event with [ofAggregate].
  ///
  /// The [type] parameter provides a stable string discriminator for
  /// persistence serialization. When omitted, the event remains valid
  /// for in-memory usage but cannot be persisted.
  const Event({required this.ofAggregate, this.type});
}
