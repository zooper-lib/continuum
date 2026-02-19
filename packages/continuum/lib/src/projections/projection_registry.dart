import 'generated_projection.dart';
import 'projection_base.dart';
import 'projection_lifecycle.dart';
import 'projection_registration.dart';
import 'read_model_store.dart';

/// Central registry for all projections in the application.
///
/// Manages projection registrations with event-type indexing for
/// efficient dispatch during event processing.
final class ProjectionRegistry {
  /// Internal registrations keyed by projection name.
  final Map<String, ProjectionRegistration<Object, Object>> _registrations = {};

  /// Event-type-to-projection-name index for fast dispatch.
  final Map<Type, Set<String>> _eventTypeIndex = {};

  /// Generated projection bundles keyed by projection name.
  final Map<String, GeneratedProjection> _generatedBundles = {};

  /// Registers a generated inline projection.
  void registerGeneratedInline<TReadModel, TKey>(
    GeneratedProjection bundle,
    ProjectionBase<TReadModel, TKey> projection,
    ReadModelStore<TReadModel, TKey> readModelStore,
  ) {
    _registerGenerated(
      bundle: bundle,
      projection: projection,
      readModelStore: readModelStore,
      lifecycle: ProjectionLifecycle.inline,
    );
  }

  /// Registers a generated async projection.
  void registerGeneratedAsync<TReadModel, TKey>(
    GeneratedProjection bundle,
    ProjectionBase<TReadModel, TKey> projection,
    ReadModelStore<TReadModel, TKey> readModelStore,
  ) {
    _registerGenerated(
      bundle: bundle,
      projection: projection,
      readModelStore: readModelStore,
      lifecycle: ProjectionLifecycle.async,
    );
  }

  /// Registers a manually-defined inline projection.
  void registerInline<TReadModel, TKey>(
    ProjectionBase<TReadModel, TKey> projection,
    ReadModelStore<TReadModel, TKey> readModelStore,
  ) {
    _register(
      projection: projection,
      readModelStore: readModelStore,
      lifecycle: ProjectionLifecycle.inline,
    );
  }

  /// Registers a manually-defined async projection.
  void registerAsync<TReadModel, TKey>(
    ProjectionBase<TReadModel, TKey> projection,
    ReadModelStore<TReadModel, TKey> readModelStore,
  ) {
    _register(
      projection: projection,
      readModelStore: readModelStore,
      lifecycle: ProjectionLifecycle.async,
    );
  }

  /// Returns inline projections that handle the given event type.
  List<ProjectionRegistration<Object, Object>> getInlineProjectionsForEventType(
    Type eventType,
  ) {
    return _getProjectionsForEventType(eventType, ProjectionLifecycle.inline);
  }

  /// Returns async projections that handle the given event type.
  List<ProjectionRegistration<Object, Object>> getAsyncProjectionsForEventType(
    Type eventType,
  ) {
    return _getProjectionsForEventType(eventType, ProjectionLifecycle.async);
  }

  /// All inline projection registrations.
  List<ProjectionRegistration<Object, Object>> get inlineProjections {
    return _registrations.values.where((reg) => reg.lifecycle == ProjectionLifecycle.inline).toList();
  }

  /// All async projection registrations.
  List<ProjectionRegistration<Object, Object>> get asyncProjections {
    return _registrations.values.where((reg) => reg.lifecycle == ProjectionLifecycle.async).toList();
  }

  /// The total number of registered projections.
  int get length => _registrations.length;

  /// Whether no projections are registered.
  bool get isEmpty => _registrations.isEmpty;

  /// Whether any projections are registered.
  bool get isNotEmpty => _registrations.isNotEmpty;

  /// Whether any inline projections are registered.
  bool get hasInlineProjections => inlineProjections.isNotEmpty;

  /// Whether any async projections are registered.
  bool get hasAsyncProjections => asyncProjections.isNotEmpty;

  /// Gets the generated bundle for the named projection, if any.
  GeneratedProjection? getGeneratedBundle(String projectionName) {
    return _generatedBundles[projectionName];
  }

  /// Gets the schema hash for the named projection.
  ///
  /// Returns an empty string if the projection has no generated bundle.
  String getSchemaHash(String projectionName) {
    return _generatedBundles[projectionName]?.schemaHash ?? '';
  }

  /// Internal registration for generated projections.
  void _registerGenerated<TReadModel, TKey>({
    required GeneratedProjection bundle,
    required ProjectionBase<TReadModel, TKey> projection,
    required ReadModelStore<TReadModel, TKey> readModelStore,
    required ProjectionLifecycle lifecycle,
  }) {
    final name = bundle.projectionName;

    if (_registrations.containsKey(name)) {
      throw StateError(
        'Projection "$name" is already registered. '
        'Each projection must have a unique name.',
      );
    }

    _generatedBundles[name] = bundle;

    final registration = ProjectionRegistration<TReadModel, TKey>(
      projection: projection,
      lifecycle: lifecycle,
      readModelStore: readModelStore,
    );
    _registrations[name] = registration as ProjectionRegistration<Object, Object>;

    // Index each handled event type for fast dispatch.
    for (final eventType in bundle.handledEventTypes) {
      _eventTypeIndex.putIfAbsent(eventType, () => {}).add(name);
    }
  }

  /// Internal registration for manually-defined projections.
  void _register<TReadModel, TKey>({
    required ProjectionBase<TReadModel, TKey> projection,
    required ReadModelStore<TReadModel, TKey> readModelStore,
    required ProjectionLifecycle lifecycle,
  }) {
    final name = projection.projectionName;

    if (_registrations.containsKey(name)) {
      throw StateError(
        'Projection "$name" is already registered. '
        'Each projection must have a unique name.',
      );
    }

    final registration = ProjectionRegistration<TReadModel, TKey>(
      projection: projection,
      lifecycle: lifecycle,
      readModelStore: readModelStore,
    );
    _registrations[name] = registration as ProjectionRegistration<Object, Object>;

    // Index each handled event type for fast dispatch.
    for (final eventType in projection.handledEventTypes) {
      _eventTypeIndex.putIfAbsent(eventType, () => {}).add(name);
    }
  }

  /// Internal method to filter projections by event type and lifecycle.
  List<ProjectionRegistration<Object, Object>> _getProjectionsForEventType(
    Type eventType,
    ProjectionLifecycle lifecycle,
  ) {
    final names = _eventTypeIndex[eventType];
    if (names == null || names.isEmpty) {
      return const [];
    }

    return names.map((name) => _registrations[name]).whereType<ProjectionRegistration<Object, Object>>().where((reg) => reg.lifecycle == lifecycle).toList();
  }
}
