/// Continuum UoW — Unit of Work session engine.
///
/// Provides the session lifecycle engine: identity map, operation
/// recording, atomic commit, transactional runner, and the extension
/// point for custom persistence strategies.
library;

export 'src/backward_compatibility.dart';
export 'src/commit_handler.dart';
export 'src/concurrency_exception.dart';
export 'src/invalid_operation_exception.dart';
export 'src/partial_save_exception.dart';
export 'src/session.dart';
export 'src/session_base.dart';
export 'src/session_store.dart';
export 'src/tracked_entity.dart';
export 'src/transactional_runner.dart';
export 'src/unsupported_operation_exception.dart';
