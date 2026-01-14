## 1. Implementation
- [ ] Update `AggregateEvent` annotation to include `creation` flag.
- [ ] Update generator discovery to classify events via `creation` flag.
- [ ] Add generator validation for missing/duplicate `createFrom<EventName>` factories.
- [ ] Update code emission (if needed) to use `createFrom<EventName>` consistently.
- [ ] Update examples to mark creation events explicitly.

## 2. Lints
- [ ] Add a new lint rule warning when `@Aggregate()` is missing required `createFrom<EventName>` factories for creation events.
- [ ] Add tests for the new rule (and quick fix if implemented).

## 3. Verification
- [ ] Run `dart format` on changed files.
- [ ] Run relevant package tests (`continuum_generator`, `continuum_lints`, and example builds if applicable).
