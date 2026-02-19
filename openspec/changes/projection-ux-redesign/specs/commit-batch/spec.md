## ADDED Requirements

### Requirement: CommitBatch type

The system SHALL provide a `CommitBatch` value type in the `continuum` package (L0) that represents the full set of operations persisted by a single transaction, grouped by stream.

`CommitBatch` SHALL contain an ordered list of `CommittedEntry` instances. The list SHALL preserve the iteration order of the session's tracked entities.

`CommitBatch` SHALL expose a convenience getter that returns all operations across all entries as a flat `List<Operation>`, preserving per-stream and per-operation ordering, for consumers that do not need stream context.

#### Scenario: CommitBatch contains committed entries grouped by stream
- **WHEN** a session commits operations across two streams (stream-A with 2 operations, stream-B with 1 operation)
- **THEN** the resulting `CommitBatch` SHALL contain 2 `CommittedEntry` instances
- **THEN** the first entry SHALL have `streamId` equal to stream-A and 2 `CommittedOperation` instances
- **THEN** the second entry SHALL have `streamId` equal to stream-B and 1 `CommittedOperation` instance

#### Scenario: CommitBatch flat operations accessor
- **WHEN** a `CommitBatch` contains entries for stream-A (op1, op2) and stream-B (op3)
- **THEN** the flat operations accessor SHALL return `[op1, op2, op3]` in order

#### Scenario: Empty CommitBatch
- **WHEN** a session has no pending operations and commits
- **THEN** the resulting `CommitBatch` SHALL have an empty entries list

### Requirement: CommittedEntry type

The system SHALL provide a `CommittedEntry` value type that groups all committed operations for a single stream within a commit batch.

`CommittedEntry` SHALL contain:
- A `StreamId` identifying the stream.
- An ordered list of `CommittedOperation` instances representing the operations committed to that stream.

#### Scenario: CommittedEntry carries stream identity
- **WHEN** a `CommittedEntry` is created for stream "user-123" with operations [UserRegistered, EmailChanged]
- **THEN** `committedEntry.streamId` SHALL equal `StreamId('user-123')`
- **THEN** `committedEntry.operations` SHALL contain 2 `CommittedOperation` instances in order

### Requirement: CommittedOperation type

The system SHALL provide a `CommittedOperation` value type that pairs a domain `Operation` with optional persistence metadata.

`CommittedOperation` SHALL contain:
- An `Operation` instance (the domain operation).
- An optional `int? streamVersion` (populated by event-sourcing stores, null for state-based stores).
- An optional `int? globalSequence` (populated by stores that support global ordering, null otherwise).

#### Scenario: CommittedOperation from event-sourcing store
- **WHEN** an event-sourcing session commits an operation at stream version 5 and global sequence 42
- **THEN** the `CommittedOperation` SHALL have `streamVersion` equal to 5 and `globalSequence` equal to 42

#### Scenario: CommittedOperation from state-based store
- **WHEN** a state-based session commits an operation
- **THEN** the `CommittedOperation` SHALL have `streamVersion` as null and `globalSequence` as null

### Requirement: Session.saveChangesAsync returns CommitBatch

`Session.saveChangesAsync()` SHALL return `Future<CommitBatch>` instead of `Future<List<Operation>>`.

The returned `CommitBatch` SHALL be constructed from the session's tracked entities map, preserving the `StreamId ↔ Operation` association that exists during persistence.

#### Scenario: saveChangesAsync returns CommitBatch with stream context
- **WHEN** a session tracks stream "order-1" with operations [OrderCreated, ItemAdded] and stream "order-2" with [OrderCreated]
- **THEN** `saveChangesAsync()` SHALL return a `CommitBatch` with 2 entries, one per stream, each containing the corresponding operations

#### Scenario: saveChangesAsync returns empty CommitBatch when nothing to commit
- **WHEN** a session has no pending operations
- **THEN** `saveChangesAsync()` SHALL return a `CommitBatch` with an empty entries list

### Requirement: CommitHandler accepts CommitBatch

`CommitHandler.onCommitAsync` SHALL accept a `CommitBatch` parameter instead of `List<Operation>`.

#### Scenario: CommitHandler receives CommitBatch after commit
- **WHEN** `TransactionalRunner` commits a session that produced a non-empty `CommitBatch`
- **THEN** it SHALL call `commitHandler.onCommitAsync(batch)` with the same `CommitBatch` returned by `saveChangesAsync()`

#### Scenario: CommitHandler not called for empty CommitBatch
- **WHEN** `TransactionalRunner` commits a session that produced an empty `CommitBatch`
- **THEN** it SHALL NOT call `commitHandler.onCommitAsync`

### Requirement: CompositeCommitHandler propagates CommitBatch

`CompositeCommitHandler` SHALL pass the same `CommitBatch` instance to each handler in its list, sequentially.

#### Scenario: Composite handler forwards CommitBatch to all handlers
- **WHEN** a `CompositeCommitHandler` with handlers [A, B] receives a `CommitBatch`
- **THEN** it SHALL call `A.onCommitAsync(batch)` then `B.onCommitAsync(batch)` with the same batch instance

### Requirement: SingleStreamProjection does not require extractKey

`SingleStreamProjection<TReadModel>` SHALL NOT require users to implement `extractKey`. The projection executor SHALL derive the key (`StreamId`) from the `CommittedEntry.streamId` in the commit batch.

Users SHALL only implement `createInitial(StreamId)` and the generated typed apply methods.

#### Scenario: SingleStreamProjection receives key from executor
- **WHEN** the inline projection executor processes a `CommittedEntry` for stream "user-42" containing a `UserRegistered` operation
- **THEN** the executor SHALL use `StreamId('user-42')` as the read-model key without calling `extractKey`
- **THEN** the executor SHALL call `createInitial(StreamId('user-42'))` if no read model exists, then `apply(readModel, operation)`

### Requirement: MultiStreamProjection retains extractKey

`MultiStreamProjection<TReadModel, TKey>` SHALL continue to require users to implement `extractKey(Operation)`. The projection executor SHALL call `extractKey` to derive the key for multi-stream projections.

#### Scenario: MultiStreamProjection uses extractKey
- **WHEN** the inline projection executor processes a `CommittedEntry` containing operations for a multi-stream projection
- **THEN** the executor SHALL call `projection.extractKey(operation)` for each operation to determine the read-model key

### Requirement: InlineProjectionExecutor accepts CommitBatch

`InlineProjectionExecutor.executeAsync` SHALL accept a `CommitBatch` instead of `List<Operation>`.

The executor SHALL iterate entries by stream, then by operation within each stream. For each operation, it SHALL look up matching projections and apply the operation using the appropriate key strategy (stream id for single-stream, `extractKey` for multi-stream).

#### Scenario: Executor processes CommitBatch with single-stream projection
- **WHEN** the executor receives a `CommitBatch` with an entry for stream "user-1" containing [UserRegistered]
- **THEN** the executor SHALL load the read model for key `StreamId('user-1')`, apply the operation, and save the updated read model

#### Scenario: Executor processes CommitBatch with multi-stream projection
- **WHEN** the executor receives a `CommitBatch` with an entry containing an operation that a multi-stream projection handles
- **THEN** the executor SHALL call `projection.extractKey(operation)` to determine the key, load the read model, apply the operation, and save the updated read model

#### Scenario: Executor skips unhandled operations
- **WHEN** the executor receives a `CommitBatch` containing operations that no registered projection handles
- **THEN** the executor SHALL skip those operations without error
