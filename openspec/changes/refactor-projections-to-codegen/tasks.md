# Tasks: Refactor Projections to Code Generation

## 1. Core Annotations (continuum package)

- [ ] Create `@Projection(name: String, events: List<Type>)` annotation in `lib/src/annotations/projection.dart`
- [ ] Export annotation from `lib/continuum.dart`
- [ ] Add documentation and examples

## 2. Projection Discovery (continuum_generator package)

- [ ] Create `ProjectionInfo` model class in `lib/src/models/projection_info.dart`
- [ ] Create `ProjectionEventInfo` model class for event type metadata
- [ ] Implement `ProjectionDiscovery` class to scan for `@Projection` annotations
- [ ] Implement reading `events` list from annotation to determine handled event types
- [ ] Infer read model type from base class generic parameter (e.g., `SingleStreamProjection<UserProfile>`)
- [ ] Add tests for projection discovery with various event list configurations

## 3. Projection Code Emission (continuum_generator package)

- [ ] Extend `CodeEmitter` or create `ProjectionCodeEmitter` for projection-specific code
- [ ] Generate `_$<Projection>Handlers` mixin with:
  - [ ] Abstract `createInitial(TKey key)` method
  - [ ] Abstract `apply<EventName>` methods for each event
- [ ] Generate `$<Projection>EventDispatch` extension with:
  - [ ] Static `handledEventTypes` set
  - [ ] `applyEvent()` dispatcher method
- [ ] Compute `schemaHash` from sorted event type names
- [ ] Generate `$<Projection>` bundle constant with:
  - [ ] Projection name
  - [ ] Schema hash
  - [ ] Handled event types set
- [ ] Add tests for emitted projection code

## 4. Generator Integration

- [ ] Update `ContinuumGenerator` to run projection discovery
- [ ] Update generator to emit projection code alongside aggregate code
- [ ] Ensure part file generation works correctly for projections
- [ ] Add integration tests for combined aggregate + projection generation

## 5. Combining Builder Updates

- [ ] Update combining builder to discover and aggregate projection bundles
- [ ] Generate `$projectionList` in `continuum.g.dart`
- [ ] Add tests for combining builder projection discovery

## 6. Runtime Support (continuum package)

- [ ] Create `GeneratedProjection` class to hold projection bundle metadata (including `schemaHash`)
- [ ] Create `ReadModelResult<T>` class with `value` and `isStale` fields
- [ ] Simplify `SingleStreamProjection` base class:
  - [ ] Remove `handledEventTypes` abstract getter
  - [ ] Remove `createInitial()` (now in generated mixin)
  - [ ] Update `apply()` to delegate to generated dispatcher (or remove if extension-based)
- [ ] Simplify `MultiStreamProjection` base class similarly
- [ ] Update `Projection` base class to work with generated code
- [ ] Update `ProjectionRegistry` to accept `List<GeneratedProjection>`
- [ ] Add/update tests for simplified projection base classes

## 7. Schema Change Detection and Rebuild

- [ ] Update `ProjectionPositionStore` to store `schemaHash` alongside position
- [ ] Implement schema hash comparison on startup
- [ ] Implement read model store clearing on schema mismatch
- [ ] Implement position reset on schema mismatch
- [ ] Implement non-blocking background rebuild
- [ ] Update `ReadModelStore` to return `ReadModelResult<T>` with staleness flag
- [ ] Track rebuild completion to transition from stale to fresh
- [ ] Add tests for schema change detection
- [ ] Add tests for lazy rebuild behavior
- [ ] Add tests for staleness flag during and after rebuild

## 8. Registry and Executor Updates

- [ ] Update `ProjectionRegistry.registerInline()` to work with generated bundles
- [ ] Update `ProjectionRegistry.registerAsync()` similarly
- [ ] Update `InlineProjectionExecutor` to use generated dispatchers
- [ ] Update `AsyncProjectionExecutor` similarly- [ ] Integrate schema change detection into executor startup- [ ] Add/update tests for registry with generated projections

## 8. Lint Support (continuum_lints package)

- [ ] Create `continuum_missing_projection_handlers` lint rule
- [ ] Implement handler detection logic (find `apply<EventName>` methods)
- [ ] Implement missing handler detection (compare mixin requirements vs implementations)
- [ ] Create quick-fix to generate missing handler stubs
- [ ] Add tests for lint rule detection
- [ ] Add tests for quick-fix code generation

## 9. Example Updates

- [ ] Update example projections to use `@Projection` annotation
- [ ] Update examples to use generated mixin pattern
- [ ] Remove manual `handledEventTypes` and `apply()` overrides
- [ ] Run `build_runner` and verify generated code
- [ ] Test examples end-to-end

## 10. Documentation

- [ ] Update `packages/continuum/README.md` projection section
- [ ] Document the annotation-based approach
- [ ] Document migration from manual to generated projections
- [ ] Add projection code generation to architecture docs

## 11. Migration Cleanup

- [ ] Remove or deprecate old projection patterns in tests
- [ ] Update test fixtures to use generated projection approach
- [ ] Verify all tests pass with new implementation

## Dependencies

- Task 2 (discovery) depends on Task 1 (annotations)
- Task 3 (emission) depends on Task 2 (discovery)
- Task 4 (generator integration) depends on Tasks 2, 3
- Task 5 (combining builder) depends on Task 4
- Task 6 (runtime support) can proceed in parallel with Tasks 2-5
- Task 7 (schema change detection) depends on Task 6
- Task 8 (registry updates) depends on Tasks 6, 7
- Task 9 (lints) depends on Tasks 1, 3 (needs annotation and generated mixin)
- Task 10 (examples) depends on Tasks 4, 7, 8
- Task 11 (docs) depends on Task 10
- Task 12 (cleanup) depends on all above

## Verification Criteria

- [ ] `@Projection(name: 'xxx', events: [...])` annotation discovered by generator
- [ ] `events` list from annotation used to determine handled event types
- [ ] Generated mixin contains `createInitial()` and `apply<EventName>` methods
- [ ] Dart compiler enforces handler implementation at compile time
- [ ] Generated dispatcher routes events correctly
- [ ] Generated bundle includes `schemaHash`
- [ ] Schema change detected on startup triggers rebuild
- [ ] Read models cleared on schema mismatch
- [ ] Reads return `ReadModelResult` with `isStale` flag during rebuild
- [ ] App startup is non-blocking during rebuild
- [ ] `$projectionList` includes all projections in package
- [ ] `ProjectionRegistry` works with generated bundles
- [ ] Lint rule catches missing handlers in IDE
- [ ] Quick-fix generates correct handler stubs
- [ ] All existing tests pass
- [ ] New tests cover generated projection code paths
- [ ] Examples demonstrate the simplified developer experience
