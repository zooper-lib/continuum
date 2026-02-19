import 'package:continuum/continuum.dart';

import 'commit_handler.dart';

/// Commit handler that delegates to a user-provided async callback.
///
/// Enables lightweight post-commit processing without requiring a
/// dedicated class — pass any `Future<void> Function(CommitBatch)`
/// callback to handle committed operations.
final class AsyncProjectionCommitHandler implements CommitHandler {
  /// The callback invoked with the committed batch.
  final Future<void> Function(CommitBatch batch) _callback;

  /// Creates a handler that invokes [callback] with each committed batch.
  const AsyncProjectionCommitHandler(
    Future<void> Function(CommitBatch batch) callback,
  ) : _callback = callback;

  @override
  Future<void> onCommitAsync(CommitBatch batch) async {
    await _callback(batch);
  }
}
