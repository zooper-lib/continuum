import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/continuum_generator.dart';

/// Creates the Continuum builder for build_runner.
Builder continuumBuilder(BuilderOptions options) =>
    SharedPartBuilder([ContinuumGenerator()], 'continuum');
