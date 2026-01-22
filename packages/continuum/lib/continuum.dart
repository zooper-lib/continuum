/// Continuum - An event sourcing library for Dart.
///
/// Provides annotations, types, and persistence abstractions for building
/// event-sourced aggregates with code generation support.
library;

// Re-export Ulid-based EventId from zooper_flutter_core
export 'package:zooper_flutter_core/zooper_flutter_core.dart' show EventId;

// Annotations for code generation discovery
export 'src/annotations/aggregate_event.dart';
export 'src/annotations/projection.dart';

// Continuum event base contract
export 'src/events/continuum_event.dart';

// Exceptions used by generated code and persistence
export 'src/exceptions/concurrency_exception.dart';
export 'src/exceptions/invalid_creation_event_exception.dart';
export 'src/exceptions/stream_not_found_exception.dart';
export 'src/exceptions/unknown_event_type_exception.dart';
export 'src/exceptions/unsupported_event_exception.dart';

// Strong identity types
export 'src/identity/stream_id.dart';

// Persistence abstractions
export 'src/persistence/atomic_event_store.dart';
export 'src/persistence/event_registry.dart';
export 'src/persistence/event_serializer.dart';
export 'src/persistence/event_serializer_registry.dart';
export 'src/persistence/event_sourcing_store.dart';
export 'src/persistence/event_store.dart';
export 'src/persistence/expected_version.dart';
export 'src/persistence/generated_aggregate.dart';
export 'src/persistence/json_event_serializer.dart';
export 'src/persistence/projection_event_store.dart';
export 'src/persistence/session.dart';
export 'src/persistence/stored_event.dart';

// Projection system
export 'src/projections/async_projection_executor.dart';
export 'src/projections/generated_projection.dart';
export 'src/projections/inline_projection_executor.dart';
export 'src/projections/multi_stream_projection.dart';
export 'src/projections/projection.dart';
export 'src/projections/projection_lifecycle.dart';
export 'src/projections/projection_position.dart';
export 'src/projections/projection_position_store.dart';
export 'src/projections/projection_processor.dart';
export 'src/projections/projection_registration.dart';
export 'src/projections/projection_registry.dart';
export 'src/projections/read_model_result.dart';
export 'src/projections/read_model_store.dart';
export 'src/projections/single_stream_projection.dart';
