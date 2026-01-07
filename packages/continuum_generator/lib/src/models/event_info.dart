import 'package:analyzer/dart/element/element.dart';

/// Represents an event discovered during code generation.
///
/// Contains information about the event class, its aggregate association,
/// and whether it's a creation or mutation event.
final class EventInfo {
  /// The class element representing the event.
  final ClassElement element;

  /// The type of the aggregate this event belongs to.
  final String aggregateTypeName;

  /// The stable type discriminator for persistence (optional).
  final String? type;

  /// Whether this is a creation event (first event in stream).
  final bool isCreationEvent;

  /// Creates an event info with the given properties.
  EventInfo({required this.element, required this.aggregateTypeName, required this.isCreationEvent, this.type});

  /// The name of the event class.
  String get name => element.name;

  /// The type discriminator, defaulting to the class name if not specified.
  String get typeDiscriminator => type ?? name;
}
