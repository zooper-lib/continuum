import 'generated_projection.dart';
import 'projection.dart';
import 'projection_lifecycle.dart';
import 'projection_registration.dart';
import 'read_model_store.dart';

/// Central registry for all projections in the system.
///
/// The registry maintains a mapping from event types to projections,
/// enabling efficient routing of events to their handlers. Projections
/// are registered with either inline or async lifecycle.
///
/// Example:
/// ```dart
/// final registry = ProjectionRegistry();
///
/// // Using generated projection bundles (recommended):
/// registry.registerGeneratedInline(
///   $UserProfileProjection,
///   userProfileProjection,
///   userProfileStore,
/// );
///
/// // Or using legacy manual registration:
/// registry.registerInline(
///   userProfileProjection,
///   userProfileStore,
/// );
///
/// registry.registerAsync(
///   statisticsProjection,
///   statisticsStore,
/// );
/// ```
final class ProjectionRegistry {
  /// All registered projections indexed by name.
  final Map<String, ProjectionRegistration<Object, Object>> _registrations = {};

  /// Index of event type → projection names for fast lookup.
  final Map<Type, Set<String>> _eventTypeIndex = {};

  /// Generated projection bundles indexed by projection name.
  final Map<String, GeneratedProjection> _generatedBundles = {};

  /// Registers a projection for inline execution using generated metadata.
  ///
  /// Uses the [GeneratedProjection] bundle for event types and schema tracking.
  /// This is the recommended approach for projections using code generation.
  ///
  /// Throws [StateError] if a projection with the same name is already registered.
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

  /// Registers a projection for async execution using generated metadata.
  ///
  /// Uses the [GeneratedProjection] bundle for event types and schema tracking.
  /// This is the recommended approach for projections using code generation.
  ///
  /// Throws [StateError] if a projection with the same name is already registered.
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

  /// Registers a projection for inline (synchronous) execution.
  ///
  /// Inline projections are executed during `saveChangesAsync()` as part
  /// of the same logical unit of work. Failures abort the event append.
  ///
  /// Throws [StateError] if a projection with the same name is already registered.
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

  /// Registers a projection for async (background) execution.
  ///
  /// Async projections are executed by the background projection processor.
  /// Event appends complete immediately without waiting for the projection.
  ///
  /// Throws [StateError] if a projection with the same name is already registered.
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

  /// Internal registration method for generated projections.
  void _registerGenerated<TReadModel, TKey>({
    required GeneratedProjection bundle,
    required ProjectionBase<TReadModel, TKey> projection,
    required ReadModelStore<TReadModel, TKey> readModelStore,
    required ProjectionLifecycle lifecycle,
  }) {
    final name = bundle.projectionName;

    // Prevent duplicate registration.
    if (_registrations.containsKey(name)) {
      throw StateError(
        'Projection "$name" is already registered. '
        'Each projection must have a unique name.',
      );
    }

    // Store the generated bundle for schema tracking.
    _generatedBundles[name] = bundle;

    // Store the registration (cast to Object to store heterogeneous types).
    final registration = ProjectionRegistration<TReadModel, TKey>(
      projection: projection,
      lifecycle: lifecycle,
      readModelStore: readModelStore,
    );
    _registrations[name] = registration as ProjectionRegistration<Object, Object>;

    // Index by event type for fast lookup using generated bundle's types.
    for (final eventType in bundle.handledEventTypes) {
      _eventTypeIndex.putIfAbsent(eventType, () => {}).add(name);
    }
  }

  /// Internal registration method for legacy (non-generated) projections.
  void _register<TReadModel, TKey>({
    required ProjectionBase<TReadModel, TKey> projection,
    required ReadModelStore<TReadModel, TKey> readModelStore,
    required ProjectionLifecycle lifecycle,
  }) {
    final name = projection.projectionName;

    // Prevent duplicate registration.
    if (_registrations.containsKey(name)) {
      throw StateError(
        'Projection "$name" is already registered. '
        'Each projection must have a unique name.',
      );
    }

    // Store the registration (cast to Object to store heterogeneous types).
    final registration = ProjectionRegistration<TReadModel, TKey>(
      projection: projection,
      lifecycle: lifecycle,
      readModelStore: readModelStore,
    );
    _registrations[name] = registration as ProjectionRegistration<Object, Object>;

    // Index by event type for fast lookup.
    for (final eventType in projection.handledEventTypes) {
      _eventTypeIndex.putIfAbsent(eventType, () => {}).add(name);
    }
  }

  /// Returns all inline projections that handle the given event type.
  List<ProjectionRegistration<Object, Object>> getInlineProjectionsForEventType(
    Type eventType,
  ) {
    return _getProjectionsForEventType(eventType, ProjectionLifecycle.inline);
  }

  /// Returns all async projections that handle the given event type.
  List<ProjectionRegistration<Object, Object>> getAsyncProjectionsForEventType(
    Type eventType,
  ) {
    return _getProjectionsForEventType(eventType, ProjectionLifecycle.async);
  }

  /// Internal lookup method.
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

  /// Returns all inline projection registrations.
  List<ProjectionRegistration<Object, Object>> get inlineProjections {
    return _registrations.values.where((reg) => reg.lifecycle == ProjectionLifecycle.inline).toList();
  }

  /// Returns all async projection registrations.
  List<ProjectionRegistration<Object, Object>> get asyncProjections {
    return _registrations.values.where((reg) => reg.lifecycle == ProjectionLifecycle.async).toList();
  }

  /// Returns the total number of registered projections.
  int get length => _registrations.length;

  /// Returns whether any projections are registered.
  bool get isEmpty => _registrations.isEmpty;

  /// Returns whether any projections are registered.
  bool get isNotEmpty => _registrations.isNotEmpty;

  /// Returns whether any inline projections are registered.
  bool get hasInlineProjections => inlineProjections.isNotEmpty;

  /// Returns whether any async projections are registered.
  bool get hasAsyncProjections => asyncProjections.isNotEmpty;

  /// Gets the generated bundle for a projection, if registered with one.
  ///
  /// Returns null for projections registered without a generated bundle
  /// (using the legacy [registerInline] or [registerAsync] methods).
  GeneratedProjection? getGeneratedBundle(String projectionName) {
    return _generatedBundles[projectionName];
  }

  /// Gets the schema hash for a projection.
  ///
  /// Returns the schema hash from the generated bundle if available,
  /// or an empty string for projections registered without a bundle.
  String getSchemaHash(String projectionName) {
    return _generatedBundles[projectionName]?.schemaHash ?? '';
  }
}
