import 'session.dart';
import 'session_store.dart';
import 'unsupported_operation_exception.dart';

/// Backward-compatibility typedef for [Session].
///
/// This typedef allows consumers migrating from the old `continuum`
/// package to use the old name while transitioning to the new
/// `continuum_uow` package.
typedef ContinuumSession = Session;

/// Backward-compatibility typedef for [SessionStore].
///
/// This typedef allows consumers migrating from the old `continuum`
/// package to use the old name while transitioning to the new
/// `continuum_uow` package.
typedef ContinuumStore = SessionStore;

/// Backward-compatibility typedef for [UnsupportedOperationException].
///
/// This typedef allows consumers migrating from the old `continuum`
/// package to use the old name while transitioning to the new
/// `continuum_uow` package.
typedef UnsupportedEventException = UnsupportedOperationException;
