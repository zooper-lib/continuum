# Tasks: Refactor Projections to Code Generation

## 1. Core Annotations (continuum package)

- [x] Create `@Projection(name: String, events: List<Type>)` annotation in `lib/src/annotations/projection.dart`
- [x] Export annotation from `lib/continuum.dart`
- [x] Add documentation and examples

## 2. Projection Discovery (continuum_generator package)

- [x] Create `ProjectionInfo` model class in `lib/src/models/projection_info.dart`
- [x] Create `ProjectionEventInfo` model class for event type metadata
- [x] Implement `ProjectionDiscovery` class to scan for `@Projection` annotations
- [x] Implement reading `events` list from annotation to determine handled event types
- [x] Infer read model type from base class generic parameter (e.g., `SingleStreamProjection<UserProfile>`)
- [x] Add tests for projection discovery with various event list configurations

## 3. Projection Code Emission (continuum_generator package)

- [x] Extend `CodeEmitter` or create `ProjectionCodeEmitter` for projection-specific code
- [x] Generate `_$<Projection>Handlers` mixin with:
  - [x] `handledEventTypes` getter
  - [x] `projectionName` getter
  - [x] `apply()` method that dispatches to typed handlers
  - [x] Abstract `apply<EventName>` methods for each event
- [x] Generate `$<Projection>EventDispatch` extension with:
  - [x] `applyEvent()` convenience dispatcher method
- [x] Compute `schemaHash` from sorted event type names
- [x] Generate `$<Projection>` bundle constant with:
  - [x] Projection name
  - [x] Schema hash
  - [x] Handled event types set
- [x] Add tests for emitted projection code

## 4. Generator Integration

- [x] Update `ContinuumGenerator` to run projection discovery
- [x] Update generator to emit projection code alongside aggregate code
- [x] Ensure part file generation works correctly for projections
- [x] Add integration tests for combined aggregate + projection generation

## 5. Combining Builder Updates

- [x] Update combining builder to discover and aggregate projection bundles
- [x] Generate `$projectionList` in `continuum.g.dart`
- [x] Add tests for combining builder projection discovery

## 6. Runtime Support (continuum package)

- [x] Create `GeneratedProjection` class to hold projection bundle metadata (including `schemaHash`)
- [x] Create `ReadModelResult<T>` class with `value` and `isStale` fields
- [x] Rename `Projection` base class to `ProjectionBase` to avoid annotation collision
- [x] Update `SingleStreamProjection` base class to work with generated mixins
- [x] Update `MultiStreamProjection` base class similarly
- [x] Update `ProjectionRegistry` to accept `List<GeneratedProjection>`
- [x] Add/update tests for simplified projection base classes

## 7. Schema Change Detection and Rebuild

- [x] Create `ProjectionPosition` class with `lastProcessedSequence` and `schemaHash`
- [x] Update `ProjectionPositionStore` to store `ProjectionPosition` (not just int)
- [x] Update `InMemoryProjectionPositionStore` implementation
- [x] Update `AsyncProjectionExecutor` to work with `ProjectionPosition`
- [x] Update `PollingProjectionProcessor` to work with new position interface
- [x] Add tests for schema change detection

## 8. Registry and Executor Updates

- [x] Add `registerGeneratedInline()` method to `ProjectionRegistry`
- [x] Add `registerGeneratedAsync()` method to `ProjectionRegistry`
- [x] Add `getSchemaHash()` method to `ProjectionRegistry`
- [x] Store generated bundles for schema hash retrieval
- [x] Add/update tests for registry with generated projections

## 9. Lint Support (continuum_lints package)

- [x] Create `continuum_missing_projection_handlers` lint rule
- [x] Implement handler detection logic (find `apply<EventName>` methods)
- [x] Implement missing handler detection (compare mixin requirements vs implementations)
- [x] Create quick-fix to generate missing handler stubs
- [x] Add tests for lint rule detection
- [x] Add tests for quick-fix code generation

## 10. Example Updates

- [x] Create `UserProfileProjection` example using `@Projection` annotation
- [x] Create `projection_example.dart` demonstrating full workflow
- [x] Update main.dart to mention projection examples
- [x] Run `build_runner` and verify generated code
- [x] Verify examples compile without errors

## 11. Documentation

- [x] Update `packages/continuum/README.md` projection section
- [x] Document the annotation-based approach
- [x] Document code generation output
- [x] Add lint support documentation
- [x] Add schema change detection documentation

## 12. Migration Cleanup

- [x] Verify old manual projection pattern still works (backward compatible)
- [x] Add tests for new `registerGeneratedInline`/`registerGeneratedAsync` methods
- [x] Verify all tests pass with new implementation (164 tests passing)

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

- [x] `@Projection(name: 'xxx', events: [...])` annotation discovered by generator
- [x] `events` list from annotation used to determine handled event types
- [x] Generated mixin contains `handledEventTypes`, `projectionName`, `apply()` and `apply<EventName>` methods
- [x] Dart compiler enforces handler implementation at compile time
- [x] Generated dispatcher routes events correctly
- [x] Generated bundle includes `schemaHash`
- [x] `ProjectionPosition` tracks schema hash for change detection
- [x] `$projectionList` includes all projections in package
- [x] `ProjectionRegistry` works with generated bundles
- [x] Lint rule catches missing handlers in IDE
- [x] Quick-fix generates correct handler stubs
- [x] All existing tests pass (164 tests)
- [x] New tests cover generated projection code paths
- [x] Examples demonstrate the simplified developer experience
