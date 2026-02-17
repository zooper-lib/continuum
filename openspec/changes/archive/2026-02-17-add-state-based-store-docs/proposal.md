## Why

The `StateBasedStore` and `StateBasedSession` implementations were added in the `add-state-based-store` change, but the README, examples, and developer docs don't mention them. Users discovering Continuum have no way to learn about state-based persistence without reading source code. The existing hybrid examples manually construct aggregates and call backend APIs directly — they predate the store abstraction and don't demonstrate the actual `StateBasedStore` API.

## What Changes

- Add a "State-Based Store" section to the README alongside the existing "Event Sourcing Store" section, showing construction API, adapter implementation pattern, and the session lifecycle.
- Create a `store_state_based.dart` example demonstrating end-to-end usage: defining an adapter, constructing a `StateBasedStore`, and using `openSession()` → `applyAsync` → `saveChangesAsync`.
- Update `example/main.dart` index to list the new example under a "STATE-BASED PERSISTENCE" section.
- Update the README's "Mode 3: Hybrid with Backend" quick-start snippet to show `StateBasedStore` instead of manual aggregate construction.

## Capabilities

### New Capabilities

- `state-based-store-docs`: README documentation for `StateBasedStore` construction, `AggregatePersistenceAdapter` implementation, and state-based session usage. Runnable example showing the full adapter → store → session → save flow.

### Modified Capabilities

_(none — no spec-level behavior changes; this is documentation-only)_

## Impact

- **`packages/continuum/README.md`**: New section under "Core Concepts" for `StateBasedStore`; updated Mode 3 quick-start snippet.
- **`packages/continuum/example/lib/store_state_based.dart`**: New runnable example file.
- **`packages/continuum/example/main.dart`**: Updated index listing.
- **No code changes to `lib/`** — purely documentation and examples.
