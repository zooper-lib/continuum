/// Marks a class as an event-sourced aggregate root.
///
/// When the generator scans the library, classes annotated with `@Aggregate()`
/// are treated as aggregate candidates for code generation.
///
/// ```dart
/// @Aggregate()
/// class ShoppingCart with _$ShoppingCartEventHandlers {
///   // aggregate implementation
/// }
/// ```
class Aggregate {
  /// Creates an aggregate annotation.
  const Aggregate();
}
