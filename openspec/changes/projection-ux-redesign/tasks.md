## 1. Introduce CommitBatch types in L0 (`continuum`)

- [ ] 1.1 Create `CommittedOperation` value type with `Operation operation`, `int? streamVersion`, and `int? globalSequence` fields
- [ ] 1.2 Create `CommittedEntry` value type with `StreamId streamId` and `List<CommittedOperation> operations` fields
- [ ] 1.3 Create `CommitBatch` value type with `List<CommittedEntry> entries` and a flat `List<Operation>` convenience getter
- [ ] 1.4 Export the new types from `continuum.dart` barrel file
- [ ] 1.5 Write unit tests for `CommitBatch`, `CommittedEntry`, and `CommittedOperation` (construction, empty batch, flat operations accessor, ordering)

## 2. Update Session and SessionBase in L1 (`continuum_uow`)

- [ ] 2.1 Change `Session.saveChangesAsync` return type from `Future<List<Operation>>` to `Future<CommitBatch>`
- [ ] 2.2 Update `SessionBase` abstract signature to match the new return type
- [ ] 2.3 Update existing `Session`/`SessionBase` tests to expect `CommitBatch` return type

## 3. Update CommitHandler and CompositeCommitHandler in L1 (`continuum_uow`)

- [ ] 3.1 Change `CommitHandler.onCommitAsync` parameter from `List<Operation>` to `CommitBatch`
- [ ] 3.2 Update `CompositeCommitHandler` to pass `CommitBatch` to each handler
- [ ] 3.3 Update `CompositeCommitHandler` tests to use `CommitBatch`

## 4. Update TransactionalRunner in L1 (`continuum_uow`)

- [ ] 4.1 Update `TransactionalRunner.runAsync` to pass the `CommitBatch` from `saveChangesAsync` to `commitHandler.onCommitAsync`
- [ ] 4.2 Update the empty-check logic (use `batch.entries.isEmpty` instead of `List.isEmpty`)
- [ ] 4.3 Update `TransactionalRunner` tests to verify `CommitBatch` propagation and empty-batch skip behavior

## 5. Update SingleStreamProjection in L0 (`continuum`)

- [ ] 5.1 Remove the abstract `extractKey` declaration from `SingleStreamProjection` (users no longer implement it)
- [ ] 5.2 Provide an internal `extractKey` override or mark it so the executor can bypass it via `is SingleStreamProjection` check
- [ ] 5.3 Update `SingleStreamProjection` tests to verify it no longer requires user-provided `extractKey`

## 6. Update InlineProjectionExecutor in L0 (`continuum`)

- [ ] 6.1 Change `InlineProjectionExecutor.executeAsync` to accept `CommitBatch` instead of `List<Operation>`
- [ ] 6.2 Implement by-stream iteration: iterate `CommitBatch.entries`, then each entry's operations
- [ ] 6.3 For single-stream projections (`is SingleStreamProjection`), use `CommittedEntry.streamId` as the key directly
- [ ] 6.4 For multi-stream projections, continue calling `projection.extractKey(operation)`
- [ ] 6.5 Update `InlineProjectionExecutor` tests to verify CommitBatch processing, single-stream key derivation, and multi-stream extractKey delegation

## 7. Update Session implementations in L1 and L2

- [ ] 7.1 Update `StateBasedSession.saveChangesAsync` to build and return a `CommitBatch` from `trackedEntities` instead of a flat `List<Operation>`
- [ ] 7.2 Update `SessionImpl.saveChangesAsync` (event-sourcing) to build and return a `CommitBatch`, populating `streamVersion` and `globalSequence` on each `CommittedOperation`
- [ ] 7.3 Update `StateBasedSession` tests to verify `CommitBatch` structure with stream grouping
- [ ] 7.4 Update `SessionImpl` tests to verify `CommitBatch` includes `streamVersion` and `globalSequence`

## 8. Ship ProjectionCommitHandler and AsyncProjectionCommitHandler in L1 (`continuum_uow`)

- [ ] 8.1 Create `ProjectionCommitHandler` class implementing `CommitHandler`, delegating `onCommitAsync(CommitBatch)` to `InlineProjectionExecutor.executeAsync`
- [ ] 8.2 Create `AsyncProjectionCommitHandler` class implementing `CommitHandler`, delegating `onCommitAsync(CommitBatch)` to a user-provided `Future<void> Function(CommitBatch)` callback
- [ ] 8.3 Export both handlers from the `continuum_uow` barrel file
- [ ] 8.4 Write tests for `ProjectionCommitHandler`: delegation, exception propagation
- [ ] 8.5 Write tests for `AsyncProjectionCommitHandler`: callback invocation, exception propagation
- [ ] 8.6 Write test for composing both handlers via `CompositeCommitHandler`

## 9. Update AsyncProjectionExecutor in L2 (`continuum_event_sourcing`)

- [ ] 9.1 Review `AsyncProjectionExecutor` — for single-stream projections, use `StoredEvent.streamId` as key instead of calling `extractKey`
- [ ] 9.2 Update `AsyncProjectionExecutor` tests to verify single-stream key derivation from `StoredEvent.streamId`

## 10. Update code generator (`continuum_generator`)

- [ ] 10.1 Add generator logic to discover all `@Projection`-annotated projections and their lifecycle, read-model type, and key type
- [ ] 10.2 Emit a `registerAll` extension method on `ProjectionRegistry` with named parameters for each projection instance and store
- [ ] 10.3 Emit correct `ReadModelStore<TReadModel, TKey>` parameter types (using `StreamId` for single-stream, user key for multi-stream)
- [ ] 10.4 Emit `registerGeneratedInline` or `registerGeneratedAsync` calls based on projection lifecycle
- [ ] 10.5 Pass the corresponding `GeneratedProjection` bundle in each registration call
- [ ] 10.6 Remove `extractKey` from generated single-stream projection handler mixins (if generated)
- [ ] 10.7 Write generator tests for the `registerAll` extension emission: parameter names, types, lifecycle routing, bundle passing

## 11. Update example and documentation

- [ ] 11.1 Update `UserProfileProjection` example to remove `extractKey` implementation
- [ ] 11.2 Remove the hand-written `_ProjectionCommitHandler` adapter from the projection example
- [ ] 11.3 Update the example to use the framework-provided `ProjectionCommitHandler` directly
- [ ] 11.4 Update the example to use the generated `registerAll` extension if applicable
- [ ] 11.5 Update `projections_developer_guide.md` to reflect the new API
