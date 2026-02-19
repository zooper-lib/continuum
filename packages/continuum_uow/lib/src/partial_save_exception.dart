import 'package:continuum/continuum.dart';

/// Thrown when a multi-stream save partially succeeds.
///
/// During a session's [saveChangesAsync], each stream may be persisted
/// independently. When some streams succeed and others fail, this
/// exception reports which streams were saved and which failed.
/// Successfully saved streams have their pending operations cleared;
/// failed streams retain theirs.
///
/// This exception is never thrown for single-stream saves (the original
/// exception propagates directly) or when all streams fail (the first
/// failure is thrown directly).
final class PartialSaveException implements Exception {
  /// Stream IDs that were successfully persisted.
  final List<StreamId> savedStreams;

  /// Stream IDs that failed to persist.
  final List<StreamId> failedStreams;

  /// The exception from the first failed stream.
  final Object cause;

  /// Creates a partial save exception with the saved/failed stream
  /// lists and the original [cause].
  const PartialSaveException({
    required this.savedStreams,
    required this.failedStreams,
    required this.cause,
  });

  @override
  String toString() =>
      'PartialSaveException: ${savedStreams.length} streams saved, '
      '${failedStreams.length} streams failed. Cause: $cause';
}
