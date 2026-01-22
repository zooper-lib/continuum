import 'package:continuum/continuum.dart';
import 'package:test/test.dart';

void main() {
  group('ProjectionRegistry', () {
    late ProjectionRegistry registry;

    setUp(() {
      registry = ProjectionRegistry();
    });

    test('registerInline adds projection with inline lifecycle', () {
      final projection = _CounterProjection('counter-1');
      final store = InMemoryReadModelStore<int, StreamId>();

      registry.registerInline(projection, store);

      expect(registry.length, equals(1));
      expect(registry.hasInlineProjections, isTrue);
      expect(registry.hasAsyncProjections, isFalse);
    });

    test('registerAsync adds projection with async lifecycle', () {
      final projection = _CounterProjection('counter-2');
      final store = InMemoryReadModelStore<int, StreamId>();

      registry.registerAsync(projection, store);

      expect(registry.length, equals(1));
      expect(registry.hasInlineProjections, isFalse);
      expect(registry.hasAsyncProjections, isTrue);
    });

    test('registerInline throws on duplicate projection name', () {
      final projection1 = _CounterProjection('same-name');
      final projection2 = _CounterProjection('same-name');
      final store = InMemoryReadModelStore<int, StreamId>();

      registry.registerInline(projection1, store);

      expect(
        () => registry.registerInline(projection2, store),
        throwsStateError,
      );
    });

    test('registerAsync throws on duplicate projection name', () {
      final projection1 = _CounterProjection('same-name');
      final projection2 = _CounterProjection('same-name');
      final store = InMemoryReadModelStore<int, StreamId>();

      registry.registerAsync(projection1, store);

      expect(
        () => registry.registerAsync(projection2, store),
        throwsStateError,
      );
    });

    test('throws on duplicate name across inline and async', () {
      final projection1 = _CounterProjection('shared-name');
      final projection2 = _CounterProjection('shared-name');
      final store = InMemoryReadModelStore<int, StreamId>();

      registry.registerInline(projection1, store);

      expect(
        () => registry.registerAsync(projection2, store),
        throwsStateError,
      );
    });

    test('getInlineProjectionsForEventType returns matching inline projections', () {
      final projection1 = _CounterProjection('p1', {_EventA});
      final projection2 = _CounterProjection('p2', {_EventA, _EventB});
      final projection3 = _CounterProjection('p3', {_EventB});
      final store = InMemoryReadModelStore<int, StreamId>();

      registry.registerInline(projection1, store);
      registry.registerInline(projection2, store);
      registry.registerAsync(projection3, store);

      final matchingA = registry.getInlineProjectionsForEventType(_EventA);
      final matchingB = registry.getInlineProjectionsForEventType(_EventB);
      final matchingC = registry.getInlineProjectionsForEventType(_EventC);

      // EventA: p1 (inline) and p2 (inline)
      expect(matchingA.length, equals(2));
      expect(
        matchingA.map((r) => r.projectionName).toSet(),
        equals({'p1', 'p2'}),
      );

      // EventB: only p2 (inline), p3 is async
      expect(matchingB.length, equals(1));
      expect(matchingB.first.projectionName, equals('p2'));

      // EventC: no matches
      expect(matchingC, isEmpty);
    });

    test('getAsyncProjectionsForEventType returns matching async projections', () {
      final projection1 = _CounterProjection('p1', {_EventA});
      final projection2 = _CounterProjection('p2', {_EventA, _EventB});
      final store = InMemoryReadModelStore<int, StreamId>();

      registry.registerInline(projection1, store);
      registry.registerAsync(projection2, store);

      final matchingA = registry.getAsyncProjectionsForEventType(_EventA);
      final matchingB = registry.getAsyncProjectionsForEventType(_EventB);

      // EventA: only p2 (async), p1 is inline
      expect(matchingA.length, equals(1));
      expect(matchingA.first.projectionName, equals('p2'));

      // EventB: p2 (async)
      expect(matchingB.length, equals(1));
      expect(matchingB.first.projectionName, equals('p2'));
    });

    test('inlineProjections returns all inline registrations', () {
      final p1 = _CounterProjection('inline-1');
      final p2 = _CounterProjection('inline-2');
      final p3 = _CounterProjection('async-1');
      final store = InMemoryReadModelStore<int, StreamId>();

      registry.registerInline(p1, store);
      registry.registerInline(p2, store);
      registry.registerAsync(p3, store);

      final inline = registry.inlineProjections;

      expect(inline.length, equals(2));
      expect(
        inline.map((r) => r.projectionName).toSet(),
        equals({'inline-1', 'inline-2'}),
      );
    });

    test('asyncProjections returns all async registrations', () {
      final p1 = _CounterProjection('inline-1');
      final p2 = _CounterProjection('async-1');
      final p3 = _CounterProjection('async-2');
      final store = InMemoryReadModelStore<int, StreamId>();

      registry.registerInline(p1, store);
      registry.registerAsync(p2, store);
      registry.registerAsync(p3, store);

      final async = registry.asyncProjections;

      expect(async.length, equals(2));
      expect(
        async.map((r) => r.projectionName).toSet(),
        equals({'async-1', 'async-2'}),
      );
    });

    test('isEmpty returns true when no projections registered', () {
      expect(registry.isEmpty, isTrue);
      expect(registry.isNotEmpty, isFalse);
    });

    test('isNotEmpty returns true when projections registered', () {
      final projection = _CounterProjection('p1');
      final store = InMemoryReadModelStore<int, StreamId>();

      registry.registerInline(projection, store);

      expect(registry.isEmpty, isFalse);
      expect(registry.isNotEmpty, isTrue);
    });

    group('Generated projection support', () {
      test('registerGeneratedInline registers with bundle metadata', () {
        const bundle = GeneratedProjection(
          projectionName: 'gen-inline',
          schemaHash: 'abc123',
          handledEventTypes: {_EventA, _EventB},
        );
        final projection = _CounterProjection('gen-inline', {_EventA, _EventB});
        final store = InMemoryReadModelStore<int, StreamId>();

        registry.registerGeneratedInline(bundle, projection, store);

        expect(registry.length, equals(1));
        expect(registry.hasInlineProjections, isTrue);
        expect(registry.getSchemaHash('gen-inline'), equals('abc123'));
      });

      test('registerGeneratedAsync registers with bundle metadata', () {
        const bundle = GeneratedProjection(
          projectionName: 'gen-async',
          schemaHash: 'def456',
          handledEventTypes: {_EventA},
        );
        final projection = _CounterProjection('gen-async', {_EventA});
        final store = InMemoryReadModelStore<int, StreamId>();

        registry.registerGeneratedAsync(bundle, projection, store);

        expect(registry.length, equals(1));
        expect(registry.hasAsyncProjections, isTrue);
        expect(registry.getSchemaHash('gen-async'), equals('def456'));
      });

      test('getSchemaHash returns empty string for manual registrations', () {
        final projection = _CounterProjection('manual');
        final store = InMemoryReadModelStore<int, StreamId>();

        registry.registerInline(projection, store);

        expect(registry.getSchemaHash('manual'), isEmpty);
      });

      test('getSchemaHash returns empty string for unknown projection', () {
        expect(registry.getSchemaHash('unknown'), isEmpty);
      });

      test('registerGeneratedInline throws on duplicate name', () {
        const bundle1 = GeneratedProjection(
          projectionName: 'duplicate',
          schemaHash: 'hash1',
          handledEventTypes: {_EventA},
        );
        const bundle2 = GeneratedProjection(
          projectionName: 'duplicate',
          schemaHash: 'hash2',
          handledEventTypes: {_EventB},
        );
        final projection1 = _CounterProjection('duplicate', {_EventA});
        final projection2 = _CounterProjection('duplicate', {_EventB});
        final store = InMemoryReadModelStore<int, StreamId>();

        registry.registerGeneratedInline(bundle1, projection1, store);

        expect(
          () => registry.registerGeneratedInline(bundle2, projection2, store),
          throwsStateError,
        );
      });
    });
  });

  group('ProjectionLifecycle', () {
    test('has inline and async values', () {
      expect(ProjectionLifecycle.values, contains(ProjectionLifecycle.inline));
      expect(ProjectionLifecycle.values, contains(ProjectionLifecycle.async));
      expect(ProjectionLifecycle.values.length, equals(2));
    });
  });
}

// --- Test Fixtures ---

class _EventA {}

class _EventB {}

class _EventC {}

/// Simple projection for testing registry behavior.
class _CounterProjection extends SingleStreamProjection<int> {
  final String _name;
  final Set<Type> _handledTypes;

  _CounterProjection(this._name, [Set<Type>? handledTypes]) : _handledTypes = handledTypes ?? {_EventA};

  @override
  Set<Type> get handledEventTypes => _handledTypes;

  @override
  String get projectionName => _name;

  @override
  int createInitial(StreamId streamId) => 0;

  @override
  int apply(int current, StoredEvent event) => current + 1;
}
