import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'discovery.dart';
import 'emitter.dart';

/// Generator for continuum event sourcing code.
///
/// Scans for @Aggregate and @Event annotations and generates:
/// - Event handler mixins for mutation events
/// - Apply dispatchers and replay helpers
/// - Creation dispatchers for aggregate instantiation
/// - Event registry for persistence deserialization
class ContinuumGenerator extends Generator {
  final _discovery = AggregateDiscovery();
  final _emitter = CodeEmitter();

  @override
  String? generate(LibraryReader library, BuildStep buildStep) {
    // Discover aggregates and events in this library
    final aggregates = _discovery.discoverAggregates(library.element);

    // Skip if no aggregates found
    if (aggregates.isEmpty) {
      return null;
    }

    // Generate code for all aggregates
    final output = _emitter.emit(aggregates);

    // Return the generated code directly.
    // Note: Part files inherit imports from the main library file,
    // so no explicit imports are needed here.
    return output;
  }
}
