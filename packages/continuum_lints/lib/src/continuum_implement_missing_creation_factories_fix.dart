import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_dart.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'continuum_required_creation_factories.dart';

/// Quick-fix that inserts stub implementations for missing
/// `static createFrom<Event>(Event event)` creation factories required by
/// creation events.
final class ContinuumImplementMissingCreationFactoriesFix extends DartFix {
  static final Object _resolvedUnitKey = Object();

  /// Unique ID for this fix (used for batching).
  static const String fixId = 'continuum_implement_missing_creation_factories';

  /// The lint code this fix targets.
  static const String _targetLintCodeName = 'continuum_missing_creation_factories';

  /// Creates a quick-fix that implements missing creation factories.
  ContinuumImplementMissingCreationFactoriesFix();

  @override
  Future<void> startUp(CustomLintResolver resolver, CustomLintContext context) async {
    // WHY: We need access to the resolved compilation unit to locate the class
    // and compute indentation/insertion offsets for edits.
    context.sharedState[_resolvedUnitKey] = await resolver.getResolvedUnitResult();
  }

  @override
  String get id => fixId;

  @override
  void run(
    CustomLintResolver resolver,
    ChangeReporter reporter,
    CustomLintContext context,
    Diagnostic analysisError,
    List<Diagnostic> others,
  ) {
    if (analysisError.diagnosticCode.name != _targetLintCodeName) return;

    final ResolvedUnitResult? unitResult = context.sharedState[_resolvedUnitKey] as ResolvedUnitResult?;
    if (unitResult == null) return;

    final ClassDeclaration? classDeclaration = _enclosingClassDeclaration(
      unitResult.unit,
      analysisError.offset,
    );

    if (classDeclaration == null) return;

    final ClassElement? classElement = classDeclaration.declaredFragment?.element;
    if (classElement == null) return;

    final List<CreationFactorySpec> missingFactories = const ContinuumRequiredCreationFactories().findMissingCreationFactorySpecs(classElement);
    if (missingFactories.isEmpty) return;

    final int insertionOffset = classDeclaration.rightBracket.offset;

    final String classIndent = _indentForLineAtOffset(
      unitResult.content,
      unitResult.lineInfo.getOffsetOfLine(
        unitResult.lineInfo.getLocation(classDeclaration.offset).lineNumber - 1,
      ),
    );

    final String memberIndent = '$classIndent  ';

    final StringBuffer buffer = StringBuffer();

    for (final CreationFactorySpec factory in missingFactories) {
      buffer.write(
        _renderStubFactory(
          aggregateName: classElement.displayName,
          methodName: factory.methodName,
          eventTypeName: factory.eventTypeName,
          indent: memberIndent,
        ),
      );
    }

    final ChangeBuilder changeBuilder = reporter.createChangeBuilder(
      message: 'Implement missing creation factories',
      priority: 0,
    );

    changeBuilder.addDartFileEdit((DartFileEditBuilder builder) {
      builder.addSimpleInsertion(insertionOffset, buffer.toString());
    });
  }

  ClassDeclaration? _enclosingClassDeclaration(CompilationUnit unit, int offset) {
    for (final CompilationUnitMember declaration in unit.declarations) {
      if (declaration is! ClassDeclaration) continue;

      if (declaration.offset <= offset && offset <= declaration.end) {
        return declaration;
      }
    }

    return null;
  }

  String _indentForLineAtOffset(String source, int lineStartOffset) {
    final int lineEndOffset = source.indexOf('\n', lineStartOffset);

    final String line = lineEndOffset == -1 ? source.substring(lineStartOffset) : source.substring(lineStartOffset, lineEndOffset);

    final int firstNonWhitespace = line.indexOf(RegExp(r'\S'));
    if (firstNonWhitespace == -1) return '';

    return line.substring(0, firstNonWhitespace);
  }

  String _renderStubFactory({
    required String aggregateName,
    required String methodName,
    required String eventTypeName,
    required String indent,
  }) {
    final StringBuffer buffer = StringBuffer();

    buffer.write('\n');
    buffer.write('$indent/// Creates a $aggregateName from a $eventTypeName.\n');
    buffer.write('${indent}static $aggregateName $methodName($eventTypeName event) {\n');
    buffer.write('$indent  throw UnimplementedError();\n');
    buffer.write('$indent}\n');

    return buffer.toString();
  }
}
