import 'package:continuum/continuum.dart';

import 'commit_handler.dart';

/// Executes multiple commit handlers sequentially.
///
/// Each handler is called with the same [CommitBatch] in the order they
/// appear in [handlers]. If any handler throws, the exception propagates
/// immediately and subsequent handlers are not called.
///
/// Example:
/// ```dart
/// final handler = CompositeCommitHandler([
///   ProjectionCommitHandler(projectionExecutor),
///   EventBusCommitHandler(eventBus),
///   AnalyticsCommitHandler(analytics),
/// ]);
///
/// final runner = TransactionalRunner(
///   store: store,
///   commitHandler: handler,
/// );
/// ```
final class CompositeCommitHandler implements CommitHandler {
  /// Creates a composite handler that executes [handlers] sequentially.
  const CompositeCommitHandler(this.handlers);

  /// The handlers to execute in order.
  final List<CommitHandler> handlers;

  @override
  Future<void> onCommitAsync(CommitBatch batch) async {
    for (final handler in handlers) {
      await handler.onCommitAsync(batch);
    }
  }
}
