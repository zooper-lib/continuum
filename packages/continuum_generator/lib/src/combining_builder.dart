import 'dart:async';

import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:source_gen/source_gen.dart';

import 'projection_discovery.dart';

const List<String> _generatedDartFileSuffixesToIgnore = <String>[
  '.freezed.dart',
  '.g.dart',
  '.mocks.dart',
];

/// A builder that combines all discovered aggregates and projections into a single file.
///
/// This builder runs after all per-aggregate and per-projection generators have completed.
/// It scans the entire package for discoverable operation targets and `@Projection()` annotations and generates
/// a single `lib/continuum.g.dart` file containing `$targetList` (and the deprecated `$aggregateList` alias), `$projectionList`,
/// and a `registerAll` extension method on [ProjectionRegistry].
class CombiningBuilder implements Builder {
  /// Type checker for bounded's AggregateRoot base class.
  static const _aggregateRootChecker = TypeChecker.fromUrl('package:bounded/src/aggregate_root.dart#AggregateRoot');

  /// Type checker for the @OperationTarget annotation.
  static const _operationTargetChecker = TypeChecker.fromUrl('package:continuum/src/annotations/operation_target.dart#OperationTarget');

  /// Discovery for extracting full projection metadata.
  final _projectionDiscovery = ProjectionDiscovery();

  @override
  Map<String, List<String>> get buildExtensions => {
    r'$lib$': ['continuum.g.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    // Find all Dart files in lib/
    final dartFiles = Glob('lib/**.dart');
    final aggregateInfos = <_DiscoveredInfo>[];
    final projectionDetailInfos = <_ProjectionDetailInfo>[];

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

      // Find all classes assignable to AggregateRoot.
      for (final element in library.classes) {
        if (_aggregateRootChecker.isAssignableFrom(element) || _operationTargetChecker.hasAnnotationOf(element)) {
          aggregateInfos.add(
            _DiscoveredInfo(
              className: element.displayName,
              importPath: importPath,
            ),
          );
        }
      }

      // Discover projections with full type information for registerAll emission.
      final projections = _projectionDiscovery.discoverProjections(library);
      for (final projection in projections) {
        // Collect import URIs for the read model type and key type so the
        // generated file can reference them in registerAll parameters.
        final readModelImportPath = _getImportPathForType(
          projection.readModelType,
          buildStep.inputId.package,
        );
        final keyImportPath = _getImportPathForType(
          projection.keyType,
          buildStep.inputId.package,
        );

        projectionDetailInfos.add(
          _ProjectionDetailInfo(
            className: projection.className,
            importPath: importPath,
            readModelTypeName: projection.readModelTypeName,
            keyTypeName: projection.keyTypeName ?? 'StreamId',
            isSingleStream: projection.isSingleStream,
            lifecycle: projection.lifecycle,
            readModelImportPath: readModelImportPath,
            keyImportPath: keyImportPath,
          ),
        );
      }
    }

    // Skip if neither aggregates nor projections found.
    if (aggregateInfos.isEmpty && projectionDetailInfos.isEmpty) return;

    // Sort for deterministic output.
    aggregateInfos.sort((a, b) => a.className.compareTo(b.className));
    projectionDetailInfos.sort((a, b) => a.className.compareTo(b.className));

    // Collect unique import paths from all sources.
    final allImportPaths = <String>{
      ...aggregateInfos.map((i) => i.importPath),
      ...projectionDetailInfos.map((i) => i.importPath),
      // Add type import paths needed for registerAll parameter types.
      ...projectionDetailInfos.map((i) => i.readModelImportPath).whereType<String>(),
      ...projectionDetailInfos.map((i) => i.keyImportPath).whereType<String>(),
    }.toList()..sort();

    // Generate the combining file.
    final buffer = StringBuffer();

    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln();
    buffer.writeln('// ignore_for_file: type=lint');
    buffer.writeln();
    buffer.writeln("import 'package:continuum/continuum.dart';");

    // Import continuum_uow when projections exist — needed for the generated
    // $createInlineProjectionHandler function and CommitHandler return type.
    if (projectionDetailInfos.isNotEmpty) {
      buffer.writeln("import 'package:continuum_uow/continuum_uow.dart';");
    }

    buffer.writeln();

    // Generate imports for each discovered file.
    for (final importPath in allImportPaths) {
      buffer.writeln("import '$importPath';");
    }

    buffer.writeln();

    // Generate $targetList if any targets found.
    if (aggregateInfos.isNotEmpty) {
      buffer.writeln('/// All discovered operation targets in this package.');
      buffer.writeln('///');
      buffer.writeln('/// Pass this list to [EventSourcingStore] for automatic');
      buffer.writeln('/// registration of all serializers, factories, and appliers.');
      buffer.writeln('final List<GeneratedAggregate> \$targetList = [');

      for (final info in aggregateInfos) {
        buffer.writeln('  \$${info.className},');
      }

      buffer.writeln('];');
      buffer.writeln();

      buffer.writeln('/// Backward-compatible alias for [\$targetList].');
      buffer.writeln('///');
      buffer.writeln('/// This package historically exposed discovered targets as `\$aggregateList`.');
      // Use a raw string literal so `$targetList` is not treated as string
      // interpolation by the Dart compiler.
      // Emit the `$` via `${'\$'}` so the generator does not try to interpolate.
      buffer.writeln("@Deprecated(r'Use ${'\$'}targetList instead.')");
      buffer.writeln('final List<GeneratedAggregate> \$aggregateList = \$targetList;');
      buffer.writeln();
    }

    // Generate $projectionList if any projections found.
    if (projectionDetailInfos.isNotEmpty) {
      buffer.writeln('/// All discovered projections in this package.');
      buffer.writeln('///');
      buffer.writeln('/// Use this list to register all projections with the registry,');
      buffer.writeln('/// or use the generated [ProjectionRegistryExtensions.registerAll] method.');
      buffer.writeln('final List<GeneratedProjection> \$projectionList = [');

      for (final info in projectionDetailInfos) {
        buffer.writeln('  \$${info.className},');
      }

      buffer.writeln('];');
      buffer.writeln();

      // Emit registerAll extension on ProjectionRegistry.
      _emitRegisterAllExtension(buffer, projectionDetailInfos);

      // Emit $createInlineProjectionHandler convenience function
      // that collapses registry + executor + handler into one call.
      final inlineProjections = projectionDetailInfos.where((p) => p.lifecycle == 'inline').toList();
      if (inlineProjections.isNotEmpty) {
        buffer.writeln();
        _emitCreateInlineProjectionHandler(buffer, inlineProjections);
      }
    }

    // Write the output.
    final outputId = AssetId(
      buildStep.inputId.package,
      'lib/continuum.g.dart',
    );

    await buildStep.writeAsString(outputId, buffer.toString());
  }

  /// Emits the `registerAll` extension method on [ProjectionRegistry].
  ///
  /// For each discovered projection, generates a named parameter pair
  /// (projection instance + store) and calls the appropriate registration
  /// method based on lifecycle.
  void _emitRegisterAllExtension(
    StringBuffer buffer,
    List<_ProjectionDetailInfo> projections,
  ) {
    buffer.writeln('/// Generated registration extension for all discovered projections.');
    buffer.writeln('///');
    buffer.writeln('/// Registers all projections in a single call with named parameters');
    buffer.writeln('/// for each projection instance and its corresponding store.');
    buffer.writeln('extension \$ProjectionRegistryExtensions on ProjectionRegistry {');
    buffer.writeln('  /// Registers all discovered projections with their stores.');
    buffer.writeln('  ///');
    buffer.writeln('  /// Each projection is registered with the correct lifecycle');
    buffer.writeln('  /// (inline or async) and its generated [GeneratedProjection] bundle.');
    buffer.writeln('  void registerAll({');

    // Emit named parameters for each projection.
    for (final info in projections) {
      final paramBaseName = _toParameterBaseName(info.className);
      final projectionParamName = '${paramBaseName}Projection';
      final storeParamName = '${paramBaseName}Store';

      buffer.writeln('    required ${info.className} $projectionParamName,');
      buffer.writeln('    required ReadModelStore<${info.readModelTypeName}, ${info.keyTypeName}> $storeParamName,');
    }

    buffer.writeln('  }) {');

    // Emit registration calls for each projection.
    for (final info in projections) {
      final paramBaseName = _toParameterBaseName(info.className);
      final projectionParamName = '${paramBaseName}Projection';
      final storeParamName = '${paramBaseName}Store';
      final bundleName = '\$${info.className}';
      final registerMethod = info.lifecycle == 'async' ? 'registerGeneratedAsync' : 'registerGeneratedInline';

      buffer.writeln('    $registerMethod(');
      buffer.writeln('      $bundleName,');
      buffer.writeln('      $projectionParamName,');
      buffer.writeln('      $storeParamName,');
      buffer.writeln('    );');
    }

    buffer.writeln('  }');
    buffer.writeln('}');
  }

  /// Emits a top-level convenience function that creates a ready-to-use
  /// [CommitHandler] for inline projections.
  ///
  /// This collapses the entire wiring pipeline (registry → executor →
  /// handler) into a single call, so users can write:
  /// ```dart
  /// final runner = TransactionalRunner(
  ///   store: store,
  ///   commitHandler: $createInlineProjectionHandler(
  ///     userProfileProjection: UserProfileProjection(),
  ///     userProfileStore: profileStore,
  ///   ),
  /// );
  /// ```
  void _emitCreateInlineProjectionHandler(
    StringBuffer buffer,
    List<_ProjectionDetailInfo> inlineProjections,
  ) {
    buffer.writeln('/// Creates a [CommitHandler] that runs all inline projections.');
    buffer.writeln('///');
    buffer.writeln('/// This is the simplest way to wire projections into a');
    buffer.writeln('/// [TransactionalRunner]. Internally creates a [ProjectionRegistry],');
    buffer.writeln('/// registers all inline projections, and wraps them in a');
    buffer.writeln('/// [ProjectionCommitHandler].');
    buffer.writeln('CommitHandler \$createInlineProjectionHandler({');

    for (final info in inlineProjections) {
      final paramBaseName = _toParameterBaseName(info.className);

      buffer.writeln('  required ${info.className} ${paramBaseName}Projection,');
      buffer.writeln('  required ReadModelStore<${info.readModelTypeName}, ${info.keyTypeName}> ${paramBaseName}Store,');
    }

    buffer.writeln('}) {');
    buffer.writeln('  final registry = ProjectionRegistry();');

    for (final info in inlineProjections) {
      final paramBaseName = _toParameterBaseName(info.className);
      final bundleName = '\$${info.className}';

      buffer.writeln('  registry.registerGeneratedInline(');
      buffer.writeln('    $bundleName,');
      buffer.writeln('    ${paramBaseName}Projection,');
      buffer.writeln('    ${paramBaseName}Store,');
      buffer.writeln('  );');
    }

    buffer.writeln('  return ProjectionCommitHandler(InlineProjectionExecutor(registry: registry));');
    buffer.writeln('}');
  }

  /// Converts a class name to a parameter base name by lowercasing the first
  /// character and stripping the `Projection` suffix if present.
  ///
  /// `UserProfileProjection` → `userProfile`
  /// `OrderSummary` → `orderSummary`
  String _toParameterBaseName(String className) {
    // Strip "Projection" suffix if present.
    var base = className;
    if (base.endsWith('Projection')) {
      base = base.substring(0, base.length - 'Projection'.length);
    }

    // Lowercase the first character.
    return base[0].toLowerCase() + base.substring(1);
  }

  /// Returns a relative or package import path for a [DartType], or `null`
  /// if the type needs no additional import (dart:core, continuum package, etc.).
  String? _getImportPathForType(DartType? type, String currentPackage) {
    if (type == null) return null;

    final element = type.element;
    if (element == null) return null;

    final library = element.library;
    if (library == null) return null;

    final uri = library.uri;

    // Skip dart:core types (int, String, bool, etc.).
    if (uri.scheme == 'dart') return null;

    if (uri.scheme == 'package') {
      final packageName = uri.pathSegments.first;

      // Skip types from the continuum package — already imported.
      if (packageName == 'continuum') return null;

      // Same package — use a relative import (consistent with other imports).
      if (packageName == currentPackage) {
        return uri.pathSegments.skip(1).join('/');
      }

      // External package — use the full package: URI.
      return uri.toString();
    }

    return null;
  }
}

/// Internal info about a discovered aggregate.
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

/// Internal info about a discovered projection with full type metadata.
///
/// Carries the additional read model type, key type, and lifecycle
/// information needed to emit the `registerAll` extension.
class _ProjectionDetailInfo {
  /// The class name.
  final String className;

  /// The import path relative to lib/ for the file containing this projection.
  final String importPath;

  /// The read model type name (e.g., `UserProfile`).
  final String readModelTypeName;

  /// The key type name (e.g., `StreamId` for single-stream, `CustomerId` for multi-stream).
  final String keyTypeName;

  /// Whether this is a single-stream projection.
  final bool isSingleStream;

  /// The lifecycle (`'inline'` or `'async'`).
  final String lifecycle;

  /// Import path for the read model type, or `null` if no additional import needed.
  final String? readModelImportPath;

  /// Import path for the key type, or `null` if no additional import needed.
  final String? keyImportPath;

  /// Creates projection detail info.
  _ProjectionDetailInfo({
    required this.className,
    required this.importPath,
    required this.readModelTypeName,
    required this.keyTypeName,
    required this.isSingleStream,
    required this.lifecycle,
    this.readModelImportPath,
    this.keyImportPath,
  });
}
