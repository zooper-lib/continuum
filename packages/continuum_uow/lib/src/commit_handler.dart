import 'package:continuum/continuum.dart';

/// Pluggable interface for post-commit side effects.
///
/// Called after operations have been durably persisted. Implementations
/// can publish to an event bus, execute projections, send analytics,
/// or perform any other post-commit work.
///
/// After-persist semantics: the handler is called only after
/// [Session.saveChangesAsync] succeeds. If the handler throws,
/// committed operations remain persisted — no rollback occurs. The
/// exception propagates to the caller.
abstract interface class CommitHandler {
  /// Called after operations have been successfully persisted.
  ///
  /// Receives a [CommitBatch] containing the committed operations
  /// grouped by stream. Not called when the action throws, when
  /// [saveChangesAsync] fails, or when no operations were committed
  /// (empty batch).
  Future<void> onCommitAsync(CommitBatch batch);
}
