# Change: Add projections/read models

## Why
Continuum currently supports event application and persistence, but it lacks a first-class way to build and persist read models. Users need projections that update and save automatically without coupling read models to aggregates or session internals.

## What Changes
- Add a new capability spec for projections/read models.
- Extend persistence abstractions to support global ordered event reads for projection processing (**BREAKING** for `EventStore`).
- Introduce projection storage/checkpoint abstractions to persist read model state safely.
- Provide a projection runner that mutates and saves projections automatically based on stored events.

## Impact
- Affected specs: `continuum-projections` (new), `continuum-persistence` (modified for global event reads).
- Affected code: `packages/continuum` persistence APIs and new projection types; store packages may need updates.
- Compatibility: **BREAKING** change to `EventStore` (new required method).