/// The lowest-common-denominator mutation type.
///
/// An operation describes what happened and carries only domain data —
/// no identity, no timestamp, no metadata. This is the abstraction the
/// session engine (Unit of Work) works with, allowing it to function
/// independently of any specific persistence strategy.
///
/// [ContinuumEvent] implements [Operation], so all events are valid
/// operations. Custom persistence strategies can define their own
/// operation types that implement this interface without needing
/// event-sourcing metadata.
abstract interface class Operation {}
