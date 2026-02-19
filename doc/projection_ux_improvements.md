# Projection UX improvements (design notes)

Date: 2026-02-18

This document captures:

- What feels “too manual” in the current projection workflow.
- What can be automated (especially via code generation).
- A proposed redesign that intentionally breaks backward compatibility.
- A clear explanation of “commit batches” and why they matter.
- A concrete plan to ship **both** an inline projection commit handler and an async projection commit handler.

## What I observed in the current example

The current example is in:

- [packages/continuum/example/lib/projection_example.dart](../packages/continuum/example/lib/projection_example.dart)
- [packages/continuum/example/lib/domain/projections/user_profile_projection.dart](../packages/continuum/example/lib/domain/projections/user_profile_projection.dart)

It demonstrates a projection that updates a read model automatically after each unit-of-work commit.

### What’s already good

- `@Projection(...)` + generator-created dispatch mixin gives a clean, type-safe handler surface.
- The “executor runs after commit” semantics are a good default for consistency.

### What’s not a great user experience

#### 1) Too much wiring for “hello projections”
The app has to manually:

- Create `ReadModelStore`.
- Create `ProjectionRegistry`.
- `registerInline(projection, store)`.
- Create `InlineProjectionExecutor`.
- Bridge it into the UoW system with a custom commit handler adapter.

This is correct, but it is a lot of code for something that should feel first-class.

#### 2) `SingleStreamProjection` still requires manual key extraction
A single-stream projection should be keyed by `StreamId` with almost no user work.

Today, inline projection execution receives only `List<Operation>`. An `Operation` has no stream identity.

Result: the user must implement `extractKey(Operation)` and often ends up:

- Duplicating identity into every event payload.
- Writing repetitive `switch` statements.
- Handling nullability (`userId!`) across multiple events.

In other words: the runtime API forces projection authors to do work that the persistence/session layer already knows.

#### 3) Inline vs async projections have different “available context”
Async projection execution works over stored events, which already include `streamId`, `version`, `globalSequence`, etc.

Inline execution works over “just operations” and therefore has *less* context, even though it runs right after persistence.

That mismatch is the root cause of (2).

## Goal (UX)

A projection should feel like:

- “I declare handlers. I provide an initial read model. That’s it.”

Wiring should be:

- “I declare read model stores once; the registry registers everything with one call.”

## Key redesign: Commit batches (breaking change)

### What is a commit batch?
A **commit batch** is the full set of things that were persisted by a transaction, including the identity of *which stream* each operation belongs to and any persistence metadata.

Conceptually:

- A transaction can touch multiple streams.
- Each stream can have multiple operations.
- After persistence, we want to run side-effects (projections, event bus, analytics) with full context.

So instead of calling commit hooks with `List<Operation>`, we call them with a richer object:

- `CommitBatch`

Where `CommitBatch` contains a list of `CommittedOperation` entries.

### Why `List<Operation>` is insufficient
`Operation` is intentionally the “lowest common denominator” domain mutation type. It has no:

- `StreamId`
- stream version
- global sequence
- persistence metadata

But projections (especially single-stream) almost always need at least `StreamId`.

Without it, the framework forces the user to:

- encode stream identity into every operation, and
- rebuild identity with switches.

That is unnecessary because the session/persistence layer already knows the stream.

### Proposed commit batch shape
This is a *design*, not exact code.

- `CommitBatch`
  - `List<CommittedOperation> entries`
  - `DateTime committedAt` (optional)

- `CommittedOperation`
  - `StreamId streamId`
  - `Operation operation`
  - `int? streamVersion` (optional; present for event-sourced stores)
  - `int? globalSequence` (optional; present if the store supports it)
  - `Map<String, Object?> metadata` (optional)

Important: `CommittedOperation.operation` stays as `Operation` to keep the domain layer clean.

### How commit batches remove boilerplate in projections
With commit batches, inline projection execution receives `streamId` alongside the operation.

For **single-stream projections**, the key is simply:

- `key = committedOperation.streamId`

So `SingleStreamProjection` can drop `extractKey` entirely.

For **multi-stream projections**, key extraction stays user-defined because multi-stream projections genuinely map events to external keys (e.g., “by customer id”, “by tenant id”, “by category id”).

### Non-goals
Commit batches are not meant to make domain events “fat”. They are meant to keep domain operations small while still giving post-commit systems the context they need.

## API changes (breaking; no backward compatibility)

### 1) Replace commit handlers to use commit batches
Current UoW commit hook API is:

- `CommitHandler.onCommitAsync(List<Operation> committedOperations)`

Proposed (breaking):

- `CommitHandler.onCommitAsync(CommitBatch batch)`

This removes the need for adapters and makes the “post commit” contract future-proof.

### 2) Make the UoW return a commit batch
Instead of `Session.saveChangesAsync()` returning a list of operations, it should return `CommitBatch`.

This has a very nice property:

- `TransactionalRunner` can commit and pass the exact same `CommitBatch` to the commit handler.

### 3) Projection base types

#### Single-stream projections
A true single-stream projection should not require `extractKey`.

Proposed:

- `abstract class SingleStreamProjection<TReadModel>`
  - `TReadModel createInitial(StreamId streamId)`
  - `TReadModel apply(TReadModel current, Operation operation)` (generated dispatch)

The executor supplies the key (stream id) from the commit batch.

#### Multi-stream projections
Multi-stream projections keep key extraction:

- `abstract class MultiStreamProjection<TReadModel, TKey>`
  - `TKey extractKey(Operation operation)`
  - `TReadModel createInitial(TKey key)`
  - `TReadModel apply(TReadModel current, Operation operation)` (generated dispatch)

## First-class commit handlers to ship

You pointed out correctly: if we export/ship an inline projection commit handler, the UX expectation is that we also ship an async one.

### A) Inline: ProjectionCommitHandler
A framework-provided commit handler that runs inline projections immediately after persistence:

- `ProjectionCommitHandler` (in the UoW layer or a small “wiring” package)
  - takes `InlineProjectionExecutor`
  - implements `CommitHandler`
  - on commit: calls `executor.executeAsync(batch)`

Key point: after the commit batch redesign, the inline executor should accept a `CommitBatch` (or entries) rather than `List<Operation>`.

### B) Async: AsyncProjectionCommitHandler
A framework-provided commit handler that schedules or triggers async projections.

There are two viable models:

#### Model B1: “enqueue committed entries”
- commit handler receives `CommitBatch`
- it pushes entries into an async queue (in-memory, persistent, or user-provided)
- a background worker consumes entries and applies them using an async executor

Pros:
- works even for non-event-sourcing stores
- does not require reloading from an event store

Cons:
- requires a queue abstraction and delivery semantics (at-least-once vs exactly-once)

#### Model B2: “event-sourcing only; process stored events by position”
- commit handler receives `CommitBatch`
- it does not carry domain-only operations; it carries “stored event metadata” too
- the handler calls an `AsyncProjectionExecutor` with the committed stored events directly

Pros:
- leverages `globalSequence` and projection positions
- fits the existing async executor shape

Cons:
- depends on event-sourcing semantics and a stable stored-event envelope

Recommendation:

- Prefer B1 as the general solution.
- Keep B2 as an optimized integration for event-sourcing stores.

With “no backward compatibility” allowed, we can design the commit batch so B2 is possible without layering problems by including optional `globalSequence` and a standard metadata map.

## Code generation improvements (reduce wiring)

Today generation provides:

- a handler mixin and dispatch for each projection
- a `$projectionList` of discovered projections

That still leaves the app to manually:

- instantiate projections
- instantiate stores
- choose lifecycle
- register each projection

### Proposed generator output: registration glue
Generate a small “projection module contract” and registration extension.

Example shape:

- a generated interface that describes required dependencies (projection instances and stores)
- a generated registry extension that registers all projections

This makes app wiring collapse to something like:

- create your stores and projection instances (often via DI)
- call one method to register them all

This is also a good place to enforce “projection name uniqueness” and surface better error messages.

## Immediate documentation improvement

Even if the runtime API is unchanged, the docs should explicitly call out:

- why single-stream projections currently need `extractKey`
- that the reason is lack of commit context

But with the commit batch redesign, that documentation becomes unnecessary because the framework handles it.

## Summary of the highest-impact changes

Breaking changes that significantly improve UX:

1) Replace commit handler input from `List<Operation>` to `CommitBatch`.
2) Make sessions/runner produce and propagate commit batches.
3) Remove `extractKey` from single-stream projections; use `StreamId` from the commit batch.
4) Ship both:
   - `ProjectionCommitHandler` (inline)
   - `AsyncProjectionCommitHandler` (async)
5) Extend generator to emit projection registration glue so users write less boilerplate.
