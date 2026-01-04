import 'models/aggregate_info.dart';

/// Generates code for aggregates and their events.
///
/// Creates event handler mixins, apply dispatchers, replay helpers,
/// creation dispatchers, and a combined GeneratedAggregate bundle.
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
      // Emit the combined GeneratedAggregate bundle
      buffer.writeln(_emitGeneratedAggregate(aggregate));
      buffer.writeln();
    }

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

  /// Generates the combined GeneratedAggregate bundle for a single aggregate.
  ///
  /// This bundles the serializer registry, aggregate factories, and event
  /// appliers into a single constant that can be passed to EventSourcingStore.
  String _emitGeneratedAggregate(AggregateInfo aggregate) {
    final buffer = StringBuffer();

    buffer.writeln('/// Generated aggregate bundle for ${aggregate.name}.');
    buffer.writeln('///');
    buffer.writeln('/// Contains all serializers, factories, and appliers for this aggregate.');
    buffer.writeln('/// Add to the `aggregates` list when creating an [EventSourcingStore].');
    buffer.writeln('final \$${aggregate.name} = GeneratedAggregate(');

    // Emit serializer registry inline
    buffer.writeln('  serializerRegistry: EventSerializerRegistry({');
    for (final event in aggregate.allEvents) {
      if (event.type != null) {
        buffer.writeln('    ${event.name}: EventSerializerEntry(');
        buffer.writeln("      eventType: '${event.typeDiscriminator}',");
        buffer.writeln('      toJson: (event) => (event as ${event.name}).toJson(),');
        buffer.writeln('      fromJson: ${event.name}.fromJson,');
        buffer.writeln('    ),');
      }
    }
    buffer.writeln('  }),');

    // Emit aggregate factory registry inline
    buffer.writeln('  aggregateFactories: AggregateFactoryRegistry({');
    if (aggregate.creationEvents.isNotEmpty) {
      buffer.writeln('    ${aggregate.name}: {');
      for (final event in aggregate.creationEvents) {
        final createMethodName = 'create${event.name}';
        buffer.writeln('      ${event.name}: (event) => ${aggregate.name}.$createMethodName(event as ${event.name}),');
      }
      buffer.writeln('    },');
    }
    buffer.writeln('  }),');

    // Emit event applier registry inline
    buffer.writeln('  eventAppliers: EventApplierRegistry({');
    if (aggregate.mutationEvents.isNotEmpty) {
      buffer.writeln('    ${aggregate.name}: {');
      for (final event in aggregate.mutationEvents) {
        buffer.writeln('      ${event.name}: (aggregate, event) =>');
        buffer.writeln('          (aggregate as ${aggregate.name}).apply${event.name}(event as ${event.name}),');
      }
      buffer.writeln('    },');
    }
    buffer.writeln('  }),');

    buffer.writeln(');');

    return buffer.toString();
  }
}
