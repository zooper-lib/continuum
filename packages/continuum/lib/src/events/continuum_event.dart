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
/// class ItemAdded extends ContinuumEvent {
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
abstract interface class ContinuumEvent implements ZooperDomainEvent {}
