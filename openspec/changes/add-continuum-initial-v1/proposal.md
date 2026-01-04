# Change: Add Continuum initial v1 implementation

## Why
The repository currently contains only a stub Dart package, but the project’s intended architecture is fully specified in `doc/draft/specs.md`.
This change establishes the initial v1 of Continuum: a lightweight core for domain events and aggregate event application, plus an optional persistence layer and reference EventStore implementations.

## What Changes
- Introduces initial OpenSpec capability specs for:
  - `continuum-core` (annotations, strong types, base event model, exceptions)
  - `continuum-generator` (code generation contracts + dispatchers + registry)
  - `continuum-persistence` (Session/EventStore/serialization abstractions + store root)
  - `continuum-store-memory` (in-memory EventStore for tests)
  - `continuum-store-hive` (Hive-backed EventStore)
- Defines the packaging plan for a mono-repo under `packages/`.
- Defines test/validation expectations for v1 behavior.

## Non-Goals (v1)
- Projections/read models
- Snapshots
- Command bus/pipeline
- Automatic message bus publishing
- Multi-device synchronization

## Impact
- Affected code: new/expanded packages under `packages/` (core, generator, stores).
- Affected specs: adds new capabilities (no prior specs exist).
- Compatibility: first stable API surface; future changes may require additional OpenSpec deltas.
