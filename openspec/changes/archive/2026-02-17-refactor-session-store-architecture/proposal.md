## Why

The current `ContinuumSession` API couples workflow code to persistence strategy. Users must distinguish between `startStream` (creation) and `append` (mutation), `saveChangesAsync` returns `void` (preventing post-commit side effects), session lifecycle is entirely manual (no ambient session, no auto-commit, no event publishing), and the architecture has no path to support non-event-sourced persistence (e.g., backend APIs). This refactor unifies the mutation API, introduces a transactional lifecycle boundary, decouples post-commit side effects, and lays the groundwork for swappable persistence strategies — all without changing workflow code.

## What Changes

- **BREAKING**: Replace `startStream<T>(streamId, event)` and `append(streamId, event)` with a single `applyAsync<T>(streamId, event)` that auto-detects creation vs. mutation via the `AggregateFactoryRegistry`
- **BREAKING**: `saveChangesAsync` returns `Future<List<ContinuumEvent>>` instead of `Future<void>`, reporting all committed events in application order
- Add `TransactionalRunner` — a zone-based unit-of-work manager that opens a session, exposes it as an ambient value, auto-commits on success, and publishes events through a pluggable `CommitHandler`
- Add `CommitHandler` interface for pluggable post-commit side effects (event bus, projections, analytics)
- Decouple `InlineProjectionExecutor` from `SessionImpl` — projections become a `CommitHandler` configured on the runner, not wired internally in the session
- Add `EventApplicationMode` enum (`eager` / `deferred`) to control whether events mutate the in-memory aggregate immediately on `applyAsync` or only after `saveChangesAsync` succeeds
- Introduce `ContinuumStore` as an abstract interface with `openSession()`, making `EventSourcingStore` one implementation and enabling future `StateBasedStore` implementations
- Add `AggregatePersistenceAdapter<T>` interface for state-based persistence — user-provided adapters that handle fetch/hydrate and persist logic for backend APIs

## Capabilities

### New Capabilities

- `unified-mutation-api`: Single `applyAsync<T>(streamId, event)` method that replaces `startStream` and `append`, auto-detecting creation vs. mutation events
- `transactional-runner`: Zone-based `TransactionalRunner` that manages session lifecycle (open → execute → commit → publish) with ambient session access via `TransactionalRunner.currentSession`
- `commit-handler`: Pluggable `CommitHandler` interface for post-commit event publishing, enabling event bus, projection, and analytics integrations
- `event-application-mode`: Configurable eager vs. deferred event application strategy controlling when domain events mutate the in-memory aggregate
- `continuum-store`: Abstract `ContinuumStore` interface with `openSession()` that `EventSourcingStore` implements, enabling swappable persistence strategies
- `aggregate-persistence-adapter`: `AggregatePersistenceAdapter<T>` interface for state-based persistence, allowing user-provided fetch/hydrate and persist logic against backend APIs

### Modified Capabilities

_(No existing specs to modify — `openspec/specs/` is empty.)_

## Impact

- **`continuum` package**: Core session, store, and projection APIs change. `ContinuumSession` loses `startStream`/`append`, gains `applyAsync`. `EventSourcingStore` implements new `ContinuumStore` interface. `SessionImpl` loses internal projection execution.
- **`continuum_generator` package**: Generated code must emit `applyAsync`-compatible factories and appliers (current `AggregateFactoryRegistry` and `EventApplierRegistry` remain structurally compatible — no codegen changes expected).
- **`continuum_store_*` packages**: Store implementations (`hive`, `memory`, `sembast`) are unaffected — they implement `EventStore`, not `ContinuumSession`.
- **User workflow code**: All call sites using `startStream`/`append` must migrate to `applyAsync`. Call sites inspecting `saveChangesAsync` return type must update. This is a breaking API change.
- **Projection wiring**: Users currently passing `ProjectionRegistry` to `EventSourcingStore` must instead wire a `ProjectionCommitHandler` on the `TransactionalRunner`. Projection behavior is preserved; only the configuration surface changes.
