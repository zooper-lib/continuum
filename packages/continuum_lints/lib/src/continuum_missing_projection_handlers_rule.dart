import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'continuum_implement_missing_projection_handlers_fix.dart';
import 'continuum_required_projection_handlers.dart';

/// Reports when a non-abstract `@Projection()` class is missing required
/// `apply<Event>(...)` handlers declared by the generated
/// `_$<Projection>Handlers` mixin.
///
/// Why this exists:
/// - Dart allows classes to become *implicitly abstract* when they do not
///   implement interface members.
/// - That means missing handlers may not surface as a compile error until the
///   class is instantiated.
/// - This lint surfaces the problem immediately in the editor.
final class ContinuumMissingProjectionHandlersRule extends DartLintRule {
  static const LintCode _lintCode = LintCode(
    name: 'continuum_missing_projection_handlers',
    problemMessage: 'This @Projection() class mixes in generated handlers but is missing methods: {0}.',
    correctionMessage: 'Implement the missing createInitial() and apply<Event>(...) methods.',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  static final TypeChecker _projectionChecker = const TypeChecker.fromUrl(
    'package:continuum/src/annotations/projection.dart#Projection',
  );

  /// Creates the lint rule.
  const ContinuumMissingProjectionHandlersRule() : super(code: _lintCode);

  @override
  List<Fix> getFixes() {
    return <Fix>[ContinuumImplementMissingProjectionHandlersFix()];
  }

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addClassDeclaration((ClassDeclaration node) {
      final ClassElement? classElement = node.declaredFragment?.element;
      if (classElement == null) return;

      // Only check @Projection annotated classes.
      if (!_projectionChecker.hasAnnotationOf(classElement)) return;

      // If the user explicitly made the class abstract, they can defer handler
      // implementations to concrete subtypes.
      if (node.abstractKeyword != null) return;

      final List<String> missingHandlers = const ContinuumRequiredProjectionHandlers().findMissingProjectionHandlers(classElement);

      if (missingHandlers.isEmpty) return;

      reporter.atElement2(
        classElement,
        _lintCode,
        arguments: <String>[missingHandlers.join(', ')],
      );
    });
  }
}
