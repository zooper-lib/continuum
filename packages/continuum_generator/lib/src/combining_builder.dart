import 'dart:async';

import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:source_gen/source_gen.dart';

const List<String> _generatedDartFileSuffixesToIgnore = <String>[
  '.freezed.dart',
  '.g.dart',
  '.mocks.dart',
];

/// A builder that combines all discovered aggregates and projections into a single file.
///
/// This builder runs after all per-aggregate and per-projection generators have completed.
/// It scans the entire package for `@Aggregate()` and `@Projection()` annotations and generates
/// a single `lib/continuum.g.dart` file containing `$aggregateList` and `$projectionList`.
///
/// Users can then simply write:
/// ```dart
/// import 'continuum.g.dart';
///
/// final store = EventSourcingStore(
///   eventStore: InMemoryEventStore(),
///   aggregates: $aggregateList,
/// );
///
/// for (final projection in $projectionList) {
///   registry.registerGeneratedInline(projection, ...);
/// }
/// ```
class CombiningBuilder implements Builder {
  /// Type checker for the @Aggregate annotation.
  static const _aggregateChecker = TypeChecker.fromUrl('package:continuum/src/annotations/aggregate.dart#Aggregate');

  /// Type checker for the @Projection annotation.
  static const _projectionChecker = TypeChecker.fromUrl('package:continuum/src/annotations/projection.dart#Projection');

  @override
  Map<String, List<String>> get buildExtensions => {
    r'$lib$': ['continuum.g.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    // Find all Dart files in lib/
    final dartFiles = Glob('lib/**.dart');
    final aggregateInfos = <_DiscoveredInfo>[];
    final projectionInfos = <_DiscoveredInfo>[];

    await for (final input in buildStep.findAssets(dartFiles)) {
      // Skip generated files to avoid cycles and non-library `part of` files.
      if (_generatedDartFileSuffixesToIgnore.any(input.path.endsWith)) continue;

      // Some tools (like Freezed) generate `part of` files under `lib/`.
      // Those are not libraries, and `libraryFor(...)` will throw.
      if (!await buildStep.resolver.isLibrary(input)) continue;

      // Try to resolve the library.
      final library = await buildStep.resolver.libraryFor(input);

      // Calculate the import path relative to lib/.
      final importPath = input.path.replaceFirst('lib/', '');

      // Find all classes annotated with @Aggregate.
      for (final element in library.classes) {
        if (_aggregateChecker.hasAnnotationOf(element)) {
          aggregateInfos.add(
            _DiscoveredInfo(
              className: element.displayName,
              importPath: importPath,
            ),
          );
        }
      }

      // Find all classes annotated with @Projection.
      for (final element in library.classes) {
        if (_projectionChecker.hasAnnotationOf(element)) {
          projectionInfos.add(
            _DiscoveredInfo(
              className: element.displayName,
              importPath: importPath,
            ),
          );
        }
      }
    }

    // Skip if neither aggregates nor projections found.
    if (aggregateInfos.isEmpty && projectionInfos.isEmpty) return;

    // Sort for deterministic output.
    aggregateInfos.sort((a, b) => a.className.compareTo(b.className));
    projectionInfos.sort((a, b) => a.className.compareTo(b.className));

    // Collect unique import paths.
    final allImportPaths = <String>{
      ...aggregateInfos.map((i) => i.importPath),
      ...projectionInfos.map((i) => i.importPath),
    }.toList()..sort();

    // Generate the combining file.
    final buffer = StringBuffer();

    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln();
    buffer.writeln('// ignore_for_file: type=lint');
    buffer.writeln();
    buffer.writeln("import 'package:continuum/continuum.dart';");
    buffer.writeln();

    // Generate imports for each discovered file.
    for (final importPath in allImportPaths) {
      buffer.writeln("import '$importPath';");
    }

    buffer.writeln();

    // Generate $aggregateList if any aggregates found.
    if (aggregateInfos.isNotEmpty) {
      buffer.writeln('/// All discovered aggregates in this package.');
      buffer.writeln('///');
      buffer.writeln('/// Pass this list to [EventSourcingStore] for automatic');
      buffer.writeln('/// registration of all serializers, factories, and appliers.');
      buffer.writeln('///');
      buffer.writeln('/// ```dart');
      buffer.writeln('/// final store = EventSourcingStore(');
      buffer.writeln('///   eventStore: InMemoryEventStore(),');
      buffer.writeln('///   aggregates: \$aggregateList,');
      buffer.writeln('/// );');
      buffer.writeln('/// ```');
      buffer.writeln('final List<GeneratedAggregate> \$aggregateList = [');

      for (final info in aggregateInfos) {
        buffer.writeln('  \$${info.className},');
      }

      buffer.writeln('];');
      buffer.writeln();
    }

    // Generate $projectionList if any projections found.
    if (projectionInfos.isNotEmpty) {
      buffer.writeln('/// All discovered projections in this package.');
      buffer.writeln('///');
      buffer.writeln('/// Use this list to register all projections with the registry.');
      buffer.writeln('///');
      buffer.writeln('/// ```dart');
      buffer.writeln('/// for (final bundle in \$projectionList) {');
      buffer.writeln('///   // Register with appropriate lifecycle and store');
      buffer.writeln('/// }');
      buffer.writeln('/// ```');
      buffer.writeln('final List<GeneratedProjection> \$projectionList = [');

      for (final info in projectionInfos) {
        buffer.writeln('  \$${info.className},');
      }

      buffer.writeln('];');
    }

    // Write the output.
    final outputId = AssetId(
      buildStep.inputId.package,
      'lib/continuum.g.dart',
    );

    await buildStep.writeAsString(outputId, buffer.toString());
  }
}

/// Internal info about a discovered aggregate or projection.
class _DiscoveredInfo {
  /// The class name.
  final String className;

  /// The import path relative to lib/.
  final String importPath;

  /// Creates discovered info.
  _DiscoveredInfo({
    required this.className,
    required this.importPath,
  });
}
