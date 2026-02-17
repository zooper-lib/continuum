## 1. Implementation
- [x] Update `AggregateEvent` annotation to include `creation` flag.
- [x] Update generator discovery to classify events via `creation` flag.
- [x] Add generator validation for missing/duplicate `createFrom<EventName>` factories.
- [x] Update code emission (if needed) to use `createFrom<EventName>` consistently.
- [x] Update examples to mark creation events explicitly.

## 2. Lints
- [x] Add a new lint rule warning when `@Aggregate()` is missing required `createFrom<EventName>` factories for creation events.
- [x] Add tests for the new rule (and quick fix if implemented).

## 3. Verification
- [x] Run `dart format` on changed files.
- [x] Run relevant package tests (`continuum_generator`, `continuum_lints`, and example builds if applicable).
