import '../operations/operation.dart';
import 'projection_registration.dart';
import 'projection_registry.dart';

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

  /// Processes all operations through matching inline projections.
  ///
  /// Called after successful persistence to ensure read models are
  /// updated before the commit cycle returns.
  Future<void> executeAsync(List<Operation> operations) async {
    if (!_registry.hasInlineProjections) {
      return;
    }

    for (final operation in operations) {
      await _processOperationAsync(operation);
    }
  }

  /// Processes a single operation through all matching inline projections.
  Future<void> _processOperationAsync(Operation operation) async {
    final projections = _registry.getInlineProjectionsForEventType(
      operation.runtimeType,
    );

    for (final registration in projections) {
      await _applyOperationToProjectionAsync(registration, operation);
    }
  }

  /// Applies a single operation to a single projection's read model.
  Future<void> _applyOperationToProjectionAsync(
    ProjectionRegistration<Object, Object> registration,
    Operation operation,
  ) async {
    final projection = registration.projection;
    final store = registration.readModelStore;

    final key = projection.extractKey(operation);

    var readModel = await store.loadAsync(key);
    readModel ??= projection.createInitial(key);

    final updatedReadModel = projection.apply(readModel, operation);

    await store.saveAsync(key, updatedReadModel);
  }
}
