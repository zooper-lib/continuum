import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_dart.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'continuum_required_projection_handlers.dart';

/// Quick-fix that inserts stub implementations for missing `apply<Event>(...)`
/// and `createInitial()` handlers required by the generated
/// `_$<Projection>Handlers` mixin.
final class ContinuumImplementMissingProjectionHandlersFix extends DartFix {
  static final Object _resolvedUnitKey = Object();

  /// Unique ID for this fix (used for batching).
  static const String fixId = 'continuum_implement_missing_projection_handlers';

  /// The lint code this fix targets.
  static const String _targetLintCodeName = 'continuum_missing_projection_handlers';

  /// Creates a quick-fix that implements missing projection handlers.
  ContinuumImplementMissingProjectionHandlersFix();

  @override
  Future<void> startUp(
    CustomLintResolver resolver,
    CustomLintContext context,
  ) async {
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

    final List<MethodElement> missingMethods = const ContinuumRequiredProjectionHandlers().findMissingProjectionHandlerMethods(classElement);
    if (missingMethods.isEmpty) return;

    final int insertionOffset = classDeclaration.rightBracket.offset;

    final String classIndent = _indentForLineAtOffset(
      unitResult.content,
      unitResult.lineInfo.getOffsetOfLine(
        unitResult.lineInfo.getLocation(classDeclaration.offset).lineNumber - 1,
      ),
    );

    final String memberIndent = '$classIndent  ';

    final StringBuffer buffer = StringBuffer();

    for (final MethodElement method in missingMethods) {
      buffer.write(_renderStubMethod(method, memberIndent));
    }

    final ChangeBuilder changeBuilder = reporter.createChangeBuilder(
      message: 'Implement missing projection handlers',
      priority: 0,
    );

    changeBuilder.addDartFileEdit((DartFileEditBuilder builder) {
      builder.addSimpleInsertion(insertionOffset, buffer.toString());
    });
  }

  /// Finds the class declaration containing the given offset.
  ClassDeclaration? _enclosingClassDeclaration(
    CompilationUnit unit,
    int offset,
  ) {
    for (final CompilationUnitMember declaration in unit.declarations) {
      if (declaration is! ClassDeclaration) continue;

      if (declaration.offset <= offset && offset <= declaration.end) {
        return declaration;
      }
    }

    return null;
  }

  /// Extracts the indentation string for a line at the given offset.
  String _indentForLineAtOffset(String source, int lineStartOffset) {
    final int lineEndOffset = source.indexOf('\n', lineStartOffset);

    final String line = lineEndOffset == -1 ? source.substring(lineStartOffset) : source.substring(lineStartOffset, lineEndOffset);

    final int firstNonWhitespace = line.indexOf(RegExp(r'\S'));
    if (firstNonWhitespace == -1) return '';

    return line.substring(0, firstNonWhitespace);
  }

  /// Renders a stub method implementation.
  String _renderStubMethod(MethodElement method, String indent) {
    final String returnType = method.returnType.getDisplayString();
    final String name = method.displayName;

    final _ParameterGroups parameters = _renderParameters(method.formalParameters);

    final StringBuffer buffer = StringBuffer();

    buffer.write('\n');
    buffer.write('$indent@override\n');
    buffer.write('$indent$returnType $name(');
    buffer.write(parameters.positional);

    if (parameters.positional.isNotEmpty && (parameters.optionalPositional.isNotEmpty || parameters.named.isNotEmpty)) {
      buffer.write(', ');
    }

    if (parameters.optionalPositional.isNotEmpty) {
      buffer.write('[${parameters.optionalPositional}]');

      if (parameters.named.isNotEmpty) {
        buffer.write(', ');
      }
    }

    if (parameters.named.isNotEmpty) {
      buffer.write('{${parameters.named}}');
    }

    buffer.write(') {\n');
    buffer.write('$indent  // TODO: Implement handler\n');
    buffer.write('$indent  throw UnimplementedError();\n');
    buffer.write('$indent}\n');

    return buffer.toString();
  }

  /// Groups parameters by kind for rendering.
  _ParameterGroups _renderParameters(List<FormalParameterElement> parameters) {
    final List<String> positional = <String>[];
    final List<String> optionalPositional = <String>[];
    final List<String> named = <String>[];

    for (final FormalParameterElement parameter in parameters) {
      final String type = parameter.type.getDisplayString();
      final String name = parameter.displayName;

      final String parameterString;
      if (parameter.isRequiredNamed) {
        parameterString = 'required $type $name';
      } else {
        parameterString = '$type $name';
      }

      if (parameter.isNamed) {
        named.add(parameterString);
      } else if (parameter.isOptionalPositional) {
        optionalPositional.add(parameterString);
      } else {
        positional.add(parameterString);
      }
    }

    return _ParameterGroups(
      positional: positional.join(', '),
      optionalPositional: optionalPositional.join(', '),
      named: named.join(', '),
    );
  }
}

/// Groups of parameters by kind.
final class _ParameterGroups {
  /// Creates parameter groups.
  const _ParameterGroups({
    required this.positional,
    required this.optionalPositional,
    required this.named,
  });

  /// Positional parameters as a comma-separated string.
  final String positional;

  /// Optional positional parameters as a comma-separated string.
  final String optionalPositional;

  /// Named parameters as a comma-separated string.
  final String named;
}
