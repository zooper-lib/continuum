/// Defines the execution lifecycle for a projection.
///
/// The lifecycle determines when and how a projection is executed
/// in response to new events.
enum ProjectionLifecycle {
  /// Inline projections are executed synchronously during event persistence.
  ///
  /// Characteristics:
  /// - Part of the same logical unit of work as the event append
  /// - Failure aborts the entire event append operation
  /// - Read models are immediately consistent after save completes
  /// - Increases write latency but provides strong consistency
  inline,

  /// Async projections are executed by a background processor.
  ///
  /// Characteristics:
  /// - Event append completes immediately without waiting for projection
  /// - Processed asynchronously by the projection processor
  /// - Eventually consistent—read models may lag behind writes
  /// - Lower write latency but temporary inconsistency is possible
  async,
}
