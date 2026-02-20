import 'package:continuum_state/src/persistence/target_persistence_adapter.dart';

/// Backward-compatible alias for the old name.
///
/// This API used to be named `AggregatePersistenceAdapter` before the
/// operation-target terminology was introduced.
@Deprecated('Use TargetPersistenceAdapter instead.')
typedef AggregatePersistenceAdapter<TTarget> = TargetPersistenceAdapter<TTarget>;
