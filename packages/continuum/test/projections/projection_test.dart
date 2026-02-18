import 'package:continuum/continuum.dart';
import 'package:test/test.dart';

void main() {
  group('ProjectionBase', () {
    test('handles() returns true for registered event types', () {
      final projection = _TestSingleStreamProjection();

      // Verifies the type-index lookup matches expected types.
      expect(projection.handles(_TestOperationA), isTrue);
      expect(projection.handles(_TestOperationB), isTrue);
    });

    test('handles() returns false for unregistered event types', () {
      final projection = _TestSingleStreamProjection();

      // Unregistered types must not match — prevents misrouting.
      expect(projection.handles(_TestOperationC), isFalse);
      expect(projection.handles(String), isFalse);
    });
  });

  group('SingleStreamProjection', () {
    test('extractKey returns the stream ID from the operation', () {
      final projection = _TestSingleStreamProjection();
      final operation = const _TestOperationA(streamId: StreamId('stream-123'));

      final key = projection.extractKey(operation);

      // Key must be derived from the operation's domain data.
      expect(key, equals(const StreamId('stream-123')));
    });

    test('createInitial creates read model for stream ID', () {
      final projection = _TestSingleStreamProjection();

      final readModel = projection.createInitial(const StreamId('stream-456'));

      expect(readModel.streamId, equals('stream-456'));
      expect(readModel.eventCount, equals(0));
    });

    test('apply updates read model with operation', () {
      final projection = _TestSingleStreamProjection();
      final initial = const _TestReadModel(streamId: 'stream-1', eventCount: 0);
      final operation = const _TestOperationA(streamId: StreamId('stream-1'));

      final updated = projection.apply(initial, operation);

      expect(updated.eventCount, equals(1));
    });

    test('handledEventTypes returns declared types', () {
      final projection = _TestSingleStreamProjection();

      expect(projection.handledEventTypes, contains(_TestOperationA));
      expect(projection.handledEventTypes, contains(_TestOperationB));
      expect(projection.handledEventTypes.length, equals(2));
    });

    test('projectionName returns unique identifier', () {
      final projection = _TestSingleStreamProjection();

      expect(projection.projectionName, equals('test-single-stream'));
    });
  });

  group('MultiStreamProjection', () {
    test('extractKey returns key from operation data', () {
      final projection = _TestMultiStreamProjection();
      final operation = const _TestOperationWithCategory(categoryId: 'category-abc');

      final key = projection.extractKey(operation);

      expect(key, equals('category-abc'));
    });

    test('createInitial creates read model for key', () {
      final projection = _TestMultiStreamProjection();

      final readModel = projection.createInitial('category-xyz');

      expect(readModel.categoryId, equals('category-xyz'));
      expect(readModel.totalEvents, equals(0));
    });

    test('apply updates read model with operation from any stream', () {
      final projection = _TestMultiStreamProjection();
      final initial = const _CategoryStats(categoryId: 'cat-1', totalEvents: 5);
      final operation = const _TestOperationWithCategory(categoryId: 'cat-1');

      final updated = projection.apply(initial, operation);

      expect(updated.totalEvents, equals(6));
    });

    test('handledEventTypes returns declared types', () {
      final projection = _TestMultiStreamProjection();

      expect(projection.handledEventTypes, contains(_TestOperationWithCategory));
      expect(projection.handledEventTypes.length, equals(1));
    });

    test('projectionName returns unique identifier', () {
      final projection = _TestMultiStreamProjection();

      expect(projection.projectionName, equals('test-multi-stream'));
    });
  });
}

// --- Test Fixtures ---

/// Test operation carrying a stream ID.
class _TestOperationA implements Operation {
  final StreamId streamId;

  const _TestOperationA({required this.streamId});
}

/// Test operation carrying a stream ID.
class _TestOperationB implements Operation {
  final StreamId streamId;

  const _TestOperationB({required this.streamId});
}

/// Marker class for unhandled operation type.
class _TestOperationC implements Operation {}

/// Operation carrying a category ID for multi-stream projection tests.
class _TestOperationWithCategory implements Operation {
  final String categoryId;

  const _TestOperationWithCategory({required this.categoryId});
}

/// Simple read model for single-stream projection tests.
class _TestReadModel {
  final String streamId;
  final int eventCount;

  const _TestReadModel({required this.streamId, required this.eventCount});
}

/// Simple read model for multi-stream projection tests.
class _CategoryStats {
  final String categoryId;
  final int totalEvents;

  const _CategoryStats({required this.categoryId, required this.totalEvents});
}

/// Test implementation of SingleStreamProjection.
class _TestSingleStreamProjection extends SingleStreamProjection<_TestReadModel> {
  @override
  Set<Type> get handledEventTypes => {_TestOperationA, _TestOperationB};

  @override
  String get projectionName => 'test-single-stream';

  @override
  StreamId extractKey(Operation operation) {
    return switch (operation) {
      _TestOperationA(:final streamId) => streamId,
      _TestOperationB(:final streamId) => streamId,
      _ => throw ArgumentError('Unsupported operation type: ${operation.runtimeType}'),
    };
  }

  @override
  _TestReadModel createInitial(StreamId streamId) {
    return _TestReadModel(streamId: streamId.value, eventCount: 0);
  }

  @override
  _TestReadModel apply(_TestReadModel current, Operation operation) {
    return _TestReadModel(
      streamId: current.streamId,
      eventCount: current.eventCount + 1,
    );
  }
}

/// Test implementation of MultiStreamProjection.
class _TestMultiStreamProjection extends MultiStreamProjection<_CategoryStats, String> {
  @override
  Set<Type> get handledEventTypes => {_TestOperationWithCategory};

  @override
  String get projectionName => 'test-multi-stream';

  @override
  String extractKey(Operation operation) {
    return (operation as _TestOperationWithCategory).categoryId;
  }

  @override
  _CategoryStats createInitial(String key) {
    return _CategoryStats(categoryId: key, totalEvents: 0);
  }

  @override
  _CategoryStats apply(_CategoryStats current, Operation operation) {
    return _CategoryStats(
      categoryId: current.categoryId,
      totalEvents: current.totalEvents + 1,
    );
  }
}
