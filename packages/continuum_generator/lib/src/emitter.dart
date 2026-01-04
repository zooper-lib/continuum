import 'models/aggregate_info.dart';

/// Generates code for aggregates and their events.
///
/// Creates event handler mixins, apply dispatchers, replay helpers,
/// and creation dispatchers.
final class CodeEmitter {
  /// Generates all code for the given aggregates.
  ///
  /// Returns the combined generated code as a string.
  String emit(List<AggregateInfo> aggregates) {
    final buffer = StringBuffer();

    for (final aggregate in aggregates) {
      buffer.writeln(_emitEventHandlersMixin(aggregate));
      buffer.writeln();
      buffer.writeln(_emitApplyExtension(aggregate));
      buffer.writeln();
      buffer.writeln(_emitCreationExtension(aggregate));
      buffer.writeln();
    }

    // Emit the combined event registry
    buffer.writeln(_emitEventRegistry(aggregates));

    // Emit the aggregate factory registry
    buffer.writeln();
    buffer.writeln(_emitAggregateFactoryRegistry(aggregates));

    // Emit the event applier registry
    buffer.writeln();
    buffer.writeln(_emitEventApplierRegistry(aggregates));

    return buffer.toString();
  }

  /// Generates the event handlers mixin for mutation events only.
  ///
  /// This mixin requires the aggregate to implement apply methods for
  /// each mutation event type.
  String _emitEventHandlersMixin(AggregateInfo aggregate) {
    final buffer = StringBuffer();

    buffer.writeln('/// Generated mixin requiring apply methods for ${aggregate.name} mutation events.');
    buffer.writeln('///');
    buffer.writeln('/// Implement this mixin and provide the required apply methods.');
    buffer.writeln('mixin _\$${aggregate.name}EventHandlers {');

    // Generate abstract apply methods for each mutation event
    for (final event in aggregate.mutationEvents) {
      buffer.writeln('  /// Applies a ${event.name} event to this aggregate.');
      buffer.writeln('  void apply${event.name}(${event.name} event);');
      buffer.writeln();
    }

    buffer.writeln('}');

    return buffer.toString();
  }

  /// Generates the apply extension for dispatching events.
  String _emitApplyExtension(AggregateInfo aggregate) {
    final buffer = StringBuffer();

    buffer.writeln('/// Generated extension providing event dispatch for ${aggregate.name}.');
    buffer.writeln('extension \$${aggregate.name}EventDispatch on ${aggregate.name} {');

    // Generate applyEvent dispatcher
    buffer.writeln('  /// Applies a domain event to this aggregate.');
    buffer.writeln('  ///');
    buffer.writeln('  /// Routes supported mutation events to the corresponding apply method.');
    buffer.writeln('  /// Throws [UnsupportedEventException] for unknown event types.');
    buffer.writeln('  void applyEvent(DomainEvent event) {');
    buffer.writeln('    switch (event) {');

    for (final event in aggregate.mutationEvents) {
      buffer.writeln('      case ${event.name}():');
      buffer.writeln('        apply${event.name}(event);');
    }

    buffer.writeln('      default:');
    buffer.writeln('        throw UnsupportedEventException(');
    buffer.writeln('          eventType: event.runtimeType,');
    buffer.writeln('          aggregateType: ${aggregate.name},');
    buffer.writeln('        );');
    buffer.writeln('    }');
    buffer.writeln('  }');
    buffer.writeln();

    // Generate replayEvents helper
    buffer.writeln('  /// Replays multiple events in order.');
    buffer.writeln('  ///');
    buffer.writeln('  /// Applies each event sequentially via [applyEvent].');
    buffer.writeln('  void replayEvents(Iterable<DomainEvent> events) {');
    buffer.writeln('    for (final event in events) {');
    buffer.writeln('      applyEvent(event);');
    buffer.writeln('    }');
    buffer.writeln('  }');

    buffer.writeln('}');

    return buffer.toString();
  }

  /// Generates the creation extension for creating aggregates from events.
  String _emitCreationExtension(AggregateInfo aggregate) {
    final buffer = StringBuffer();

    buffer.writeln('/// Generated extension providing creation dispatch for ${aggregate.name}.');
    buffer.writeln('extension \$${aggregate.name}Creation on Never {');

    // Generate createFromEvent dispatcher
    buffer.writeln('  /// Creates a ${aggregate.name} from a creation event.');
    buffer.writeln('  ///');
    buffer.writeln('  /// Routes to the appropriate static create method.');
    buffer.writeln('  /// Throws [InvalidCreationEventException] for unknown event types.');
    buffer.writeln('  static ${aggregate.name} createFromEvent(DomainEvent event) {');
    buffer.writeln('    switch (event) {');

    for (final event in aggregate.creationEvents) {
      // Derive the create method name from the event name
      final createMethodName = 'create${event.name}';
      buffer.writeln('      case ${event.name}():');
      buffer.writeln('        return ${aggregate.name}.$createMethodName(event);');
    }

    buffer.writeln('      default:');
    buffer.writeln('        throw InvalidCreationEventException(');
    buffer.writeln('          eventType: event.runtimeType,');
    buffer.writeln('          aggregateType: ${aggregate.name},');
    buffer.writeln('        );');
    buffer.writeln('    }');
    buffer.writeln('  }');

    buffer.writeln('}');

    return buffer.toString();
  }

  /// Generates the event registry for all aggregates.
  String _emitEventRegistry(List<AggregateInfo> aggregates) {
    final buffer = StringBuffer();

    buffer.writeln('/// Generated event registry for persistence deserialization.');
    buffer.writeln('///');
    buffer.writeln('/// Maps event type discriminators to fromJson factories.');
    buffer.writeln('final \$generatedEventRegistry = EventRegistry({');

    for (final aggregate in aggregates) {
      for (final event in aggregate.allEvents) {
        // Only include events with type discriminators
        if (event.type != null) {
          buffer.writeln("  '${event.typeDiscriminator}': ${event.name}.fromJson,");
        }
      }
    }

    buffer.writeln('});');

    return buffer.toString();
  }

  /// Generates the aggregate factory registry for creation dispatch.
  String _emitAggregateFactoryRegistry(List<AggregateInfo> aggregates) {
    final buffer = StringBuffer();

    buffer.writeln('/// Generated aggregate factory registry for Session creation dispatch.');
    buffer.writeln('final \$generatedAggregateFactories = AggregateFactoryRegistry({');

    for (final aggregate in aggregates) {
      if (aggregate.creationEvents.isEmpty) continue;

      buffer.writeln('  ${aggregate.name}: {');
      for (final event in aggregate.creationEvents) {
        final createMethodName = 'create${event.name}';
        buffer.writeln('    ${event.name}: (event) => ${aggregate.name}.$createMethodName(event as ${event.name}),');
      }
      buffer.writeln('  },');
    }

    buffer.writeln('});');

    return buffer.toString();
  }

  /// Generates the event applier registry for mutation dispatch.
  String _emitEventApplierRegistry(List<AggregateInfo> aggregates) {
    final buffer = StringBuffer();

    buffer.writeln('/// Generated event applier registry for Session mutation dispatch.');
    buffer.writeln('final \$generatedEventAppliers = EventApplierRegistry({');

    for (final aggregate in aggregates) {
      if (aggregate.mutationEvents.isEmpty) continue;

      buffer.writeln('  ${aggregate.name}: {');
      for (final event in aggregate.mutationEvents) {
        buffer.writeln('    ${event.name}: (aggregate, event) => ');
        buffer.writeln('        (aggregate as ${aggregate.name}).apply${event.name}(event as ${event.name}),');
      }
      buffer.writeln('  },');
    }

    buffer.writeln('});');

    return buffer.toString();
  }
}
