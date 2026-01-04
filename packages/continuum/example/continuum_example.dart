import 'package:continuum/continuum.dart';

// NOTE: This example requires running `dart run build_runner build` first.
// The generated file provides:
// - _$ShoppingCartEventHandlers mixin (enforces apply method signatures)
// - applyEvent() dispatcher extension
// - replayEvents() helper extension
// - createFromEvent() factory

part 'continuum_example.g.dart';

/// Example aggregate representing a shopping cart.
///
/// The aggregate mixes in the generated _$ShoppingCartEventHandlers mixin,
/// which REQUIRES implementing apply methods for all mutation events.
/// If any apply method is missing, the project fails to compile.
@Aggregate()
class ShoppingCart with _$ShoppingCartEventHandlers {
  /// The unique identifier for this cart.
  final String id;

  /// The items currently in the cart.
  final List<CartItem> items;

  /// Private constructor - aggregates are created via static create* methods.
  ShoppingCart._({required this.id, required this.items});

  /// Creates a new cart from a CartCreated event.
  ///
  /// This is a CREATION factory - it constructs the aggregate from the
  /// first event in a stream. The body is written by the developer.
  /// No apply method is called for creation events.
  static ShoppingCart createCartCreated(CartCreated event) {
    return ShoppingCart._(id: event.cartId, items: []);
  }

  /// Applies an ItemAdded event to this cart.
  ///
  /// This is a MUTATION handler - the signature is enforced by the
  /// generated mixin, but the body is written by the developer.
  @override
  void applyItemAdded(ItemAdded event) {
    items.add(CartItem(productId: event.productId, quantity: event.quantity));
  }

  /// Applies an ItemRemoved event to this cart.
  @override
  void applyItemRemoved(ItemRemoved event) {
    items.removeWhere((item) => item.productId == event.productId);
  }
}

/// Represents an item in the cart.
class CartItem {
  final String productId;
  final int quantity;

  CartItem({required this.productId, required this.quantity});
}

/// Event fired when a cart is created (CREATION event).
///
/// Creation events use static create* methods, not apply methods.
@Event(ofAggregate: ShoppingCart, type: 'cart.created')
class CartCreated extends DomainEvent {
  final String cartId;

  CartCreated({required super.eventId, required this.cartId, super.occurredOn, super.metadata});

  factory CartCreated.fromJson(Map<String, dynamic> json) {
    return CartCreated(eventId: EventId(json['eventId'] as String), cartId: json['cartId'] as String);
  }
}

/// Event fired when an item is added to the cart (MUTATION event).
///
/// Mutation events require an apply method on the aggregate.
/// The generated mixin enforces this at compile time.
@Event(ofAggregate: ShoppingCart, type: 'item.added')
class ItemAdded extends DomainEvent {
  final String productId;
  final int quantity;

  ItemAdded({required super.eventId, required this.productId, required this.quantity, super.occurredOn, super.metadata});

  factory ItemAdded.fromJson(Map<String, dynamic> json) {
    return ItemAdded(eventId: EventId(json['eventId'] as String), productId: json['productId'] as String, quantity: json['quantity'] as int);
  }
}

/// Event fired when an item is removed from the cart.
@Event(ofAggregate: ShoppingCart, type: 'item.removed')
class ItemRemoved extends DomainEvent {
  final String productId;

  ItemRemoved({required super.eventId, required this.productId, super.occurredOn, super.metadata});

  factory ItemRemoved.fromJson(Map<String, dynamic> json) {
    return ItemRemoved(eventId: EventId(json['eventId'] as String), productId: json['productId'] as String);
  }
}

void main() {
  // Create a cart using a creation event and the static factory
  final creationEvent = CartCreated(eventId: EventId('evt-1'), cartId: 'cart-123');

  // Use the generated createFromEvent dispatcher (or call static method directly)
  final cart = ShoppingCart.createCartCreated(creationEvent);
  print('Created cart: ${cart.id}');

  // Apply mutation events using the GENERATED applyEvent() dispatcher.
  // This routes to the correct apply method based on event type.
  // If you pass an unsupported event type, it throws UnsupportedEventException.
  cart.applyEvent(ItemAdded(eventId: EventId('evt-2'), productId: 'product-abc', quantity: 2));

  cart.applyEvent(ItemAdded(eventId: EventId('evt-3'), productId: 'product-xyz', quantity: 1));

  print('Cart has ${cart.items.length} items');

  // Remove an item
  cart.applyEvent(ItemRemoved(eventId: EventId('evt-4'), productId: 'product-abc'));

  print('After removal, cart has ${cart.items.length} items');

  // You can also replay multiple events at once
  // cart.replayEvents([event1, event2, event3]);
}
