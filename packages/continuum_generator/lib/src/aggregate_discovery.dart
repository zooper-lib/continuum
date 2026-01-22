import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';

import 'models/aggregate_info.dart';
import 'models/event_info.dart';

/// Type checker for bounded's AggregateRoot base class.
const _aggregateRootChecker = TypeChecker.fromUrl('package:bounded/src/aggregate_root.dart#AggregateRoot');

/// Type checker for the @AggregateEvent annotation.
const _eventChecker = TypeChecker.fromUrl('package:continuum/src/annotations/aggregate_event.dart#AggregateEvent');

/// Type checker for the ContinuumEvent base class.
const _continuumEventChecker = TypeChecker.fromUrl('package:continuum/src/events/continuum_event.dart#ContinuumEvent');

/// Discovers aggregates and events from library elements.
///
/// Scans a library for classes that extend/implement `AggregateRoot` and
/// events annotated with `@AggregateEvent()`
/// and builds the mapping between aggregates and their events.
///
/// Events can be defined in the same file OR in separate imported files.
///
/// The generator can discover events from:
/// 1. Elements defined in this library (including part files)
/// 2. A wider set of candidate libraries (e.g. all libraries in the package)
///
/// This flexibility allows the generator to discover events even when the
/// aggregate library does not import the event's defining library.
final class AggregateDiscovery {
  /// Discovers all aggregates and events in the given library.
  ///
  /// Returns a list of [AggregateInfo] with associated events categorized
  /// as creation or mutation events.
  ///
  /// When [candidateEventLibraries] is provided, events are discovered by
  /// scanning those libraries (and this library) for `@AggregateEvent` types.
  ///
  /// When [candidateEventLibraries] is not provided, discovery is limited to
  /// this library and its direct imports.
  List<AggregateInfo> discoverAggregates(
    LibraryElement library, {
    Iterable<LibraryElement>? candidateEventLibraries,
  }) {
    final aggregates = <String, AggregateInfo>{};
    final pendingEvents = <EventInfo>[];

    // First pass: discover all aggregates in THIS library.
    //
    // Aggregates are discovered by being assignable to bounded's AggregateRoot.
    for (final element in library.classes) {
      if (_aggregateRootChecker.isAssignableFrom(element)) {
        final aggregateName = element.name ?? element.displayName;
        if (aggregateName.isEmpty) continue;
        aggregates[aggregateName] = AggregateInfo(element: element);
      }
    }

    // If no aggregates in this library, nothing to generate
    if (aggregates.isEmpty) {
      return [];
    }

    // Second pass: discover events.
    //
    // If candidateEventLibraries is provided, scan that wider set.
    // Otherwise, fall back to scanning this library and its direct imports.
    final librariesToScan = <LibraryElement>{
      library,
      if (candidateEventLibraries != null) ...candidateEventLibraries,
    };

    if (candidateEventLibraries == null) {
      for (final fragment in library.fragments) {
        librariesToScan.addAll(fragment.importedLibraries);
      }
    }

    final discoveredEventsByKey = <String, EventInfo>{};

    for (final candidateLibrary in librariesToScan) {
      for (final element in candidateLibrary.classes) {
        if (!_eventChecker.hasAnnotationOf(element)) continue;

        final eventInfo = _extractEventInfo(element);
        if (eventInfo == null) continue;

        // Only include if this event belongs to an aggregate in THIS library.
        if (!aggregates.containsKey(eventInfo.aggregateTypeName)) continue;

        final eventName = element.name ?? element.displayName;
        final key = '${eventInfo.aggregateTypeName}#$eventName';

        discoveredEventsByKey[key] = eventInfo;
      }
    }

    pendingEvents.addAll(discoveredEventsByKey.values);

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
    // Verify the event extends ContinuumEvent
    if (!_continuumEventChecker.isAssignableFrom(element)) {
      // Could throw an error here, but for now we skip non-ContinuumEvent classes
      return null;
    }

    final annotation = _eventChecker.firstAnnotationOf(element);
    if (annotation == null) return null;

    // Extract the of type
    final ofAggregateValue = annotation.getField('of');
    if (ofAggregateValue == null || ofAggregateValue.isNull) return null;

    final aggregateType = ofAggregateValue.toTypeValue();
    if (aggregateType == null) return null;

    final aggregateTypeName = _getTypeName(aggregateType);
    if (aggregateTypeName == null) return null;

    // Extract the optional type discriminator
    final typeValue = annotation.getField('type');
    final type = typeValue?.toStringValue();

    // Determine if this is a creation event via explicit annotation flag.
    final creationValue = annotation.getField('creation');
    final bool isCreationEvent = creationValue?.toBoolValue() ?? false;

    if (isCreationEvent) {
      _validateCreationFactory(
        aggregateType: aggregateType,
        eventElement: element,
      );
    }

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

  /// Validates that the aggregate declares the required creation factory.
  ///
  /// Convention: a creation event `E` for aggregate `A` requires:
  /// `static A createFromE(E event)`
  void _validateCreationFactory({
    required DartType aggregateType,
    required ClassElement eventElement,
  }) {
    final Element? aggregateElement = aggregateType.element;
    if (aggregateElement is! ClassElement) {
      throw InvalidGenerationSourceError(
        'Invalid @AggregateEvent(of: ...) type: expected a class type for the aggregate, got $aggregateType.',
        element: eventElement,
      );
    }

    final String eventName = eventElement.name ?? eventElement.displayName;
    if (eventName.isEmpty) {
      throw InvalidGenerationSourceError(
        'Creation event type has no name.',
        element: eventElement,
      );
    }

    final String expectedFactoryName = 'createFrom$eventName';

    MethodElement? factoryMethod;
    for (final MethodElement method in aggregateElement.methods) {
      if (!method.isStatic) continue;
      if (method.displayName != expectedFactoryName) continue;
      factoryMethod = method;
      break;
    }

    if (factoryMethod == null) {
      throw InvalidGenerationSourceError(
        'Creation event $eventName requires ${aggregateElement.displayName}.$expectedFactoryName($eventName event).',
        element: aggregateElement,
      );
    }

    if (factoryMethod.formalParameters.length != 1) {
      throw InvalidGenerationSourceError(
        '${aggregateElement.displayName}.$expectedFactoryName must take exactly one parameter of type $eventName.',
        element: factoryMethod,
      );
    }

    final FormalParameterElement parameter = factoryMethod.formalParameters.single;
    if (parameter.isNamed || parameter.isOptionalPositional) {
      throw InvalidGenerationSourceError(
        '${aggregateElement.displayName}.$expectedFactoryName parameter must be a required positional $eventName.',
        element: factoryMethod,
      );
    }

    if (parameter.type.element != eventElement) {
      throw InvalidGenerationSourceError(
        '${aggregateElement.displayName}.$expectedFactoryName must accept a $eventName parameter.',
        element: factoryMethod,
      );
    }

    final typeSystem = aggregateElement.library.typeSystem;
    if (!typeSystem.isSubtypeOf(factoryMethod.returnType, aggregateType)) {
      throw InvalidGenerationSourceError(
        '${aggregateElement.displayName}.$expectedFactoryName must return ${aggregateElement.displayName} (or a subtype).',
        element: factoryMethod,
      );
    }
  }
}
