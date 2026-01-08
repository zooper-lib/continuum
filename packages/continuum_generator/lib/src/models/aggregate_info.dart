import 'package:analyzer/dart/element/element.dart';

import 'event_info.dart';

/// Represents an aggregate discovered during code generation.
///
/// Contains information about the aggregate class and its associated
/// creation and mutation events.
final class AggregateInfo {
  /// The class element representing the aggregate.
  final ClassElement element;

  /// Events that can create this aggregate (first event in stream).
  final List<EventInfo> creationEvents;

  /// Events that mutate this aggregate (non-creation events).
  final List<EventInfo> mutationEvents;

  /// Creates an aggregate info with the given properties.
  AggregateInfo({required this.element, List<EventInfo>? creationEvents, List<EventInfo>? mutationEvents})
    : creationEvents = creationEvents ?? [],
      mutationEvents = mutationEvents ?? [];

  /// The name of the aggregate class.
  String get name => element.name ?? element.displayName;

  /// All events (creation + mutation) for this aggregate.
  List<EventInfo> get allEvents => [...creationEvents, ...mutationEvents];
}
