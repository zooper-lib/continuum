import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Computes which `apply...` handlers a concrete aggregate is still missing.
///
/// The handler requirements are derived from the generated
/// `_$<Aggregate>EventHandlers` mixin.
final class ContinuumRequiredApplyHandlers {
  /// Creates a requirement checker for generated continuum apply handlers.
  const ContinuumRequiredApplyHandlers();

  /// Returns the list of missing apply handler method names.
  ///
  /// If the class does not mix in `_$<Aggregate>EventHandlers`, this returns an
  /// empty list.
  List<String> findMissingApplyHandlers(ClassElement classElement) {
    final InterfaceType? eventHandlersMixinType = _findEventHandlersMixinType(classElement);
    if (eventHandlersMixinType == null) {
      return const <String>[];
    }

    final List<String> requiredApplyMethodNames = eventHandlersMixinType.element.methods
        .where((MethodElement method) => method.isAbstract)
        .map((MethodElement method) => method.displayName)
        .where((String methodName) => methodName.startsWith('apply'))
        .toList(growable: false);

    if (requiredApplyMethodNames.isEmpty) {
      return const <String>[];
    }

    final List<String> missing = <String>[];

    for (final String requiredMethodName in requiredApplyMethodNames) {
      final MethodElement? concreteImplementation = _findConcreteMethodImplementation(classElement, requiredMethodName);

      if (concreteImplementation == null) {
        missing.add(requiredMethodName);
      }
    }

    return missing;
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
