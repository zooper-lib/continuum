import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'continuum_required_apply_handlers.dart';

/// Reports when a non-abstract `@Aggregate()` class is missing required
/// `apply<Event>(...)` handlers declared by the generated
/// `_$<Aggregate>EventHandlers` mixin.
///
/// Why this exists:
/// - Dart allows classes to become *implicitly abstract* when they do not
///   implement interface members.
/// - That means missing handlers may not surface as a compile error until the
///   class is instantiated.
/// - This lint surfaces the problem immediately in the editor.
final class ContinuumMissingApplyHandlersRule extends DartLintRule {
  static const LintCode _lintCode = LintCode(
    name: 'continuum_missing_apply_handlers',
    problemMessage: 'This @Aggregate() class mixes in generated event handlers but is missing apply methods: {0}.',
    correctionMessage: 'Implement the missing apply<Event>(...) methods.',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  static final TypeChecker _aggregateChecker = const TypeChecker.fromUrl('package:continuum/src/annotations/aggregate.dart#Aggregate');

  const ContinuumMissingApplyHandlersRule() : super(code: _lintCode);

  @override
  void run(
    CustomLintResolver resolver,
    DiagnosticReporter reporter,
    CustomLintContext context,
  ) {
    context.registry.addClassDeclaration((ClassDeclaration node) {
      final ClassElement? classElement = node.declaredFragment?.element;
      if (classElement == null) return;

      if (!_aggregateChecker.hasAnnotationOf(classElement)) return;

      // If the user explicitly made the class abstract, they can defer handler
      // implementations to concrete subtypes.
      if (node.abstractKeyword != null) return;

      final List<String> missingApplyHandlers = const ContinuumRequiredApplyHandlers().findMissingApplyHandlers(classElement);

      if (missingApplyHandlers.isEmpty) return;

      reporter.atElement2(
        classElement,
        _lintCode,
        arguments: <String>[missingApplyHandlers.join(', ')],
      );
    });
  }
}
