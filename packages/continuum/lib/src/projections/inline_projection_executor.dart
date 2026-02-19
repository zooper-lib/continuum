import '../identity/stream_id.dart';
import '../operations/operation.dart';
import 'commit_batch.dart';
import 'committed_entry.dart';
import 'projection_registration.dart';
import 'projection_registry.dart';
import 'single_stream_projection.dart';

/// Executes inline projections synchronously after commit.
///
/// Processes all committed operations through matching inline projections,
/// updating read models before the commit cycle completes. Typically
/// consumed as a [CommitHandler] delegate on the [TransactionalRunner].
final class InlineProjectionExecutor {
  /// The registry of projections to check for matches.
  final ProjectionRegistry _registry;

  /// Creates an inline projection executor with the given registry.
  InlineProjectionExecutor({required ProjectionRegistry registry}) : _registry = registry;

  /// Processes all operations in the [batch] through matching inline
  /// projections.
  ///
  /// Iterates by [CommittedEntry] so that single-stream projections
  /// receive the [StreamId] directly from the entry, eliminating the
  /// need for user-provided key extraction.
  Future<void> executeAsync(CommitBatch batch) async {
    if (!_registry.hasInlineProjections) {
      return;
    }

    for (final entry in batch.entries) {
      for (final committedOp in entry.operations) {
        await _processOperationAsync(entry, committedOp.operation);
      }
    }
  }

  /// Processes a single operation through all matching inline projections.
  Future<void> _processOperationAsync(
    CommittedEntry entry,
    Operation operation,
  ) async {
    final projections = _registry.getInlineProjectionsForEventType(
      operation.runtimeType,
    );

    for (final registration in projections) {
      await _applyOperationToProjectionAsync(registration, entry.streamId, operation);
    }
  }

  /// Applies a single operation to a single projection's read model.
  ///
  /// For [SingleStreamProjection], uses the [streamId] from the
  /// [CommittedEntry] directly. For multi-stream projections, delegates
  /// to [ProjectionBase.extractKey].
  Future<void> _applyOperationToProjectionAsync(
    ProjectionRegistration<Object, Object> registration,
    StreamId streamId,
    Operation operation,
  ) async {
    final projection = registration.projection;
    final store = registration.readModelStore;

    final key = projection is SingleStreamProjection ? streamId : projection.extractKey(operation);

    var readModel = await store.loadAsync(key);
    readModel ??= projection.createInitial(key);

    final updatedReadModel = projection.apply(readModel, operation);

    await store.saveAsync(key, updatedReadModel);
  }
}
