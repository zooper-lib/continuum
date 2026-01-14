# Change: Mark creation events on the event annotation

## Why
Creation events are currently inferred by scanning aggregate static `create*` methods. This makes event classification dependent on aggregate implementation order and naming, and can lead to surprising generator output (e.g. an event stops requiring an `apply<Event>` method just because a `create*` method exists).

## What Changes
- **BREAKING**: Creation vs mutation events are determined by an explicit flag on the event annotation (e.g. `@AggregateEvent(creation: true, ...)`) instead of by scanning aggregate static methods.
- The generator validates that every creation event has a corresponding aggregate factory method `createFrom<EventName>(EventType event)`.
- A new lint warns when an aggregate is missing one or more required `createFrom<EventName>` factory methods for its creation events.

## Impact
- Affected capabilities/specs:
  - `continuum-core` (annotation API)
  - `continuum-generator` (event classification + validation)
  - `continuum-lints` (new warning)
- Affected code:
  - `packages/continuum/lib/src/annotations/aggregate_event.dart`
  - `packages/continuum_generator/lib/src/aggregate_discovery.dart` (and related models/emitter)
  - `packages/continuum_lints/lib/src/*`

## Migration Notes
- For each aggregate creation event, add `creation: true` to its `@AggregateEvent(...)`.
- Ensure the aggregate defines `static <Aggregate> createFrom<EventName>(<EventName> event)` for each creation event.
