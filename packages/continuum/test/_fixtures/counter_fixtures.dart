import 'package:continuum/continuum.dart';
import 'package:zooper_flutter_core/zooper_flutter_core.dart';

final class Counter {
  int value;

  Counter(this.value);
}

final class CounterCreated implements ContinuumEvent {
  CounterCreated({
    required this.initial,
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  final int initial;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  factory CounterCreated.fromJson(Map<String, dynamic> json) {
    return CounterCreated(
      eventId: EventId(json['eventId'] as String),
      initial: json['initial'] as int,
      occurredOn: DateTime.parse(json['occurredOn'] as String),
      metadata: Map<String, Object?>.from(json['metadata'] as Map),
    );
  }
}

final class CounterIncremented implements ContinuumEvent {
  CounterIncremented({
    required this.amount,
    EventId? eventId,
    DateTime? occurredOn,
    Map<String, Object?> metadata = const {},
  }) : id = eventId ?? EventId.fromUlid(),
       occurredOn = occurredOn ?? DateTime.now(),
       metadata = Map<String, Object?>.unmodifiable(metadata);

  final int amount;

  @override
  final EventId id;

  @override
  final DateTime occurredOn;

  @override
  final Map<String, Object?> metadata;

  factory CounterIncremented.fromJson(Map<String, dynamic> json) {
    return CounterIncremented(
      eventId: EventId(json['eventId'] as String),
      amount: json['amount'] as int,
      occurredOn: DateTime.parse(json['occurredOn'] as String),
      metadata: Map<String, Object?>.from(json['metadata'] as Map),
    );
  }
}

EventSerializerRegistry buildCounterSerializerRegistry() {
  return EventSerializerRegistry({
    CounterCreated: EventSerializerEntry(
      eventType: 'counter.created',
      toJson: (event) {
        final created = event as CounterCreated;
        return {'initial': created.initial};
      },
      fromJson: CounterCreated.fromJson,
    ),
    CounterIncremented: EventSerializerEntry(
      eventType: 'counter.incremented',
      toJson: (event) {
        final incremented = event as CounterIncremented;
        return {'amount': incremented.amount};
      },
      fromJson: CounterIncremented.fromJson,
    ),
  });
}

AggregateFactoryRegistry buildCounterFactoryRegistry() {
  return AggregateFactoryRegistry({
    Counter: {
      CounterCreated: (event) {
        final created = event as CounterCreated;
        return Counter(created.initial);
      },
    },
  });
}

EventApplierRegistry buildCounterApplierRegistry() {
  return EventApplierRegistry({
    Counter: {
      CounterIncremented: (aggregate, event) {
        final counter = aggregate as Counter;
        final incremented = event as CounterIncremented;
        counter.value += incremented.amount;
      },
    },
  });
}

GeneratedAggregate buildGeneratedCounterAggregate() {
  return GeneratedAggregate(
    serializerRegistry: buildCounterSerializerRegistry(),
    aggregateFactories: buildCounterFactoryRegistry(),
    eventAppliers: buildCounterApplierRegistry(),
  );
}
