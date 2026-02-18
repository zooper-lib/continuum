import '../identity/stream_id.dart';
import '../operations/operation.dart';
import 'projection_base.dart';

/// Projection that derives a read model from a single aggregate stream.
///
/// Uses [StreamId] as the read model key. Subclasses implement
/// [extractKey], [createInitial], and [apply] for domain-specific logic.
///
/// Unlike multi-stream projections, the key type is fixed to [StreamId]
/// which represents a single aggregate instance.
abstract class SingleStreamProjection<TReadModel> extends ProjectionBase<TReadModel, StreamId> {
  @override
  StreamId extractKey(Operation operation);

  @override
  TReadModel createInitial(StreamId streamId);

  @override
  TReadModel apply(TReadModel current, Operation operation);
}
