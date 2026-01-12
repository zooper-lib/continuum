import 'package:zooper_flutter_core/zooper_flutter_core.dart';

/// Base contract for all continuum events in an event-sourced system.
///
/// Continuum events represent facts that have happened in the domain.
/// They are immutable and carry all the information needed to describe
/// what occurred.
///
/// Implementations should provide their own constructors that accept
/// the event-specific data and optionally override [occurredOn] and
/// [metadata] defaults.
///
/// ```dart
/// @AggregateEvent(of: ShoppingCart, type: 'item_added')
/// class ItemAdded implements ContinuumEvent {
///   final String productId;
///   final int quantity;
///
///   ItemAdded({
///     required EventId eventId,
///     required this.productId,
///     required this.quantity,
///     DateTime? occurredOn,
///     Map<String, Object?> metadata = const {},
///   }) : id = eventId,
///        occurredOn = occurredOn ?? DateTime.now(),
///        metadata = Map<String, Object?>.unmodifiable(metadata);
///
///   @override
///   final EventId id;
///
///   @override
///   final DateTime occurredOn;
///
///   @override
///   final Map<String, Object?> metadata;
/// }
/// ```
abstract interface class ContinuumEvent implements ZooperDomainEvent {}
