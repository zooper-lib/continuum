import 'package:continuum/continuum.dart';
import 'package:test/test.dart';
import 'package:zooper_flutter_core/zooper_flutter_core.dart';

import '../_fixtures/counter_fixtures.dart';

void main() {
  group('AggregateFactoryRegistry', () {
    test('merge prefers other registry for duplicate event types', () {
      final r1 = AggregateFactoryRegistry({
        Counter: {
          CounterCreated: (_) => Counter(1),
        },
      });

      final r2 = AggregateFactoryRegistry({
        Counter: {
          CounterCreated: (_) => Counter(2),
        },
      });

      final merged = r1.merge(r2);
      final factory = merged.getFactory<Counter>(Counter, CounterCreated);

      expect(factory, isNotNull);
      final created = CounterCreated(eventId: const EventId('e-1'), initial: 0);
      final counter = factory!(created);
      expect(counter.value, equals(2));
    });

    test('getFactory returns null for unknown aggregate or event types', () {
      final registry = AggregateFactoryRegistry({
        Counter: {
          CounterCreated: (_) => Counter(1),
        },
      });

      expect(registry.getFactory<Counter>(Counter, CounterIncremented), isNull);
      expect(registry.getFactory<Counter>(String, CounterCreated), isNull);
    });
  });

  group('EventApplierRegistry', () {
    test('merge prefers other registry for duplicate event types', () {
      final r1 = EventApplierRegistry({
        Counter: {
          CounterIncremented: (aggregate, _) {
            final counter = aggregate as Counter;
            counter.value += 1;
          },
        },
      });

      final r2 = EventApplierRegistry({
        Counter: {
          CounterIncremented: (aggregate, _) {
            final counter = aggregate as Counter;
            counter.value += 10;
          },
        },
      });

      final merged = r1.merge(r2);
      final applier = merged.getApplier<Counter>(Counter, CounterIncremented);

      expect(applier, isNotNull);
      final counter = Counter(0);
      applier!(counter, CounterIncremented(eventId: const EventId('e-1'), amount: 123));
      expect(counter.value, equals(10));
    });

    test('getApplier returns null for unknown aggregate or event types', () {
      final registry = EventApplierRegistry({
        Counter: {
          CounterIncremented: (_, _) {},
        },
      });

      expect(registry.getApplier<Counter>(Counter, CounterCreated), isNull);
      expect(registry.getApplier<Counter>(String, CounterIncremented), isNull);
    });

    test(
      'BUG: getApplier should not accept wrong aggregate instances at runtime',
      () {
        final registry = EventApplierRegistry({
          Counter: {
            CounterIncremented: (aggregate, event) {
              final counter = aggregate as Counter;
              final incremented = event as CounterIncremented;
              counter.value += incremented.amount;
            },
          },
        });

        // Ask for an applier that accepts `Object` so we can pass the wrong
        // aggregate instance and verify it fails at runtime (not compile-time).
        final applier = registry.getApplier<Object>(Counter, CounterIncremented);
        expect(applier, isNotNull);

        expect(
          () => applier!(
            'not a Counter',
            CounterIncremented(eventId: const EventId('e-1'), amount: 1),
          ),
          throwsA(isA<TypeError>()),
        );
      },
    );
  });
}
