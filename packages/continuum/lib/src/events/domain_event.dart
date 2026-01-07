import '../identity/event_id.dart';

/// Base contract for all domain events in an event-sourced system.
///
/// Domain events represent facts that have happened in the domain.
/// They are immutable and carry all the information needed to describe
/// what occurred.
///
/// Implementations should provide their own constructors that accept
/// the event-specific data and optionally override [occurredOn] and
/// [metadata] defaults.
///
/// ```dart
/// @Event(ofAggregate: ShoppingCart, type: 'item_added')
/// class ItemAdded extends DomainEvent {
///   final String productId;
///   final int quantity;
///
///   ItemAdded({
///     required super.eventId,
///     required this.productId,
///     required this.quantity,
///     super.occurredOn,
///     super.metadata,
///   });
/// }
/// ```
abstract class DomainEvent {
  /// Unique identifier for this event instance.
  final EventId eventId;

  /// The timestamp when this event occurred.
  ///
  /// Defaults to UTC now if not explicitly provided.
  final DateTime occurredOn;

  /// Optional metadata associated with this event.
  ///
  /// Can include correlation IDs, causation IDs, user context, etc.
  final Map<String, dynamic> metadata;

  /// Creates a domain event with the given [eventId].
  ///
  /// If [occurredOn] is not provided, it defaults to the current UTC time.
  /// If [metadata] is not provided, it defaults to an empty map.
  DomainEvent({
    required this.eventId,
    DateTime? occurredOn,
    Map<String, dynamic>? metadata,
  }) : occurredOn = occurredOn ?? DateTime.now().toUtc(),
       metadata = metadata ?? const {};
}
