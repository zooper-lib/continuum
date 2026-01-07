# Project Context

## Purpose
Continuum is a domain event modeling and event sourcing framework for Dart.

The project is designed around **domain events as a modeling tool** that can be used in multiple modes (not only “full event sourcing”). The core goals are:

- Provide a lightweight **core** for typed domain events and aggregate state transitions.
- Provide an optional **persistence layer** (interfaces + tooling) for event sourcing, version tracking, and serialization.
- Use **code generation** instead of reflection to keep runtime dependencies low and keep domain code ergonomic.

## Tech Stack
- Language: Dart (SDK constraint: `^3.10.4` in the current package)
- Package manager/build tooling: Dart `pub`
- Linting: `package:lints` (recommended set via `analysis_options.yaml`)
- Testing: `package:test`

Repository layout is a mono-repo with Dart packages under `packages/` (today: `packages/continuum`).

Planned/expected (per draft architecture docs):

- `continuum_generator` package for generating `*.g.dart` code into consumers’ projects
- Optional EventStore implementations as separate packages (e.g. memory, Hive)

## Project Conventions

### Code Style
- Formatting: use standard `dart format` output.
- Lints: keep code compliant with `package:lints/recommended.yaml`.
- Public API boundary:
	- Public exports live in the package barrel (e.g. `lib/continuum.dart`).
	- Implementation details live in `lib/src/`.
- Keep dependencies minimal:
	- Core should avoid pulling in persistence backends or platform-specific dependencies.
	- Prefer small, composable packages (core, generator, stores).
- Naming conventions (important for generated wiring):
	- Aggregate event handlers are named `apply<EventName>`.
	- Creation factories on aggregates are named `create*` and take exactly one parameter (the creation event).

### Architecture Patterns
Continuum is structured around a two-layer design with three supported usage modes.

**Supported usage modes**

1. **Event-driven aggregate mutation (no persistence):** domain events as typed state transitions; only final state is persisted via CRUD.
2. **Frontend-only event sourcing:** client is source of truth; events are persisted locally and aggregates are rebuilt by replay.
3. **Hybrid mode:** backend is authoritative; frontend uses optimistic event application and can discard pending work.

**Two-layer architecture**

- **Core layer:** annotations, base event types, strong ID types, and event application rules. No persistence implementations.
- **Persistence layer:** session management, event store interfaces, serialization concerns, and expected-version concurrency.

**Domain modeling rules**

- Events are immutable value objects.
- Events are internal modeling constructs (not API contracts).
- Aggregates are plain Dart classes:
	- No base class required.
	- No version field or version mutation inside aggregates.
	- Non-creation events are applied via `apply<EventName>(event)` methods.
	- Creation events construct aggregates via static `create*` methods; creation events do not have apply handlers.

**Code generation**

Because reflection is not suitable for this use case, Continuum relies on code generation to:

- Generate `_$<Aggregate>EventHandlers` contracts for non-creation events.
- Generate `applyEvent()` dispatchers, `replayEvents()` helpers, and creation factories like `createFromEvent()`.
- Generate registries needed for deserialization in persistence scenarios.

Draft design decisions to preserve unless explicitly changed:

- Event IDs use ULID and are wrapped in strong types (avoid raw strings for core identity types).
- Metadata stays a simple `Map<String, dynamic>`.
- Keep core dependency-light; avoid `freezed` as a baseline requirement.
- `json_serializable` is acceptable for persistence scenarios (events need JSON only when persisted/serialized).

### Testing Strategy
- Use `package:test` for unit tests.
- Prefer fast, deterministic tests; avoid relying on wall-clock time unless injected/controlled.
- Persistence/store implementations should have contract-style tests (e.g., EventStore append/load semantics) plus backend-specific tests.
- Generated code should be exercised via integration-style tests in a fixture package when generator work lands.

### Git Workflow
Not explicitly defined in this repo yet. Default expectations for contributors/assistants:

- Prefer small, reviewable changes (PRs) on short-lived branches.
- For non-trivial changes (new capabilities, breaking changes, architecture shifts), use OpenSpec:
	- Add a change under `openspec/changes/<change-id>/`.
	- Run `openspec validate <change-id> --strict`.

If you have a specific workflow (trunk-based vs release branches, commit message conventions, etc.), add it here and assistants should follow it.

## Domain Context
- Continuum models domain state transitions as explicit, typed domain events.
- Frontend and backend events may serve different roles; in hybrid mode, frontend events can be optimistic and disposable.
- Aggregates are “apply-only”: they know how to apply events and how to construct from creation events; they do not create events and do not own infrastructure concerns.

## Important Constraints
- Keep the core layer lightweight and usable without persistence.
- Avoid runtime reflection; prefer compile-time generation.
- Keep persistence implementations out of the core package; stores should live in separate packages.
- Avoid leaking infrastructure concerns (like stream version tracking) into aggregates.

## External Dependencies
Current:

- Dev: `lints`, `test`
- Runtime: none declared yet

Planned/optional (per draft docs):

- Codegen toolchain and generator package(s)
- Storage backends (e.g., Hive) in separate packages
