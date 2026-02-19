/// Continuum State — State-based persistence strategy.
///
/// Provides adapter-driven aggregate persistence for backends that
/// store full aggregate state (REST APIs, databases, GraphQL) rather
/// than event streams. Reuses the shared session lifecycle from
/// `continuum_uow`.
library;

export 'src/exceptions/permanent_adapter_exception.dart';
export 'src/exceptions/transient_adapter_exception.dart';
export 'src/persistence/aggregate_persistence_adapter.dart';
export 'src/persistence/state_based_session.dart';
export 'src/persistence/state_based_store.dart';
