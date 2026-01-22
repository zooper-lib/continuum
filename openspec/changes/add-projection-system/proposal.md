# Change: Add Projection and Read-Model System

## Why

Continuum currently supports event sourcing with aggregate persistence, but lacks a way to automatically maintain read models from events. Users must manually subscribe to events, track positions, and update read models—a tedious and error-prone process.

A projection system enables:
- Automatic read-model updates when events are appended
- Both strongly consistent (inline) and eventually consistent (async) execution models
- Single-stream and multi-stream projections
- Zero runtime user interaction after initial configuration

## What Changes

- **ADDED**: Projection abstraction defining how events mutate read models
- **ADDED**: Single-stream projections (one read model per aggregate stream)
- **ADDED**: Multi-stream projections (aggregated read models across streams)
- **ADDED**: Inline projection execution (synchronous, strongly consistent)
- **ADDED**: Async projection execution (background, eventually consistent)
- **ADDED**: Projection registry for automatic event routing
- **ADDED**: Read model storage abstraction
- **ADDED**: Position tracking for async projection recovery
- **ADDED**: Background projection processor
- **MODIFIED**: `EventSourcingStore` to accept projection configuration
- **MODIFIED**: `Session.saveChangesAsync()` to trigger inline projections

## Impact

- Affected specs: `continuum-persistence`, new `continuum-projections` capability
- Affected code:
  - `packages/continuum/lib/src/persistence/event_sourcing_store.dart`
  - `packages/continuum/lib/src/persistence/session_impl.dart`
  - New files under `packages/continuum/lib/src/projections/`
- Breaking changes: None (additive feature)
- Migration: None required; existing code continues to work without projections
