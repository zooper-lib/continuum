import '../persistence/stored_event.dart';
import 'projection.dart';

/// Projection that derives a read model from events across multiple streams.
///
/// Unlike [SingleStreamProjection], the key extraction is user-defined
/// and can span multiple aggregate instances.
abstract class MultiStreamProjection<TReadModel, TKey> extends ProjectionBase<TReadModel, TKey> {
  @override
  TKey extractKey(StoredEvent event);

  @override
  TReadModel createInitial(TKey key);

  @override
  TReadModel apply(TReadModel current, StoredEvent event);
}
