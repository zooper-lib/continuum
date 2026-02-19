/// Controls when domain events mutate the in-memory aggregate during a session.
///
/// Configured at the store level and propagated to all sessions created
/// by that store. The mode determines whether [ContinuumSession.applyAsync]
/// applies the event handler immediately or defers application until
/// [ContinuumSession.saveChangesAsync].
enum EventApplicationMode {
  /// Events mutate the in-memory aggregate immediately when
  /// [ContinuumSession.applyAsync] is called.
  ///
  /// The returned aggregate reflects post-event state. This is the
  /// natural default for most event-sourcing workflows that need to
  /// read post-event state (check invariants, compute derived values,
  /// conditionally apply further events).
  eager,

  /// Events are recorded but not applied until
  /// [ContinuumSession.saveChangesAsync] succeeds.
  ///
  /// The returned aggregate reflects pre-event state throughout the
  /// transaction. Useful when the backend is the authority and the
  /// client should not see uncommitted state.
  deferred,
}
