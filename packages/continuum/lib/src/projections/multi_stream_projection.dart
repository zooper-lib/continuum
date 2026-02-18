import '../operations/operation.dart';
import 'projection_base.dart';

/// Projection that derives a read model from operations across multiple streams.
///
/// Unlike [SingleStreamProjection], the key extraction is user-defined
/// and can span multiple aggregate instances. The key type [TKey]
/// determines how read models are partitioned.
abstract class MultiStreamProjection<TReadModel, TKey> extends ProjectionBase<TReadModel, TKey> {
  @override
  TKey extractKey(Operation operation);

  @override
  TReadModel createInitial(TKey key);

  @override
  TReadModel apply(TReadModel current, Operation operation);
}
