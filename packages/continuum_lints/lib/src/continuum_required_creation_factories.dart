import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Computes which creation factory methods an aggregate root is missing.
///
/// A creation event `E` for aggregate `A` requires a matching static factory:
/// `static A createFromE(E event)`.
final class ContinuumRequiredCreationFactories {
  static final TypeChecker _aggregateEventChecker = const TypeChecker.fromUrl(
    'package:continuum/src/annotations/aggregate_event.dart#AggregateEvent',
  );

  static final TypeChecker _continuumEventChecker = const TypeChecker.fromUrl(
    'package:continuum/src/events/continuum_event.dart#ContinuumEvent',
  );

  /// Creates a requirement checker for aggregate creation factories.
  const ContinuumRequiredCreationFactories();

  /// Returns the list of missing factory method names.
  List<String> findMissingCreationFactories(ClassElement aggregateClassElement) {
    final List<CreationFactorySpec> specs = findMissingCreationFactorySpecs(
      aggregateClassElement,
    );

    return specs.map((CreationFactorySpec spec) => spec.methodName).toList(growable: false);
  }

  /// Returns the list of missing creation factory specifications.
  ///
  /// This is useful for quick-fixes that need both the method name and the
  /// event type name.
  List<CreationFactorySpec> findMissingCreationFactorySpecs(
    ClassElement aggregateClassElement,
  ) {
    final List<ClassElement> creationEventTypes = _findCreationEventTypes(
      aggregateClassElement,
    );

    if (creationEventTypes.isEmpty) {
      return const <CreationFactorySpec>[];
    }

    final List<CreationFactorySpec> missingFactories = <CreationFactorySpec>[];

    for (final ClassElement creationEventType in creationEventTypes) {
      final String eventName = creationEventType.name ?? creationEventType.displayName;
      if (eventName.isEmpty) continue;

      final String requiredFactoryName = 'createFrom$eventName';

      final bool hasFactory = aggregateClassElement.methods.any(
        (MethodElement method) {
          if (!method.isStatic) return false;
          if (method.displayName != requiredFactoryName) return false;

          if (method.formalParameters.length != 1) return false;
          final FormalParameterElement parameter = method.formalParameters.single;
          if (parameter.isNamed || parameter.isOptionalPositional) return false;
          if (parameter.type.element != creationEventType) return false;

          final typeSystem = aggregateClassElement.library.typeSystem;
          return typeSystem.isSubtypeOf(
            method.returnType,
            aggregateClassElement.thisType,
          );
        },
      );

      if (!hasFactory) {
        missingFactories.add(
          CreationFactorySpec(
            methodName: requiredFactoryName,
            eventTypeName: eventName,
          ),
        );
      }
    }

    return missingFactories;
  }

  List<ClassElement> _findCreationEventTypes(ClassElement aggregateClassElement) {
    final LibraryElement aggregateLibrary = aggregateClassElement.library;

    final Set<LibraryElement> librariesToScan = <LibraryElement>{aggregateLibrary};

    // Include imported libraries from all fragments/parts for stability.
    for (final LibraryFragment fragment in aggregateLibrary.fragments) {
      librariesToScan.addAll(fragment.importedLibraries);
    }

    final List<ClassElement> creationEventTypes = <ClassElement>[];

    for (final LibraryElement library in librariesToScan) {
      for (final ClassElement candidate in library.classes) {
        if (!_aggregateEventChecker.hasAnnotationOf(candidate)) continue;
        if (!_continuumEventChecker.isAssignableFrom(candidate)) continue;

        final annotation = _aggregateEventChecker.firstAnnotationOf(candidate);
        if (annotation == null) continue;

        final ofValue = annotation.getField('of');
        final DartType? aggregateType = ofValue?.toTypeValue();

        if (aggregateType?.element != aggregateClassElement) continue;

        final bool isCreation = annotation.getField('creation')?.toBoolValue() ?? false;
        if (!isCreation) continue;

        creationEventTypes.add(candidate);
      }
    }

    return creationEventTypes;
  }
}

/// Description of a required creation factory.
final class CreationFactorySpec {
  /// Creates a factory specification.
  const CreationFactorySpec({
    required this.methodName,
    required this.eventTypeName,
  });

  /// The required static factory method name (e.g. `createFromUserRegistered`).
  final String methodName;

  /// The creation event type name.
  final String eventTypeName;
}
