/// Controls how a projection is executed relative to event persistence.
enum ProjectionLifecycle {
  /// Projection is executed synchronously during [saveChangesAsync],
  /// before the method returns.
  inline,

  /// Projection is scheduled for background processing after events
  /// are persisted.
  async,
}
