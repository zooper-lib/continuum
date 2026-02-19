import 'package:bounded/bounded.dart';
import 'package:zooper_flutter_core/zooper_flutter_core.dart';

import '../operations/operation.dart';

/// Base contract for all continuum events in an event-sourced system.
///
/// Continuum events represent facts that have happened in the domain.
/// They are immutable and carry all the information needed to describe
/// what occurred.
///
/// Continuum is compatible with pure unit-test usage (no event store needed).
/// Events are identified, timestamped, and can carry arbitrary metadata.
///
/// Implementations should ensure [id], [occurredOn], and [metadata] are
/// immutable.
///
/// Implements [Operation] so that the Unit of Work session engine can
/// process events alongside other operation types.
abstract interface class ContinuumEvent implements BoundedDomainEvent<EventId>, Operation {}
