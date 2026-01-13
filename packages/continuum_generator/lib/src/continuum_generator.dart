import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:source_gen/source_gen.dart';

import 'aggregate_discovery.dart';
import 'code_emitter.dart';

/// Generator for continuum event sourcing code.
///
/// Scans for @Aggregate and @Event annotations and generates:
/// - Event handler mixins for mutation events
/// - Apply dispatchers and replay helpers
/// - Creation dispatchers for aggregate instantiation
/// - Event registry for persistence deserialization
class ContinuumGenerator extends Generator {
  static const List<String> _generatedDartFileSuffixesToIgnore = <String>[
    '.freezed.dart',
    '.g.dart',
    '.mocks.dart',
  ];

  final _discovery = AggregateDiscovery();
  final _emitter = CodeEmitter();

  @override
  FutureOr<String?> generate(LibraryReader library, BuildStep buildStep) async {
    // First: discover whether this library defines any aggregates.
    final localAggregates = _discovery.discoverAggregates(library.element);

    // Skip if no aggregates found
    if (localAggregates.isEmpty) {
      return null;
    }

    // Then: collect all libraries in the current package so we can discover
    // events annotated as belonging to these aggregates, even when the aggregate
    // library doesn't import the event library.
    final candidateEventLibraries = await _collectPackageLibrariesAsync(buildStep);

    // Re-run discovery with the wider candidate set.
    final aggregates = _discovery.discoverAggregates(
      library.element,
      candidateEventLibraries: candidateEventLibraries,
    );

    // Generate code for all aggregates
    final output = _emitter.emit(aggregates);

    // Return the generated code directly.
    // Note: Part files inherit imports from the main library file,
    // so no explicit imports are needed here.
    return output;
  }

  /// Collects all resolvable Dart libraries in the current package.
  ///
  /// This supports package-wide event discovery while still generating code per
  /// aggregate library.
  Future<List<LibraryElement>> _collectPackageLibrariesAsync(BuildStep buildStep) async {
    final dartFiles = Glob('lib/**.dart');
    final libraries = <LibraryElement>[];

    await for (final input in buildStep.findAssets(dartFiles)) {
      if (input.package != buildStep.inputId.package) continue;
      if (_generatedDartFileSuffixesToIgnore.any(input.path.endsWith)) continue;
      if (!await buildStep.resolver.isLibrary(input)) continue;

      final candidateLibrary = await buildStep.resolver.libraryFor(input);
      libraries.add(candidateLibrary);
    }

    return libraries;
  }
}
