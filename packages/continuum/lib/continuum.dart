/// Continuum - Core types and annotations for event-sourced aggregates.
///
/// Provides annotations, event contracts, identity types, and dispatch
/// registries used by generated code. Persistence and session types
/// are in separate packages: `continuum_event_sourcing`, `continuum_state`,
/// and `continuum_uow`.
library;

// Re-export Ulid-based EventId from zooper_flutter_core
export 'package:zooper_flutter_core/zooper_flutter_core.dart' show EventId;

// Annotations for code generation discovery
export 'src/annotations/aggregate_event.dart';
export 'src/annotations/projection.dart';

// Continuum event base contract
export 'src/events/continuum_event.dart';

// Exceptions
export 'src/exceptions/invalid_creation_event_exception.dart';
export 'src/exceptions/stream_not_found_exception.dart';
export 'src/exceptions/unknown_event_type_exception.dart';
export 'src/exceptions/unsupported_operation_exception.dart';

// Strong identity types
export 'src/identity/stream_id.dart';

// Operation marker interface
export 'src/operations/operation.dart';

// Core persistence types used by generated code
export 'src/persistence/dispatch_registries.dart';
export 'src/persistence/event_application_mode.dart';
export 'src/persistence/event_registry.dart';
export 'src/persistence/event_serializer_registry.dart';
export 'src/persistence/generated_aggregate.dart';

// Projection system
export 'src/projections/generated_projection.dart';
export 'src/projections/inline_projection_executor.dart';
export 'src/projections/multi_stream_projection.dart';
export 'src/projections/projection_base.dart';
export 'src/projections/projection_lifecycle.dart';
export 'src/projections/projection_registration.dart';
export 'src/projections/projection_registry.dart';
export 'src/projections/read_model_result.dart';
export 'src/projections/read_model_store.dart';
export 'src/projections/single_stream_projection.dart';
export 'src/projections/unsupported_projection_operation_exception.dart';
