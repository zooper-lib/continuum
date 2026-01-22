import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

/// Computes which `apply...` handlers a concrete projection is still missing.
///
/// The handler requirements are derived from the generated
/// `_$<Projection>Handlers` mixin.
final class ContinuumRequiredProjectionHandlers {
  static final TypeChecker _projectionChecker = const TypeChecker.fromUrl(
    'package:continuum/src/annotations/projection.dart#Projection',
  );

  /// Creates a requirement checker for generated continuum projection handlers.
  const ContinuumRequiredProjectionHandlers();

  /// Returns the list of missing projection handler method names.
  ///
  /// If the class does not mix in `_$<Projection>Handlers`, this returns an
  /// empty list.
  List<String> findMissingProjectionHandlers(ClassElement classElement) {
    final List<MethodElement> missingMethods = findMissingProjectionHandlerMethods(classElement);

    return missingMethods.map((MethodElement method) => method.displayName).toList(growable: false);
  }

  /// Returns the list of missing projection handler method elements.
  ///
  /// This is useful for generating method stubs in quick-fixes.
  ///
  /// If the class does not mix in `_$<Projection>Handlers`, this returns an
  /// empty list.
  List<MethodElement> findMissingProjectionHandlerMethods(
    ClassElement classElement,
  ) {
    // First verify this is a @Projection annotated class.
    if (!_projectionChecker.hasAnnotationOf(classElement)) {
      return const <MethodElement>[];
    }

    final InterfaceType? handlersMixinType = _findHandlersMixinType(classElement);
    if (handlersMixinType == null) {
      return const <MethodElement>[];
    }

    // Find all required abstract methods from the mixin.
    // These include createInitial and apply<EventName> methods.
    final List<MethodElement> requiredMethods = handlersMixinType.element.methods.where((MethodElement method) => method.isAbstract).toList(growable: false);

    if (requiredMethods.isEmpty) {
      return const <MethodElement>[];
    }

    final List<MethodElement> missing = <MethodElement>[];

    for (final MethodElement requiredMethod in requiredMethods) {
      final MethodElement? concreteImplementation = _findConcreteMethodImplementation(
        classElement,
        requiredMethod.displayName,
      );
      if (concreteImplementation == null) {
        missing.add(requiredMethod);
      }
    }

    return missing;
  }

  /// Finds the `_$<Projection>Handlers` mixin type in the class's mixins.
  InterfaceType? _findHandlersMixinType(ClassElement classElement) {
    final String className = classElement.displayName;
    final String expectedMixinName = '_\$${className}Handlers';

    for (final InterfaceType mixinType in classElement.mixins) {
      if (mixinType.element.name == expectedMixinName) {
        return mixinType;
      }
    }

    return null;
  }

  /// Finds a concrete method implementation in the class hierarchy.
  MethodElement? _findConcreteMethodImplementation(
    ClassElement classElement,
    String methodName,
  ) {
    // Check the class itself first.
    for (final MethodElement method in classElement.methods) {
      if (method.displayName == methodName && !method.isAbstract) {
        return method;
      }
    }

    // Check superclasses (but not mixins, since we want user implementations).
    final InterfaceType? supertype = classElement.supertype;
    if (supertype != null && supertype.element is ClassElement) {
      return _findConcreteMethodImplementation(
        supertype.element as ClassElement,
        methodName,
      );
    }

    return null;
  }
}
