import 'package:continuum/continuum.dart';

/// Tracks the state of an entity within a session's identity map.
///
/// Holds the cached entity instance, its runtime type, the version
/// when loaded, and any pending (uncommitted) operations. Used by
/// [SessionBase] to manage the identity map entries.
final class TrackedEntity {
  /// The cached entity instance.
  final Object entity;

  /// The runtime type of the entity for registry lookups.
  final Type entityType;

  /// The version when the entity was loaded (or -1 for new entities).
  final int loadedVersion;

  /// Pending operations not yet persisted.
  final List<Operation> pendingOperations;

  /// Creates a tracked entity for identity map tracking.
  ///
  /// The [pendingOperations] list defaults to an empty list if not
  /// provided. All fields are required except [pendingOperations].
  TrackedEntity({
    required this.entity,
    required this.entityType,
    required this.loadedVersion,
    List<Operation>? pendingOperations,
  }) : pendingOperations = pendingOperations ?? [];

  /// Creates a copy with an empty pending operations list.
  ///
  /// The entity, entityType, and loadedVersion are preserved. Only
  /// the pending operations are cleared. Used by discard operations
  /// to reset pending state without removing the entity from the
  /// identity map.
  TrackedEntity withClearedPendingOperations() {
    return TrackedEntity(
      entity: entity,
      entityType: entityType,
      loadedVersion: loadedVersion,
      pendingOperations: [],
    );
  }
}
