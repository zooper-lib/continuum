import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Represents a projection discovered during code generation.
///
/// Contains information about the projection class, its name,
/// handled event types, and the read model type.
final class ProjectionInfo {
  /// The class element representing the projection.
  final ClassElement element;

  /// The unique name for this projection (from annotation).
  final String projectionName;

  /// The event types this projection handles (from annotation).
  final List<DartType> eventTypes;

  /// The read model type inferred from the base class generic parameter.
  ///
  /// For `SingleStreamProjection<UserProfile>`, this would be `UserProfile`.
  final DartType? readModelType;

  /// The key type inferred from the base class generic parameter.
  ///
  /// For `SingleStreamProjection<T>`, this is `StreamId`.
  /// For `MultiStreamProjection<T, K>`, this is `K`.
  final DartType? keyType;

  /// Creates a projection info with the given properties.
  ProjectionInfo({
    required this.element,
    required this.projectionName,
    required this.eventTypes,
    this.readModelType,
    this.keyType,
  });

  /// The name of the projection class.
  String get className => element.name ?? element.displayName;

  /// Returns the event type names as strings for code generation.
  List<String> get eventTypeNames => eventTypes.map((type) => type.element?.name ?? type.toString()).toList();

  /// Returns the read model type name as a string for code generation.
  ///
  /// Throws if the type could not be resolved — projections must always
  /// have a concrete read model type.
  String get readModelTypeName {
    final resolved = readModelType?.getDisplayString();
    if (resolved == null || resolved == 'dynamic') {
      throw StateError(
        'Could not resolve read model type for projection "$className". '
        'Ensure the projection extends SingleStreamProjection<T> or '
        'MultiStreamProjection<T, K> with a concrete type argument.',
      );
    }
    return resolved;
  }

  /// Returns the key type name as a string for code generation.
  ///
  /// Returns `null` when the key type is implicitly `StreamId` (for
  /// [SingleStreamProjection]) — callers should substitute the default.
  String? get keyTypeName {
    final resolved = keyType?.getDisplayString();
    if (resolved == 'dynamic') return null;
    return resolved;
  }
}
