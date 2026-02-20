import 'package:continuum/continuum.dart';
import 'package:continuum_state/continuum_state.dart';
import 'package:continuum_uow/continuum_uow.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../_fixtures/counter_fixtures.dart';

@GenerateNiceMocks([
  MockSpec<TargetPersistenceAdapter<Counter>>(),
])
import 'state_based_store_test.mocks.dart';

void main() {
  late MockTargetPersistenceAdapter mockAdapter;
  late GeneratedAggregate generatedAggregate;

  setUp(() {
    provideDummy<Counter>(Counter(0));
    mockAdapter = MockTargetPersistenceAdapter();
    generatedAggregate = buildGeneratedCounterAggregate();
  });

  test('6.1 StateBasedStore implements SessionStore', () {
    // Arrange & Act
    final store = StateBasedStore(
      adapters: {Counter: mockAdapter},
      targets: [generatedAggregate],
    );

    // Assert — type assignability check.
    expect(store, isA<SessionStore>());
  });

  test('6.2 each openSession returns an independent session', () {
    // Arrange
    final store = StateBasedStore(
      adapters: {Counter: mockAdapter},
      targets: [generatedAggregate],
    );

    // Act
    final session1 = store.openSession();
    final session2 = store.openSession();

    // Assert — sessions are distinct instances.
    expect(identical(session1, session2), isFalse);
  });

  test('6.3 default application mode is eager', () async {
    // Arrange — create store without explicit mode.
    final store = StateBasedStore(
      adapters: {Counter: mockAdapter},
      targets: [generatedAggregate],
    );
    final session = store.openSession();
    const streamId = StreamId('counter-1');

    // Act — create and mutate in the default mode.
    final counter = await session.applyAsync<Counter>(
      streamId,
      CounterCreated(eventId: const EventId('e-1'), initial: 10),
    );
    await session.applyAsync<Counter>(
      streamId,
      CounterIncremented(eventId: const EventId('e-2'), amount: 5),
    );

    // Assert — eager mode applies immediately.
    expect(counter.value, equals(15));
  });

  test('6.4 explicit deferred mode propagated to session', () async {
    // Arrange — create store with deferred mode.
    final store = StateBasedStore(
      adapters: {Counter: mockAdapter},
      targets: [generatedAggregate],
      applicationMode: EventApplicationMode.deferred,
    );
    final session = store.openSession();
    const streamId = StreamId('counter-1');

    // Act — create and mutate in deferred mode.
    final counter = await session.applyAsync<Counter>(
      streamId,
      CounterCreated(eventId: const EventId('e-1'), initial: 10),
    );
    await session.applyAsync<Counter>(
      streamId,
      CounterIncremented(eventId: const EventId('e-2'), amount: 5),
    );

    // Assert — deferred mode: aggregate unchanged until save.
    expect(counter.value, equals(10));
  });

  test('6.5 TransactionalRunner works with StateBasedStore', () async {
    // Arrange
    final store = StateBasedStore(
      adapters: {Counter: mockAdapter},
      targets: [generatedAggregate],
    );
    final runner = TransactionalRunner(store: store);

    when(mockAdapter.persistAsync(any, any, any)).thenAnswer(
      (_) async {},
    );

    // Act — run a transactional action.
    await runner.runAsync(() async {
      final session = TransactionalRunner.currentSession;

      await session.applyAsync<Counter>(
        const StreamId('counter-1'),
        CounterCreated(eventId: const EventId('e-1'), initial: 10),
      );
    });

    // Assert — persistAsync was called during auto-commit.
    verify(mockAdapter.persistAsync(any, any, any)).called(1);
  });

  test(
    '6.6 adapter receives creation event and aggregate on save',
    () async {
      // Arrange
      final store = StateBasedStore(
        adapters: {Counter: mockAdapter},
        targets: [generatedAggregate],
      );
      final session = store.openSession();
      const streamId = StreamId('counter-1');

      when(mockAdapter.persistAsync(any, any, any)).thenAnswer(
        (_) async {},
      );

      // Act — apply creation event and save.
      await session.applyAsync<Counter>(
        streamId,
        CounterCreated(eventId: const EventId('e-1'), initial: 42),
      );
      await session.saveChangesAsync();

      // Assert — adapter received stream ID, aggregate, and operation list.
      final captured = verify(
        mockAdapter.persistAsync(
          captureAny,
          captureAny,
          captureAny,
        ),
      ).captured;

      expect(captured[0], equals(streamId));
      expect((captured[1] as Counter).value, equals(42));
      final operations = captured[2] as List;
      expect(operations, hasLength(1));
      expect(operations.first, isA<CounterCreated>());
    },
  );
}
