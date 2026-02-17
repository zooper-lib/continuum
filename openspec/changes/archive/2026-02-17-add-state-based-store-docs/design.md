## Context

The `StateBasedStore`, `StateBasedSession`, and adapter exception types were implemented in the `add-state-based-store` change. The code is complete and tested (272 tests pass), but the README, examples, and developer-facing documentation have not been updated. Users currently have no way to discover or learn about state-based persistence without reading source code.

The README has a "Three Usage Modes" section where Mode 3 ("Hybrid with Backend") describes the exact use case `StateBasedStore` enables — but the code snippets there show manual aggregate construction, not the actual store API. There are also three hybrid example files (`hybrid_optimistic_creation.dart`, `hybrid_profile_edit.dart`, `hybrid_multi_step_form.dart`) that predate the store implementation and use the same manual approach.

## Goals / Non-Goals

**Goals:**

- Document `StateBasedStore` construction API and `AggregatePersistenceAdapter` implementation in the README
- Create a runnable example showing the full adapter → store → session → save flow
- Update the README's Mode 3 quick-start snippet to use `StateBasedStore` instead of manual aggregate construction
- Keep documentation style and depth consistent with existing README sections (Event Sourcing Store, TransactionalRunner, etc.)

**Non-Goals:**

- Rewriting the three existing hybrid examples to use `StateBasedStore` — they demonstrate a valid manual pattern and remain useful as-is
- Creating a separate developer guide document — the README is sufficient for now
- Documenting `SessionBase` internals — that's an implementation detail, not user-facing API

## Decisions

### 1. Add a "State-Based Store" section under "Core Concepts"

**Decision:** Place the new section directly after the existing "Event Sourcing Store" section, mirroring its structure: construction snippet, brief explanation, key properties.

**Rationale:** Users scanning the README will naturally encounter both store types in sequence. The parallel structure makes the swappability obvious — same `openSession()` → `applyAsync` → `saveChangesAsync` pattern, different backing.

### 2. Show a concrete `AggregatePersistenceAdapter` implementation in the README

**Decision:** Include a minimal adapter implementation (e.g., `UserApiAdapter`) that shows `fetchAsync` and `persistAsync` with fake HTTP calls, so users understand what they need to implement.

**Rationale:** The adapter is the user's main extension point. Without an example, the abstract interface is hard to grok. A concrete implementation (even a simplified one) makes the contract clear.

### 3. Create `store_state_based.dart` as a standalone runnable example

**Decision:** One new example file under `example/lib/` showing `StateBasedStore` end-to-end: define a fake adapter, construct the store, open a session, apply events, save, load.

**Rationale:** Follows the existing example pattern (`store_creating_streams.dart`, `store_loading_and_updating.dart`, etc.). Users can `dart run` it to see the flow in action.

### 4. Update Mode 3 quick-start snippet only

**Decision:** Replace the Mode 3 code block in "Quick Start → Use Your Aggregate" with a `StateBasedStore` snippet. Leave the three standalone hybrid example files unchanged.

**Rationale:** The hybrid examples demonstrate a different (valid) pattern — manual event application for optimistic UI without any store. They're complementary, not obsolete. The Mode 3 quick-start snippet is where users first encounter the hybrid concept and should show the primary API.

## Risks / Trade-offs

- **[Example becomes stale]** → The example uses a fake adapter, not a real HTTP client. If the `AggregatePersistenceAdapter` interface changes, the example breaks. Mitigation: the example lives in `example/lib/` which is analyzed by CI, so compilation failures are caught.
- **[README length]** → Adding another store section increases README size. Mitigation: keep it concise (same depth as the Event Sourcing Store section, ~30 lines).
