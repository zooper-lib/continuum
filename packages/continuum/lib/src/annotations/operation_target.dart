/// Marks a class as a target for operation-driven mutation.
///
/// The code generator uses this annotation to discover types that should
/// receive generated operation dispatch helpers and registry entries.
///
/// This annotation exists to avoid requiring a specific base class (such as
/// `AggregateRoot`) for discovery.
final class OperationTarget {
  /// Creates an operation target marker.
  const OperationTarget();
}
