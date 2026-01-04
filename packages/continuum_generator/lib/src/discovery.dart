import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';

import 'models/aggregate_info.dart';
import 'models/event_info.dart';

/// Type checker for the @Aggregate annotation.
const _aggregateChecker = TypeChecker.fromUrl('package:continuum/src/annotations/aggregate.dart#Aggregate');

/// Type checker for the @Event annotation.
const _eventChecker = TypeChecker.fromUrl('package:continuum/src/annotations/event.dart#Event');

/// Type checker for the DomainEvent base class.
const _domainEventChecker = TypeChecker.fromUrl('package:continuum/src/events/domain_event.dart#DomainEvent');

/// Discovers aggregates and events from library elements.
///
/// Scans a library for classes annotated with `@Aggregate()` and `@Event()`
/// and builds the mapping between aggregates and their events.
///
/// Events can be defined in the same file OR in separate imported files.
/// The generator discovers events by:
/// 1. Looking at elements defined in this library (including part files)
/// 2. Looking at imported elements that have `@Event(ofAggregate: X)`
///    where X is an aggregate defined in this library
final class AggregateDiscovery {
  /// Discovers all aggregates and events in the given library.
  ///
  /// Returns a list of [AggregateInfo] with associated events categorized
  /// as creation or mutation events.
  List<AggregateInfo> discoverAggregates(LibraryElement library) {
    final aggregates = <String, AggregateInfo>{};
    final pendingEvents = <EventInfo>[];

    // First pass: discover all aggregates in THIS library
    for (final element in library.topLevelElements) {
      if (element is ClassElement && _aggregateChecker.hasAnnotationOf(element)) {
        aggregates[element.name] = AggregateInfo(element: element);
      }
    }

    // If no aggregates in this library, nothing to generate
    if (aggregates.isEmpty) {
      return [];
    }

    // Second pass: discover events defined in THIS library
    for (final element in library.topLevelElements) {
      if (element is ClassElement && _eventChecker.hasAnnotationOf(element)) {
        final eventInfo = _extractEventInfo(element);
        if (eventInfo != null) {
          pendingEvents.add(eventInfo);
        }
      }
    }

    // Third pass: discover events from IMPORTED libraries
    // This allows events to be defined in separate files
    for (final importedLibrary in library.importedLibraries) {
      // Scan exported elements from the imported library
      for (final element in importedLibrary.exportNamespace.definedNames.values) {
        if (element is ClassElement && _eventChecker.hasAnnotationOf(element)) {
          final eventInfo = _extractEventInfo(element);
          if (eventInfo != null) {
            // Only include if this event belongs to an aggregate in THIS library
            if (aggregates.containsKey(eventInfo.aggregateTypeName)) {
              pendingEvents.add(eventInfo);
            }
          }
        }
      }
    }

    // Associate events with aggregates
    for (final eventInfo in pendingEvents) {
      final aggregate = aggregates[eventInfo.aggregateTypeName];
      if (aggregate != null) {
        if (eventInfo.isCreationEvent) {
          aggregate.creationEvents.add(eventInfo);
        } else {
          aggregate.mutationEvents.add(eventInfo);
        }
      }
    }

    return aggregates.values.toList();
  }

  /// Extracts event information from an annotated class element.
  EventInfo? _extractEventInfo(ClassElement element) {
    // Verify the event extends DomainEvent
    if (!_domainEventChecker.isSuperOf(element)) {
      // Could throw an error here, but for now we skip non-DomainEvent classes
      return null;
    }

    final annotation = _eventChecker.firstAnnotationOf(element);
    if (annotation == null) return null;

    // Extract the ofAggregate type
    final ofAggregateValue = annotation.getField('ofAggregate');
    if (ofAggregateValue == null || ofAggregateValue.isNull) return null;

    final aggregateType = ofAggregateValue.toTypeValue();
    if (aggregateType == null) return null;

    final aggregateTypeName = _getTypeName(aggregateType);
    if (aggregateTypeName == null) return null;

    // Extract the optional type discriminator
    final typeValue = annotation.getField('type');
    final type = typeValue?.toStringValue();

    // Determine if this is a creation event by checking for a static create method
    final isCreationEvent = _hasCreateMethod(element, aggregateType);

    return EventInfo(element: element, aggregateTypeName: aggregateTypeName, type: type, isCreationEvent: isCreationEvent);
  }

  /// Gets the type name from a DartType.
  String? _getTypeName(DartType type) {
    final element = type.element;
    if (element is ClassElement) {
      return element.name;
    }
    return null;
  }

  /// Checks if the aggregate has a static create method for this event.
  ///
  /// Convention: A creation event should have a corresponding static method
  /// named `create<EventName>` or the aggregate should have a factory that
  /// accepts this event type.
  bool _hasCreateMethod(ClassElement eventElement, DartType aggregateType) {
    final aggregateElement = aggregateType.element;
    if (aggregateElement is! ClassElement) return false;

    // Look for static methods starting with 'create' that take this event type
    for (final method in aggregateElement.methods) {
      if (method.isStatic && method.name.startsWith('create')) {
        // Check if the method has a parameter of this event type
        for (final param in method.parameters) {
          if (param.type.element == eventElement) {
            return true;
          }
        }
      }
    }

    return false;
  }
}
