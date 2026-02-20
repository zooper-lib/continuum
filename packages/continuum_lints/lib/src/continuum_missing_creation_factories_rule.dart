import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'continuum_implement_missing_creation_factories_fix.dart';
import 'continuum_required_creation_factories.dart';

/// Reports when an operation target is missing one or more required
/// `createFrom<Operation>(Operation operation)` creation factory methods for
/// its creation operations.
///
/// Why this exists:
/// - Creation classification is explicit via `@OperationFor(creation: true)`.
/// - Legacy projects may still use `@AggregateEvent(creation: true)`.
/// - When a creation operation exists but the factory method is missing, the
///   generator will fail, but this lint surfaces the issue immediately in the
///   editor.
final class ContinuumMissingCreationFactoriesRule extends DartLintRule {
  static const LintCode _lintCode = LintCode(
    name: 'continuum_missing_creation_factories',
    problemMessage: 'This operation target is missing required creation factories: {0}.',
    correctionMessage: 'Add the missing static createFrom<Event>(Event event) factory methods.',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  static final TypeChecker _aggregateRootChecker = const TypeChecker.fromUrl('package:bounded/src/aggregate_root.dart#AggregateRoot');
  static final TypeChecker _operationTargetChecker = const TypeChecker.fromUrl(
    'package:continuum/src/annotations/operation_target.dart#OperationTarget',
  );

  const ContinuumMissingCreationFactoriesRule() : super(code: _lintCode);

  @override
  List<Fix> getFixes() {
    return <Fix>[ContinuumImplementMissingCreationFactoriesFix()];
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

      final bool isTarget = _aggregateRootChecker.isAssignableFrom(classElement) || _operationTargetChecker.hasAnnotationOf(classElement);
      if (!isTarget) return;

      final List<String> missingFactories = const ContinuumRequiredCreationFactories().findMissingCreationFactories(classElement);
      if (missingFactories.isEmpty) return;

      reporter.atElement2(
        classElement,
        _lintCode,
        arguments: <String>[missingFactories.join(', ')],
      );
    });
  }
}
