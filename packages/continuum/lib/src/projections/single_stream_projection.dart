import '../identity/stream_id.dart';
import '../operations/operation.dart';
import 'projection_base.dart';

/// Projection that derives a read model from a single aggregate stream.
///
/// Uses [StreamId] as the read model key. Subclasses implement
/// [createInitial] and [apply] for domain-specific logic.
///
/// Key extraction is handled automatically by the framework — the
/// executor derives the [StreamId] from the [CommittedEntry] that
/// carries each operation, so subclasses do not implement [extractKey].
abstract class SingleStreamProjection<TReadModel> extends ProjectionBase<TReadModel, StreamId> {
  /// Key extraction is handled by the executor via [CommittedEntry.streamId].
  ///
  /// This override exists only to satisfy the [ProjectionBase] contract.
  /// It must not be called directly — the inline and async executors
  /// bypass it for single-stream projections.
  @override
  StreamId extractKey(Operation operation) {
    throw UnsupportedError(
      'SingleStreamProjection does not use extractKey. '
      'The executor derives the key from CommittedEntry.streamId.',
    );
  }

  @override
  TReadModel createInitial(StreamId streamId);

  @override
  TReadModel apply(TReadModel current, Operation operation);
}
