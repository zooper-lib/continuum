import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Computes which `apply...` handlers a concrete aggregate is still missing.
///
/// The handler requirements are derived from the generated
/// `_$<Aggregate>EventHandlers` mixin.
final class ContinuumRequiredApplyHandlers {
  static final TypeChecker _aggregateEventChecker = const TypeChecker.fromUrl(
    'package:continuum/src/annotations/aggregate_event.dart#AggregateEvent',
  );

  /// Creates a requirement checker for generated continuum apply handlers.
  const ContinuumRequiredApplyHandlers();

  /// Returns the list of missing apply handler method names.
  ///
  /// If the class does not mix in `_$<Aggregate>EventHandlers`, this returns an
  /// empty list.
  List<String> findMissingApplyHandlers(ClassElement classElement) {
    final List<MethodElement> missingMethods = findMissingApplyHandlerMethods(classElement);

    return missingMethods.map((MethodElement method) => method.displayName).toList(growable: false);
  }

  /// Returns the list of missing apply handler method elements.
  ///
  /// This is useful for generating method stubs in quick-fixes.
  ///
  /// If the class does not mix in `_$<Aggregate>EventHandlers`, this returns an
  /// empty list.
  List<MethodElement> findMissingApplyHandlerMethods(ClassElement classElement) {
    final InterfaceType? eventHandlersMixinType = _findEventHandlersMixinType(classElement);
    if (eventHandlersMixinType == null) {
      return const <MethodElement>[];
    }

    final List<MethodElement> requiredApplyMethods = eventHandlersMixinType.element.methods
        .where((MethodElement method) => method.isAbstract)
        .where((MethodElement method) => method.displayName.startsWith('apply'))
        .where((MethodElement method) => !_isCreationApplyHandler(method, classElement))
        .toList(growable: false);

    if (requiredApplyMethods.isEmpty) {
      return const <MethodElement>[];
    }

    final List<MethodElement> missing = <MethodElement>[];

    for (final MethodElement requiredMethod in requiredApplyMethods) {
      final MethodElement? concreteImplementation = _findConcreteMethodImplementation(classElement, requiredMethod.displayName);
      if (concreteImplementation == null) {
        missing.add(requiredMethod);
      }
    }

    return missing;
  }

  bool _isCreationApplyHandler(MethodElement applyMethod, ClassElement aggregateClassElement) {
    // Convention: apply handlers always accept a single event parameter.
    if (applyMethod.formalParameters.length != 1) return false;

    final FormalParameterElement parameter = applyMethod.formalParameters.single;
    if (parameter.isNamed || parameter.isOptionalPositional) return false;

    final Element? eventElement = parameter.type.element;
    if (eventElement is! ClassElement) return false;

    if (!_aggregateEventChecker.hasAnnotationOf(eventElement)) return false;

    final annotation = _aggregateEventChecker.firstAnnotationOf(eventElement);
    if (annotation == null) return false;

    final DartType? annotatedAggregateType = annotation.getField('of')?.toTypeValue();
    if (annotatedAggregateType?.element != aggregateClassElement) return false;

    return annotation.getField('creation')?.toBoolValue() ?? false;
  }

  InterfaceType? _findEventHandlersMixinType(ClassElement classElement) {
    final String className = classElement.displayName;
    final String expectedMixinName = '_\$${className}EventHandlers';

    for (final InterfaceType mixinType in classElement.mixins) {
      if (mixinType.element.name == expectedMixinName) {
        return mixinType;
      }
    }

    return null;
  }

  MethodElement? _findConcreteMethodImplementation(
    ClassElement classElement,
    String methodName,
  ) {
    // Check the class itself first.
    for (final MethodElement method in classElement.methods) {
      if (method.displayName != methodName) continue;
      if (!method.isAbstract) return method;
    }

    // Then scan the full supertype graph.
    for (final InterfaceType supertype in classElement.allSupertypes) {
      for (final MethodElement method in supertype.element.methods) {
        if (method.displayName != methodName) continue;
        if (!method.isAbstract) return method;
      }
    }

    return null;
  }
}
