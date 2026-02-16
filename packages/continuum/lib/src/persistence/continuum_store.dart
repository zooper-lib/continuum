import 'session.dart';

/// Abstract interface for opening persistence sessions.
///
/// Provides a single entry point for creating [ContinuumSession] instances,
/// decoupling workflow code from the concrete persistence strategy. Different
/// implementations (event sourcing, state-based, etc.) provide their own
/// session semantics while exposing the same surface.
abstract interface class ContinuumStore {
  /// Opens a new session for aggregate operations.
  ///
  /// Each session is independent and tracks its own loaded aggregates
  /// and pending events. Sessions should be short-lived and not reused
  /// after [ContinuumSession.saveChangesAsync] is called.
  ContinuumSession openSession();
}
