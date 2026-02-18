import 'package:continuum/continuum.dart';

import '../persistence/stored_event.dart';
import 'projection.dart';

/// Projection that derives a read model from a single aggregate stream.
///
/// Uses the event's [StreamId] as the read model key. Subclasses
/// implement [createInitial] and [apply] for domain-specific logic.
abstract class SingleStreamProjection<TReadModel> extends ProjectionBase<TReadModel, StreamId> {
  @override
  StreamId extractKey(StoredEvent event) => event.streamId;

  @override
  TReadModel createInitial(StreamId streamId);

  @override
  TReadModel apply(TReadModel current, StoredEvent event);
}
