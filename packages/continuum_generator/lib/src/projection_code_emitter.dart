import 'models/projection_info.dart';

/// Generates code for projections.
///
/// Creates event handler mixins, apply dispatchers, and projection bundles
/// for classes annotated with `@Projection`.
final class ProjectionCodeEmitter {
  /// Generates all code for the given projections.
  ///
  /// Returns the combined generated code as a string.
  String emit(List<ProjectionInfo> projections) {
    final buffer = StringBuffer();

    for (final projection in projections) {
      buffer.writeln(_emitHandlersMixin(projection));
      buffer.writeln();
      buffer.writeln(_emitDispatchExtension(projection));
      buffer.writeln();
      buffer.writeln(_emitProjectionBundle(projection));
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Generates the event handlers mixin.
  ///
  /// This mixin provides:
  /// - `handledEventTypes` getter (overrides base class)
  /// - `projectionName` getter (overrides base class)
  /// - `apply()` method that dispatches to typed handlers (overrides base class)
  /// - Abstract `apply<EventName>()` methods for each event type
  String _emitHandlersMixin(ProjectionInfo projection) {
    final buffer = StringBuffer();
    final className = projection.className;
    final readModelType = projection.readModelTypeName;
    final projectionName = projection.projectionName;

    buffer.writeln('/// Generated mixin providing event handling for $className.');
    buffer.writeln('///');
    buffer.writeln('/// This mixin provides the [handledEventTypes], [projectionName], and [apply]');
    buffer.writeln('/// implementations. Implement the abstract `apply<EventName>` methods.');
    buffer.writeln('mixin _\$${className}Handlers {');

    // Generate handledEventTypes getter.
    buffer.writeln('  /// The set of event types this projection handles.');
    buffer.writeln('  Set<Type> get handledEventTypes => const {');
    for (final eventTypeName in projection.eventTypeNames) {
      buffer.writeln('    $eventTypeName,');
    }
    buffer.writeln('  };');
    buffer.writeln();

    // Generate projectionName getter.
    buffer.writeln('  /// The unique name identifying this projection.');
    buffer.writeln("  String get projectionName => '$projectionName';");
    buffer.writeln();

    // Generate apply method that dispatches to typed handlers.
    buffer.writeln('  /// Applies an operation to update the read model.');
    buffer.writeln('  ///');
    buffer.writeln('  /// Routes the operation to the appropriate typed handler method.');
    buffer.writeln('  /// Throws [UnsupportedProjectionOperationException] for unknown operation types.');
    buffer.writeln('  $readModelType apply($readModelType current, Operation operation) {');
    buffer.writeln('    return switch (operation) {');
    for (final eventTypeName in projection.eventTypeNames) {
      buffer.writeln('      $eventTypeName() => apply$eventTypeName(current, operation),');
    }
    buffer.writeln('      _ => throw UnsupportedProjectionOperationException(');
    buffer.writeln('            operationType: operation.runtimeType,');
    buffer.writeln('            projectionType: $className,');
    buffer.writeln('          ),');
    buffer.writeln('    };');
    buffer.writeln('  }');
    buffer.writeln();

    // Generate abstract apply methods for each event type.
    for (final eventTypeName in projection.eventTypeNames) {
      buffer.writeln('  /// Applies a $eventTypeName event to the read model.');
      buffer.writeln('  $readModelType apply$eventTypeName($readModelType current, $eventTypeName event);');
      buffer.writeln();
    }

    buffer.writeln('}');

    return buffer.toString();
  }

  /// Generates the dispatch extension for event routing.
  ///
  /// Provides `applyEvent()` for convenient routing from domain events.
  String _emitDispatchExtension(ProjectionInfo projection) {
    final buffer = StringBuffer();
    final className = projection.className;
    final readModelType = projection.readModelTypeName;

    buffer.writeln('/// Generated extension providing additional operation dispatch for $className.');
    buffer.writeln('extension \$${className}EventDispatch on $className {');

    // Generate applyEvent dispatcher for Operation (convenience method).
    buffer.writeln('  /// Routes an operation to the appropriate apply method.');
    buffer.writeln('  ///');
    buffer.writeln('  /// This is a convenience method for applying operations directly.');
    buffer.writeln('  ///');
    buffer.writeln('  /// Throws [UnsupportedProjectionOperationException] for unknown operation types.');
    buffer.writeln('  $readModelType applyEvent($readModelType current, Operation operation) {');
    buffer.writeln('    return switch (operation) {');

    for (final eventTypeName in projection.eventTypeNames) {
      buffer.writeln('      $eventTypeName() => apply$eventTypeName(current, operation),');
    }

    buffer.writeln('      _ => throw UnsupportedProjectionOperationException(');
    buffer.writeln('            operationType: operation.runtimeType,');
    buffer.writeln('            projectionType: $className,');
    buffer.writeln('          ),');
    buffer.writeln('    };');
    buffer.writeln('  }');

    buffer.writeln('}');

    return buffer.toString();
  }

  /// Generates the projection bundle constant.
  String _emitProjectionBundle(ProjectionInfo projection) {
    final buffer = StringBuffer();
    final className = projection.className;
    final projectionName = projection.projectionName;

    // Compute schema hash from sorted event type names.
    final schemaHash = _computeSchemaHash(projection.eventTypeNames);

    buffer.writeln('/// Generated projection bundle for $className.');
    buffer.writeln('///');
    buffer.writeln('/// Contains metadata for registry configuration.');
    buffer.writeln('/// Add to the `projections` list when creating a [ProjectionRegistry].');
    buffer.writeln('final \$$className = GeneratedProjection(');
    buffer.writeln("  projectionName: '$projectionName',");
    buffer.writeln("  schemaHash: '$schemaHash',");
    buffer.writeln('  handledEventTypes: {');
    for (final eventTypeName in projection.eventTypeNames) {
      buffer.writeln('    $eventTypeName,');
    }
    buffer.writeln('  },');
    buffer.writeln(');');

    return buffer.toString();
  }

  /// Computes a schema hash from the sorted event type names.
  ///
  /// This hash changes when events are added, removed, or renamed,
  /// triggering a projection rebuild.
  ///
  /// Uses a simple hash algorithm to avoid external dependencies.
  String _computeSchemaHash(List<String> eventTypeNames) {
    final sorted = List<String>.from(eventTypeNames)..sort();
    final concatenated = sorted.join(',');

    // Simple FNV-1a hash (32-bit) for deterministic, fast hashing.
    var hash = 0x811c9dc5;
    for (var i = 0; i < concatenated.length; i++) {
      hash ^= concatenated.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }

    // Return as 8 hex characters.
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
