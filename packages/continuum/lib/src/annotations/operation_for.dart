/// Marks a class as an operation that can be applied to a specific target type.
///
/// The generator uses this annotation to associate operation types with their
/// targets and generate dispatch and registry wiring.
///
/// The [key] parameter provides an optional stable discriminator for
/// persistence serialization. When null, the operation can still be used for
/// in-memory mutation but cannot be persisted without an explicit mapping.
///
/// When [creation] is `true`, the generator treats this operation as a
/// creation operation and requires the target to declare a matching static
/// factory method `createFrom<OperationName>(Operation operation)`.
final class OperationFor {
  /// The target type this operation belongs to.
  final Type type;

  /// Optional stable key discriminator for persistence serialization.
  final String? key;

  /// Whether this is a creation operation (the first operation in a stream).
  final bool creation;

  /// Creates an operation annotation associating this operation with [type].
  const OperationFor({
    required this.type,
    this.key,
    this.creation = false,
  });
}
