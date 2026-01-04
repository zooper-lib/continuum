import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/combining_builder.dart';
import 'src/continuum_generator.dart';

/// Creates the Continuum builder for build_runner.
///
/// This builder processes individual aggregate files and generates
/// the per-aggregate code (mixins, extensions, GeneratedAggregate bundles).
Builder continuumBuilder(BuilderOptions options) =>
    SharedPartBuilder([ContinuumGenerator()], 'continuum');

/// Creates the Continuum combining builder for build_runner.
///
/// This builder runs after all aggregate files have been processed
/// and generates a single `lib/continuum.g.dart` file containing
/// the `$aggregateList` variable with all discovered aggregates.
Builder continuumCombiningBuilder(BuilderOptions options) => CombiningBuilder();
