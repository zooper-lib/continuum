import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:source_gen/source_gen.dart';

import 'aggregate_discovery.dart';
import 'code_emitter.dart';
import 'projection_code_emitter.dart';
import 'projection_discovery.dart';

/// Generator for continuum event sourcing code.
///
/// Scans for aggregate roots (types extending `bounded.AggregateRoot`) and for
/// `@AggregateEvent` / `@Projection` annotations and generates:
/// - Event handler mixins for mutation events
/// - Apply dispatchers and replay helpers
/// - Creation dispatchers for aggregate instantiation
/// - Event registry for persistence deserialization
/// - Projection handler mixins and dispatchers
/// - Projection bundles for registry configuration
class ContinuumGenerator extends Generator {
  static const List<String> _generatedDartFileSuffixesToIgnore = <String>[
    '.freezed.dart',
    '.g.dart',
    '.mocks.dart',
  ];

  final _aggregateDiscovery = AggregateDiscovery();
  final _aggregateEmitter = CodeEmitter();
  final _projectionDiscovery = ProjectionDiscovery();
  final _projectionEmitter = ProjectionCodeEmitter();

  @override
  FutureOr<String?> generate(LibraryReader library, BuildStep buildStep) async {
    // Discover aggregates and projections in this library.
    final localAggregates = _aggregateDiscovery.discoverAggregates(library.element);
    final projections = _projectionDiscovery.discoverProjections(library.element);

    // Skip if neither aggregates nor projections found.
    if (localAggregates.isEmpty && projections.isEmpty) {
      return null;
    }

    final outputBuffer = StringBuffer();

    // Generate aggregate code if any aggregates found.
    if (localAggregates.isNotEmpty) {
      // Collect all libraries in the current package so we can discover
      // events annotated as belonging to these aggregates, even when the aggregate
      // library doesn't import the event library.
      final candidateEventLibraries = await _collectPackageLibrariesAsync(buildStep);

      // Re-run discovery with the wider candidate set.
      final aggregates = _aggregateDiscovery.discoverAggregates(
        library.element,
        candidateEventLibraries: candidateEventLibraries,
      );

      // Generate code for all aggregates.
      final aggregateOutput = _aggregateEmitter.emit(aggregates);
      outputBuffer.writeln(aggregateOutput);
    }

    // Generate projection code if any projections found.
    if (projections.isNotEmpty) {
      final projectionOutput = _projectionEmitter.emit(projections);
      outputBuffer.writeln(projectionOutput);
    }

    // Return the generated code directly.
    // Note: Part files inherit imports from the main library file,
    // so no explicit imports are needed here.
    return outputBuffer.toString();
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
