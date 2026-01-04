## 1. Specs & structure
- [x] 1.1 Add initial capability specs (core, persistence, generator, stores)
- [ ] 1.2 Validate OpenSpec change (`openspec validate add-continuum-initial-v1 --strict`)

## 2. Core package: `packages/continuum`
- [x] 2.1 Implement annotations: `@Aggregate()` and `@Event(ofAggregate: ..., type: ...)`
- [x] 2.2 Implement strong types: `EventId`, `StreamId`
- [x] 2.3 Implement `DomainEvent` base contract and exceptions used by generated code
- [x] 2.4 Implement persistence interfaces: `Session`, `EventStore`, `EventSerializer`, `StoredEvent`, `ExpectedVersion`
- [x] 2.5 Implement `EventSourcingStore` root object
- [x] 2.6 Update exports in `lib/continuum.dart` and docs/examples
- [x] 2.7 Add unit tests for core types/exceptions (no generator)

## 3. Generator package: `packages/continuum_generator`
- [x] 3.1 Scaffold generator package (build_runner + source_gen)
- [x] 3.2 Implement aggregate/event discovery and validation rules
- [x] 3.3 Generate `_$<Aggregate>EventHandlers` mixin (non-creation events only)
- [x] 3.4 Generate `applyEvent()` and `replayEvents()` extensions
- [x] 3.5 Generate `createFromEvent()` factory dispatcher
- [x] 3.6 Generate `EventRegistry` for persistence deserialization
- [ ] 3.7 Add integration-style tests that compile and run generated code

## 4. Store packages
- [x] 4.1 Add `packages/continuum_store_memory` implementing `EventStore`
- [x] 4.2 Add EventStore contract tests (append/load ordering, expected-version concurrency)
- [x] 4.3 Add `packages/continuum_store_hive` implementing `EventStore`
- [x] 4.4 Add Hive store tests (same contract + Hive specifics)

## 5. Repository hygiene
- [x] 5.1 Update top-level README to describe packages and usage modes
- [x] 5.2 Ensure `dart format` and tests pass for all packages
