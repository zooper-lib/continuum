/// Continuum - An event sourcing library for Dart.
///
/// Provides annotations, types, and persistence abstractions for building
/// event-sourced aggregates with code generation support.
library;

// Annotations for code generation discovery
export 'src/annotations/aggregate.dart';
export 'src/annotations/aggregate_event.dart';

// Continuum event base contract
export 'src/events/continuum_event.dart';

// Exceptions used by generated code and persistence
export 'src/exceptions/concurrency_exception.dart';
export 'src/exceptions/invalid_creation_event_exception.dart';
export 'src/exceptions/stream_not_found_exception.dart';
export 'src/exceptions/unknown_event_type_exception.dart';
export 'src/exceptions/unsupported_event_exception.dart';

// Strong identity types
export 'src/identity/event_id.dart';
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
export 'src/persistence/session.dart';
export 'src/persistence/stored_event.dart';
