import 'package:continuum/continuum.dart';

import 'commit_handler.dart';

/// Commit handler that delegates to an [InlineProjectionExecutor].
///
/// Bridges the [CommitHandler] interface with the projection executor,
/// so projections are executed inline during the commit cycle without
/// requiring a hand-written adapter.
final class ProjectionCommitHandler implements CommitHandler {
  /// The executor that processes projections.
  final InlineProjectionExecutor _executor;

  /// Creates a handler that delegates to [executor].
  const ProjectionCommitHandler(InlineProjectionExecutor executor) : _executor = executor;

  @override
  Future<void> onCommitAsync(CommitBatch batch) async {
    await _executor.executeAsync(batch);
  }
}
