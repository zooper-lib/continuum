/// Continuum Event Sourcing — event sourcing persistence strategy.
///
/// Provides event store abstractions, serialization, projection system,
/// and the event-sourcing-specific session implementation that extends
/// the Unit of Work session engine.
library;

// Re-export serialization and aggregate bundle types from continuum core.
// These types are defined in continuum (L0) because the code generator
// produces code that imports package:continuum. Re-exporting them here
// ensures that consumers of continuum_event_sourcing see the same types
// without needing a direct continuum import.
export 'package:continuum/continuum.dart' show EventFromJsonFactory, EventSerializerEntry, EventSerializerRegistry, EventToJsonFactory, GeneratedAggregate;

// Re-export ConcurrencyException from continuum_uow so that store
// implementations can throw it without depending on continuum_uow directly.
export 'package:continuum_uow/continuum_uow.dart' show ConcurrencyException, UnsupportedOperationException;

// Re-export projection types from continuum core so that consumers who
// already import continuum_event_sourcing continue to see them.
export 'package:continuum/continuum.dart'
    show
        GeneratedProjection,
        InlineProjectionExecutor,
        MultiStreamProjection,
        ProjectionBase,
        ProjectionLifecycle,
        ProjectionRegistration,
        ProjectionRegistry,
        ReadModelResult,
        ReadModelStore,
        SingleStreamProjection,
        UnsupportedProjectionOperationException;

export 'src/persistence/atomic_event_store.dart';
export 'src/persistence/event_serializer.dart';
export 'src/persistence/event_sourcing_store.dart';
export 'src/persistence/event_store.dart';
export 'src/persistence/expected_version.dart';
export 'src/persistence/json_event_serializer.dart';
export 'src/persistence/projection_event_store.dart';
export 'src/persistence/session_impl.dart';
export 'src/persistence/stored_event.dart';

export 'src/projections/async_projection_executor.dart';
export 'src/projections/projection_position.dart';
export 'src/projections/projection_position_store.dart';
export 'src/projections/projection_processor.dart';
