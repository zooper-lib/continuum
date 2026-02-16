import '../events/continuum_event.dart';

/// Pluggable interface for post-commit side effects.
///
/// Receives the list of domain events after they have been durably
/// persisted. Implementations can publish to an event bus, execute
/// projections, send analytics, or perform any other post-commit work.
///
/// After-persist semantics: the handler is called only after
/// [ContinuumSession.saveChangesAsync] succeeds. If the handler throws,
/// committed events remain persisted — no rollback occurs. The exception
/// propagates to the caller.
abstract interface class CommitHandler {
  /// Called after events have been successfully persisted.
  ///
  /// The [events] list contains all domain events from the commit,
  /// ordered by stream in persistence order. The handler receives
  /// events only — not aggregate instances or aggregate state.
  ///
  /// Not called when the commit is empty (no pending events were saved).
  Future<void> onCommitAsync(List<ContinuumEvent> events);
}
