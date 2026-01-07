import 'package:continuum/continuum.dart';

final class Counter {
  int value;

  Counter(this.value);
}

final class CounterCreated extends DomainEvent {
  final int initial;

  CounterCreated({
    required super.eventId,
    required this.initial,
    super.occurredOn,
    super.metadata,
  });

  factory CounterCreated.fromJson(Map<String, dynamic> json) {
    return CounterCreated(
      eventId: EventId(json['eventId'] as String),
      initial: json['initial'] as int,
      occurredOn: DateTime.parse(json['occurredOn'] as String),
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>(),
    );
  }
}

final class CounterIncremented extends DomainEvent {
  final int amount;

  CounterIncremented({
    required super.eventId,
    required this.amount,
    super.occurredOn,
    super.metadata,
  });

  factory CounterIncremented.fromJson(Map<String, dynamic> json) {
    return CounterIncremented(
      eventId: EventId(json['eventId'] as String),
      amount: json['amount'] as int,
      occurredOn: DateTime.parse(json['occurredOn'] as String),
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>(),
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
