import 'session.dart';

/// Factory interface for creating sessions.
///
/// Implementations create sessions wired to their specific persistence
/// backend. Used by [TransactionalRunner] to open sessions automatically
/// within transactional scopes.
abstract interface class SessionStore {
  /// Opens a new session for performing aggregate operations.
  ///
  /// Each call creates a fresh session with an empty identity map.
  /// Sessions are short-lived and should not be reused after
  /// [Session.saveChangesAsync] is called.
  Session openSession();
}
