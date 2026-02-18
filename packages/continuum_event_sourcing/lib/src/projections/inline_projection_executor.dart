import '../persistence/stored_event.dart';
import 'projection_registration.dart';
import 'projection_registry.dart';

/// Executes inline projections synchronously during save.
///
/// Processes all committed events through matching inline projections,
/// updating read models before [saveChangesAsync] returns.
final class InlineProjectionExecutor {
  /// The registry of projections to check for matches.
  final ProjectionRegistry _registry;

  /// Creates an inline projection executor with the given registry.
  InlineProjectionExecutor({required ProjectionRegistry registry}) : _registry = registry;

  /// Processes all events through matching inline projections.
  ///
  /// Called during [saveChangesAsync] to ensure read models are
  /// updated before the method returns.
  Future<void> executeAsync(List<StoredEvent> events) async {
    if (!_registry.hasInlineProjections) {
      return;
    }

    for (final event in events) {
      await _processEventAsync(event);
    }
  }

  /// Processes a single event through all matching inline projections.
  Future<void> _processEventAsync(StoredEvent event) async {
    final domainEvent = event.domainEvent;
    if (domainEvent == null) {
      throw StateError(
        'StoredEvent.domainEvent is null. '
        'Projections require deserialized domain events.',
      );
    }

    final projections = _registry.getInlineProjectionsForEventType(
      domainEvent.runtimeType,
    );

    for (final registration in projections) {
      await _applyEventToProjectionAsync(registration, event);
    }
  }

  /// Applies a single event to a single projection's read model.
  Future<void> _applyEventToProjectionAsync(
    ProjectionRegistration<Object, Object> registration,
    StoredEvent event,
  ) async {
    final projection = registration.projection;
    final store = registration.readModelStore;

    final key = projection.extractKey(event);

    var readModel = await store.loadAsync(key);
    readModel ??= projection.createInitial(key);

    final updatedReadModel = projection.apply(readModel, event);

    await store.saveAsync(key, updatedReadModel);
  }
}
