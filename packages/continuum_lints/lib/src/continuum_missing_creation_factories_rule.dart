import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart' hide LintCode;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'continuum_implement_missing_creation_factories_fix.dart';
import 'continuum_required_creation_factories.dart';

/// Reports when an aggregate root is missing one or more required
/// `createFrom<Event>(Event event)` creation factory methods for its creation
/// events.
///
/// Why this exists:
/// - Creation event classification is explicit via `@AggregateEvent(creation: true)`.
/// - When a creation event exists but the factory method is missing, the
///   generator will fail, but this lint surfaces the issue immediately in the
///   editor.
final class ContinuumMissingCreationFactoriesRule extends DartLintRule {
  static const LintCode _lintCode = LintCode(
    name: 'continuum_missing_creation_factories',
    problemMessage: 'This aggregate root is missing required creation factories: {0}.',
    correctionMessage: 'Add the missing static createFrom<Event>(Event event) factory methods.',
    errorSeverity: DiagnosticSeverity.WARNING,
  );

  static final TypeChecker _aggregateRootChecker = const TypeChecker.fromUrl('package:bounded/src/aggregate_root.dart#AggregateRoot');

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

      if (!_aggregateRootChecker.isAssignableFrom(classElement)) return;

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
