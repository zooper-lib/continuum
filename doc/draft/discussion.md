# Design Discussion – Open Questions

This document captures open questions about the event sourcing architecture before implementation begins.

---

## 1. DomainEvent

### 1.1 Event ID Generation
- Should `eventId` be generated automatically by the system, or should it always be provided by the caller?
- If auto-generated, should we use UUIDs, ULIDs, or another format?

> **Decision:** Generate `eventId` automatically. Use a **strong type** (not raw String). Format: **ULID**.

### 1.2 Event Metadata
- The spec mentions "optional metadata (correlation, causation, user id, etc)". Should this be:
  - A generic `Map<String, dynamic> metadata` field on the base class?
  - A separate `EventMetadata` class?
  - Left entirely to concrete event implementations?

> **Decision:** Simple `Map<String, dynamic>` for metadata.

### 1.3 Event Annotation Design
- Should `@Event(ofAggregate: UserAggregate)` reference the aggregate type directly, or use a string identifier?
- Can a single event belong to multiple aggregates, or is it strictly one-to-one?
- What happens if someone forgets the annotation? Should the generator fail, warn, or ignore?

> **Decision:** Reference the aggregate type directly for type safety. One event belongs to exactly one aggregate. If the annotation is forgotten, the generator simply won't find it – nothing happens (no error, no warning).

### 1.4 Event Immutability
- Should events be enforced as immutable (e.g., require `const` constructors, use `freezed`)?
- Should we recommend or integrate with `freezed` / `json_serializable` for event definitions?

> **Decision:** Events should be immutable, but we do **not** use `freezed`. Keep dependencies minimal. `json_serializable` is acceptable.

---

## 2. AggregateRoot

### 2.1 Aggregate ID Type
- The spec uses `String id`. Should we support generic ID types (`AggregateRoot<TId>`) for flexibility (UUIDs, integers, composite keys)?

> **Decision:** No base class required for aggregates.
> - Aggregates are plain classes with `applyXxxEvent` methods and static `create` methods.
> - Stream identity is external and owned by the session/event store.
> - Aggregates don't need to know their own ID or have any infrastructure concerns.

### 2.2 Version Management
- Who is responsible for incrementing `version`?
  - The generated `replayEvents` extension increments it.
  - Should `append` in the session also increment it immediately?
  - What about when loading – should version reflect the stored version or start at 0 and count up?

> **Decision:** Aggregates do NOT store or manage version at all. Version is pure infrastructure metadata.
> 
> **Ownership model:**
> 
> | Concern | Owner |
> |---|---|
> | Stream version | EventStore |
> | Expected version checking | Session |
> | Version increment | Session (after successful saveChanges) |
> | Aggregate state | Aggregate (apply methods only) |
> 
> **Aggregates:**
> - Do NOT have a version field
> - Do NOT increment version
> - Do NOT know how many events have been applied
> 
> **Where version lives:**
> ```dart
> class Session {
>   final Map<StreamId, int> _streamVersions;
> }
> ```
> - `_streamVersions[streamId]` = current persisted version
> - Updated only after `load` and after successful `saveChanges`
> - Aggregates never see this value
> 
> **Generated replay helpers must NOT touch version:**
> 
> ❌ **Incorrect (must not exist):**
> ```dart
> void replayEvents(List<DomainEvent> events) {
>   for (final e in events) {
>     applyEvent(e);
>     version++; // ❌ aggregate has no version field
>   }
> }
> ```
> 
> ✅ **Correct:**
> ```dart
> void replayEvents(List<DomainEvent> events) {
>   for (final e in events) {
>     applyEvent(e);
>   }
> }
> ```
> 
> **Version counting by Session:**
> - During load: Session counts events → `currentVersion`
> - During saveChanges: Session uses `expectedVersion` for concurrency check
> - After successful append: Session updates `_streamVersions[streamId]`
> 
> **Rationale:**
> - Keeps aggregates pure and persistence-agnostic
> - Matches Marten behavior exactly
> - Avoids leaking infrastructure concerns into domain code
> - Allows future snapshotting without domain changes

### 2.3 Creation Event Convention
- The spec says "There is exactly one creation event per aggregate type." How do we enforce this?
  - A separate annotation like `@CreationEvent(ofAggregate: ...)`?
  - A naming convention (e.g., `*CreatedEvent`)?
  - An interface marker like `implements CreationEvent<UserAggregate>`?

> **Decision:** Creation events are identified via static `create*` method signatures on the aggregate.
> 
> **Rules:**
> - An aggregate must define at least one static factory method named `create*`
> - Each `create*` method takes exactly one parameter: the creation event type
> - The return type is the aggregate type
> - The body of the `create*` method is implemented by the programmer and must NOT call any apply method
> - The creation event types are the union of all parameter types of the `create*` methods
> - For every creation event type, that event must be annotated with `@Event(ofAggregate: ThisAggregate, ...)`
> - **No `apply<CreationEvent>` method is generated** (and therefore does not exist) for creation events
> - All other events (non-creation) require generated `apply<Event>` handlers
> - **Each creation event type must map to exactly one `create*` method** — duplicate event types = generator error
> 
> **Example:**
> ```dart
> @Aggregate()
> class UserAggregate {
>   static UserAggregate create(UserCreatedEventV1 event) {
>     return UserAggregate(
>       id: event.userId,
>       name: event.name,
>     );
>   }
> 
>   static UserAggregate createV2(UserCreatedEventV2 event) {
>     return UserAggregate(
>       id: event.userId,
>       firstName: event.firstName,
>       lastName: event.lastName,
>     );
>   }
> 
>   void applyNameChangedEvent(NameChangedEvent event) { ... }
> }
> ```
> 
> **Generator behavior:**
> - Scans static methods named `create*`
> - Collects their parameter types as creation event types
> - Validates each creation event type maps to exactly one `create*` method (error if duplicates)
> - Generates:
>   - Apply dispatcher for non-creation events only
>   - Apply method contracts for non-creation events only
>   - A creation dispatcher that selects the correct `create*` based on the first event type
> 
> **Summary:**
> - Creation event → handled by programmer-defined `create*` method
> - No `apply<CreationEvent>` exists
> - Non-creation events → handled by generated `apply<Event>` methods and dispatcher
> - First event in stream must be a valid creation event for that aggregate type

### 2.4 Aggregate Construction
- For `load`, the spec says "creating a new instance (for example with a constructor that takes `id`)". Should we:
  - Require a specific constructor signature?
  - Use a factory registration pattern?
  - Generate a factory as part of the code generator?

> **Decision:** Aggregate construction is handled via generated aggregate factories.
> 
> **Session.load<T>(streamId) flow:**
> 1. Load all events for the stream ordered by version
> 2. Take the first event — it must be one of the creation event types for `T`
> 3. Call the matching static `create*` method to build the aggregate instance
> 4. Replay the remaining events using the generated `applyEvent` dispatcher (non-creation events only)
> 5. If the first event is not a valid creation event for `T`, loading fails with `InvalidStreamCreationEventException`
> 
> **Session.startStream<T>(id, creationEvent) flow:**
> 1. Validate `creationEvent` is a creation event for `T`
> 2. Construct the aggregate via `T.create*(creationEvent)`
> 3. Record the event as pending
> 4. Cache the aggregate instance
> 5. Do NOT call any apply method
> 
> **Generated code (conceptual):**
> ```dart
> extension _$UserAggregateFactory on Never {
>   static UserAggregate createFromEvent(DomainEvent event) {
>     return switch (event) {
>       UserCreatedEventV1 e => UserAggregate.create(e),
>       UserCreatedEventV2 e => UserAggregate.createV2(e),
>       _ => throw InvalidCreationEventException(event.runtimeType),
>     };
>   }
> }
> ```
> 
> **Registry responsibility:**
> - Aggregate type → factory function mapping
> - Creation event type → aggregate type mapping
> 
> **Rationale:**
> - No base class required
> - No constructor constraints
> - No reflection
> - Fully static and type-safe
> - Clear separation: `create*` = birth, `apply*` = mutation

### 2.5 Protected vs Public Apply Methods
- Should `applyXxxEvent` methods be public or protected?
- If public, should external code be prevented from calling them directly (only through session)?

> **Decision:** Can be public. No enforcement for now – keep it simple for the initial version.

---

## 3. Session

### 3.1 Session Lifecycle
- Is a session single-use or reusable after `saveChanges()`?
- Should there be explicit `dispose()` or cleanup?

> **Decision:** Session should be reusable after `saveChanges()`.

### 3.2 Aggregate Caching
- The spec mentions "if one is kept in a cache". Should the session:
  - Always cache loaded/created aggregates?
  - Never cache (stateless loads)?
  - Make caching optional/configurable?

> **Decision:** No caching for the first implementation. Caching will be a future feature.

### 3.3 Append Without Prior Load
- Can you call `append(streamId, event)` without first calling `load()` or `startStream()`?
- If yes, how does the session know the aggregate type for event validation?

> **Decision:** Yes, you can append without prior load. Further details TBD.

### 3.4 Multiple Aggregates in One Session
- Can a single session manage multiple aggregates of different types?
- Can it manage multiple instances of the same aggregate type?
- Should `saveChanges()` be atomic across all streams or per-stream?

> **Research (Marten behavior):**
> - Marten allows a single session (`IDocumentSession`) to work with multiple streams of different types.
> - You can call `StartStream<T>()` and `Append()` on different streams within the same session.
> - `SaveChangesAsync()` commits all pending changes atomically in one database transaction.
> - Marten also offers `FetchForWriting<T>()` to load an aggregate for command handling with built-in optimistic concurrency.
> - Concurrency conflicts on any stream cause the entire `SaveChanges()` to fail with `ConcurrencyException`.
>
> **Decision:** Follow Marten's approach – session manages multiple streams, `saveChanges()` is atomic across all streams.

### 3.5 Concurrency Within Session
- What happens if `append` is called after `saveChanges()` has started but not completed?
- Should there be any locking mechanism?

> **Decision:** Session is locked while `saveChanges()` is in progress.
> 
> **Context:**
> - This is about reentrancy and async gaps, not optimistic concurrency (that's 3.4/EventStore).
> - Marten sessions are not thread-safe and rely on single-threaded usage per session.
> - In Dart/Flutter, async gaps exist – `await saveChanges()` yields control, allowing other callbacks to potentially call `append()`.
> 
> **Behavior:**
> - While `saveChanges()` is executing, any call to `append()` or `startStream()` throws immediately.
> - Error type: `SessionInProgressException`
> - This ensures semantic correctness, not thread-safety.

### 3.6 Error Handling
- What happens if `saveChanges()` fails partway through (e.g., concurrency conflict on one stream)?
  - Roll back all?
  - Partial success?
  - Return detailed error info?

> **Decision:** `saveChanges()` is atomic across all streams. No partial success.
> 
> **Guarantees (following Marten):**
> - Either all events across all streams are committed, or none are.
> - On any failure (e.g., concurrency conflict), the session state remains unchanged.
> - Pending events are NOT cleared.
> - Session remains usable after failure.
> 
> **Caller options after failure:**
> - Retry `saveChanges()`
> - Discard session
> - Inspect error details
> 
> **Error types (strongly typed, not booleans):**
> ```dart
> abstract class SaveChangesException implements Exception {}
> 
> class ConcurrencyException extends SaveChangesException {
>   final String streamId;
>   final int expectedVersion;
>   final int actualVersion;
> }
> 
> class EventStoreException extends SaveChangesException {
>   final Object cause;
> }
> ```

### 3.7 Event Validation
- Should the session validate that appended events match the aggregate type of the stream?
- Should validation happen at `append` time or `saveChanges` time?

> **Decision:** Validate at append-time. Fail fast.
> 
> **Rationale:**
> - Aggregates are passive; events declare their aggregate via `@Event(ofAggregate: X)`.
> - Appending without prior load is allowed.
> - Without validation, bugs become persistent data corruption.
> 
> **Validation rules:**
> - On first interaction with a stream, the aggregate type is inferred from:
>   - `startStream<T>()`, OR
>   - The first appended event's `@Event(ofAggregate: ...)`
> - All subsequent appends to that stream must match the established aggregate type.
> - Mismatches throw immediately at `append()` time.
> 
> **Example invalid case:**
> ```dart
> session.startStream<UserAggregate>('user-1', UserCreatedEvent(...));
> session.append('user-1', OrderPlacedEvent(...)); // ❌ throws InvalidEventForStreamException
> ```
> 
> **Error type:**
> ```dart
> class InvalidEventForStreamException implements Exception {
>   final String streamId;
>   final Type expectedAggregate;
>   final Type actualAggregate;
> }
> ```

---

## 4. EventStore

### 4.1 Stream Existence
- What does `loadStream` return for a non-existent stream? Empty list or error?

> **Decision:** Return empty list. No exception.
> 
> **Rationale (following Marten):**
> - Event sourcing treats "non-existent" and "empty history" identically.
> - Stream existence is defined by the presence of events, not by pre-created records.
> - Creation is defined by first event, not by separate existence tracking.
> - Simplifies logic and avoids existence checks everywhere.

### 4.2 Optimistic Concurrency
- What is the `expectedVersion` for a new stream? `0` or `-1` or a special constant?
- How should concurrency conflicts be reported? Exception type?

> **Decision:** Use a special constant for new streams; typed exceptions for conflicts.
> 
> **Expected version for new streams:**
> ```dart
> class ExpectedVersion {
>   static const int noStream = -1;
> }
> ```
> - New stream → `expectedVersion = ExpectedVersion.noStream`
> - Existing stream → `expectedVersion = lastEventVersion`
> - More explicit than `0` (which is ambiguous)
> 
> **Concurrency conflict reporting:**
> ```dart
> class ConcurrencyException implements Exception {
>   final String streamId;
>   final int expectedVersion;
>   final int actualVersion;
> }
> ```
> - Bubbles out of `saveChanges()`
> - Causes full rollback (atomic guarantee)
> - Leaves session state intact for retry/disposal

### 4.3 Event Ordering
- Are events guaranteed to be returned in order by version?
- Is the version strictly sequential (1, 2, 3) or can there be gaps?

> **Decision:** Events are strictly ordered. No gaps allowed.
> 
> **Guarantees (following Marten):**
> - Events returned by `loadStream` are always ordered by version (ascending).
> - Versions are strictly sequential: 1, 2, 3, ... with no gaps.
> 
> **Rationale:**
> - Version = position in stream
> - Gaps imply missing events
> - Missing events = corrupted history
> - If an EventStore implementation cannot guarantee this, it is invalid.

### 4.4 Stream Deletion
- Should streams be deletable? (Soft delete, hard delete, archive?)
- If yes, what happens to aggregates that reference deleted streams?

> **Decision:** Stream deletion is NOT supported in v1.
> 
> **Rationale (following event sourcing principles):**
> - Deleting event streams destroys history
> - Breaks auditability
> - Breaks projections
> - Breaks causal reasoning
> 
> **Marten approach:**
> - Strongly discourages deletion
> - Supports archival patterns instead
> - Treats deletion as dangerous operation
> 
> **Future consideration:**
> - If deletion is needed, model it as a domain event (`AggregateDeletedEvent`)
> - Not as a store-level operation
> - Therefore, "aggregates referencing deleted streams" is a non-issue

### 4.5 Global Event Ordering
- Is there a global sequence number across all streams (for projections later)?
- If not now, should we design for it?

> **Decision:** Design storage to allow it, but don't expose it in v1 API.
> 
> **Context:**
> - Projections are out of scope for v1
> - But future support is desired
> - Marten stores both per-stream version and global sequence number
> 
> **Approach:**
> - `StoredEvent` may include an optional `globalSequence` field
> - EventStore implementations may populate it
> - Session/Aggregate logic does NOT depend on it
> 
> **Example:**
> ```dart
> class StoredEvent {
>   final int version;           // per-stream position
>   final int? globalSequence;   // optional, not used in v1
> }
> ```
> 
> This keeps v1 clean while making v2 projections feasible.

---

## 5. Serialization

### 5.1 Event Type Discriminator
- Should the type discriminator be:
  - The simple class name (`UserCreatedEvent`)?
  - A fully qualified name (`package:myapp/events/user_created_event.dart#UserCreatedEvent`)?
  - A custom string provided via annotation?

> **Decision:** Use custom, explicit event type string via annotation. Do NOT derive from class name.
> 
> **Requirements for discriminator:**
> - Must survive refactors
> - Must survive package renames
> - Must be stable across versions
> - Must work without reflection
> - Must be readable/debuggable
> 
> **Comparison:**
> 
> | Option | Pros | Cons |
> |--------|------|------|
> | Simple class name | Short, readable | Breaks on rename, collisions |
> | Fully qualified name | Unique | Extremely brittle, unreadable |
> | Custom string | Stable, explicit | Requires discipline |
> 
> **Example:**
> ```dart
> @Event(
>   ofAggregate: UserAggregate,
>   type: 'user.created'
> )
> class UserCreatedEvent implements DomainEvent { ... }
> ```
> 
> **Rules:**
> - `type` is mandatory
> - `type` must be globally unique
> - `type` is stable forever
> - Changing the Dart class name does NOT change stored data
> 
> **Consequence:**
> - Generated registry maps: `'user.created' → UserCreatedEvent.fromJson(...)`
> - Class renames are safe
> 
> **Note:** This is the single most important serialization decision (following Marten).

### 5.2 Schema Evolution
- How do we handle event schema changes over time?
  - Upcasting (transforming old events to new format)?
  - Versioned event types (`UserCreatedEventV1`, `UserCreatedEventV2`)?
  - Built-in migration support?

> **Decision:** Two distinct strategies exist. Do NOT mix them.
> 
> **Strategy 1: New Event Type (preferred, default)**
> 
> When the meaning or structure of an event changes in a way that represents a new domain concept, introduce a new event type.
> 
> **Example:**
> ```dart
> @Event(ofAggregate: UserAggregate, type: 'user.created.v1')
> class UserCreatedEventV1 { String name; }
> 
> @Event(ofAggregate: UserAggregate, type: 'user.created.v2')
> class UserCreatedEventV2 { String firstName; String lastName; }
> ```
> 
> **Rules:**
> - Existing streams containing `V1` events remain unchanged forever
> - New streams may use `V2` events
> - Aggregates implement apply methods for BOTH event types
> - No upcasting required
> - No historical data is reinterpreted
> 
> **This is the cleanest and safest approach.**
> 
> **Strategy 2: Upcasters (exceptional case)**
> 
> When an existing event was incorrectly modeled and historical events must be treated as if they had a different shape, use an upcaster.
> 
> **Rules:**
> - Stored events remain immutable
> - Upcasters adapt old schemas to new in-memory representation during load
> - Upcasters may only reshape data; cannot invent missing information
> - If required data cannot be derived:
>   - Fields must be nullable, OR
>   - Have explicit defaults, OR
>   - Use Strategy 1 (new event type) instead
> 
> **Guiding rule:**
> - Historical events remain semantically valid → new event type
> - Historical events must be reinterpreted → upcaster
> 
> **For v1:** Upcasters are optional infrastructure, not mandatory. May be added later if needed.

### 5.3 JSON Serialization
- Should we mandate a specific JSON serialization approach?
  - `json_serializable` / `freezed`?
  - Manual `toJson` / `fromJson`?
  - Generated by our code generator?

> **Decision:** Require contract, not implementation. Don't mandate a framework.
> 
> **Requirements:**
> - Minimal dependencies
> - No runtime reflection
> - Predictable codegen
> - Developer control
> 
> **Comparison:**
> 
> | Option | Verdict |
> |--------|----------|
> | Mandate freezed | ❌ Too opinionated |
> | Mandate json_serializable | ⚠️ Acceptable but optional |
> | Manual toJson/fromJson | ✅ Simplest |
> | Generator auto-serialization | ❌ Too magical (v1) |
> 
> **Contract required:**
> ```dart
> abstract class DomainEvent {
>   String get eventId;
>   DateTime get occurredOn;
>   
>   Map<String, dynamic> toJson();
> }
> ```
> 
> **Convention expected:**
> ```dart
> static UserCreatedEvent fromJson(Map<String, dynamic> json)
> ```
> 
> **Developers may use:**
> - `json_serializable`
> - Manual mapping
> - Any tool they want
> 
> **Framework responsibility:**
> - The generator only needs to know how to call `fromJson`
> - The serializer only needs to call `toJson` to write to storage
> - The framework doesn't care about the implementation

### 5.4 Non-JSON Formats
- Should we support binary formats (protobuf, msgpack) in the future?
- If yes, should we abstract serialization now to allow for this?

> **Decision:** Abstract serialization now, but ship JSON only in v1.
> 
> **Reality:**
> - Need JSON now
> - May want binary later (protobuf, msgpack)
> - Supporting both now adds complexity
> - Not planning for it creates lock-in
> 
> **Abstraction:**
> ```dart
> abstract class EventSerializer {
>   SerializedEvent serialize(DomainEvent event);
>   DomainEvent deserialize(SerializedEvent event);
> }
> 
> class SerializedEvent {
>   final String type;
>   final int schemaVersion;
>   final Object payload; // Map for JSON, bytes for binary later
> }
> ```
> 
> **V1 implementation:**
> ```dart
> class JsonEventSerializer implements EventSerializer { ... }
> ```
> 
> **Future implementations (no API changes required):**
> - `ProtobufEventSerializer`
> - `MsgPackEventSerializer`
> - Custom formats

---

## 6. Code Generator

### 6.1 Build System
- Using `build_runner` with `source_gen`?
- Part files (`*.g.dart`) or separate files?

> **Decision:** Use `build_runner` with `source_gen`. Generate `*.g.dart` part files only.
> 
> **Rationale:**
> - Standard Dart codegen model
> - Required for mixins, extensions, generated interfaces
> - Keeps generated code colocated with source
> - No custom file naming schemes
> - No extra Dart libraries to manage
> 
> **Usage pattern:**
> ```dart
> // user_aggregate.dart
> part 'user_aggregate.g.dart';
> 
> @Aggregate()
> class UserAggregate { ... }
> ```
> 
> **Generator output:**
> - Only `*.g.dart` files
> - No `.events.g.dart` or other custom suffixes

### 6.2 Generator Scope
- Should the generator produce:
  - One file per aggregate?
  - One central registry file?
  - Both?

> **Decision:** Per-aggregate `*.g.dart` + one shared registry `*.g.dart`.
> 
> **Clarification:**
> - Events themselves are NOT generated (manually written)
> 
> **What IS generated:**
> 
> **Per-aggregate `*.g.dart` contains:**
> - Apply method interface/mixin
> - `applyEvent(DomainEvent)` dispatcher
> - `replayEvents(...)` helper
> 
> **Central registry `*.g.dart` contains:**
> - Event type → factory mapping (`'user.created' → UserCreatedEvent.fromJson`)
> - Event type → aggregate type mapping
> - Optional upcaster registration (future)
> 
> **Example:**
> - `user_aggregate.g.dart` (per-aggregate)
> - `event_registry.g.dart` (central registry)

### 6.3 Aggregate Discovery
- How does the generator discover aggregates?
  - Scan for classes extending `AggregateRoot`?
  - Require an annotation on aggregates too?

> **Decision:** Aggregates discovered via `@Aggregate()` annotation only.
> 
> **Rationale:**
> - No base class exists (per decision 2.1)
> - No naming conventions
> - Explicit and predictable
> 
> **Pattern:**
> ```dart
> @Aggregate()
> class UserAggregate {
>   static UserAggregate create(UserCreatedEvent event) { ... }
>   void applyUserCreatedEvent(UserCreatedEvent event) { ... }
> }
> ```
> 
> **Events link to aggregates:**
> ```dart
> @Event(
>   ofAggregate: UserAggregate,
>   type: 'user.created'
> )
> class UserCreatedEvent implements DomainEvent { ... }
> ```

### 6.4 Apply Method Naming
- The spec uses `applyUserCreatedEvent`. Is this convention fixed, or configurable?
- What about events with long names – any length limits?

> **Decision:** Fixed convention `apply<EventClassName>`. Not configurable.
> 
> **Rules:**
> - No configuration
> - No shortening
> - No aliases
> - Long names are acceptable
> 
> **Examples:**
> ```dart
> void applyUserCreatedEvent(UserCreatedEvent event) { ... }
> void applyUserProfilePhotoUpdatedEvent(UserProfilePhotoUpdatedEvent event) { ... }
> ```
> 
> **Predictability over brevity.**

### 6.5 Generated Code Visibility
- Should generated code be implementation-private (`_$...`) or public?

> **Decision:** Generated symbols prefixed with `_$`, public at language level, private by convention.
> 
> **Pattern:**
> - Live in `*.g.dart` part files
> - Prefixed with `_$` (e.g., `_$UserAggregateEventHandlers`)
> - Technically public (Dart language limitation)
> - Private by convention (developers should not use directly)
> 
> **Example:**
> ```dart
> // Generated in user_aggregate.g.dart
> mixin _$UserAggregateEventHandlers {
>   void applyUserCreatedEvent(UserCreatedEvent event);
> }
> 
> // User code in user_aggregate.dart
> @Aggregate()
> class UserAggregate with _$UserAggregateEventHandlers {
>   // Implementation
> }
> ```

---

## 7. API Design

### 7.1 Opening a Session
- The spec shows `eventSourcing.openSession()`. What is `eventSourcing`?
  - A singleton?
  - A configured instance (`EventSourcingClient`, `DocumentStore`)?
  - What configuration does it need (EventStore, Serializer, etc.)?

> **Decision:** Introduce `EventSourcingStore` (analogous to Marten's `DocumentStore`). Not a singleton.
> 
> **Pattern:**
> ```dart
> final store = EventSourcingStore(
>   eventStore: sqliteEventStore,
>   serializer: jsonEventSerializer,
>   upcasters: [...],
> );
> 
> final session = store.openSession();
> ```
> 
> **Rationale:**
> - Avoids hidden global state
> - Allows multiple configurations (test vs prod, multi-tenant)
> - Mirrors Marten's mental model
> - Makes dependencies explicit
> 
> **Responsibilities of `EventSourcingStore`:**
> - Holds configuration (EventStore, EventSerializer, upcasters)
> - Owns shared infrastructure
> - Creates new Session instances
> 
> **Lifecycle:**
> - `EventSourcingStore` is long-lived and reusable
> - `Session` instances are lightweight and short-lived (per unit of work)

### 7.2 Dependency Injection
- How should the system integrate with DI frameworks?
- Should `EventStore`, `EventSerializer`, `Session` be injectable?

> **Decision:** DI-friendly but DI-agnostic. Constructor injection for all core components.
> 
> **Injectable components:**
> - `EventStore`
> - `EventSerializer`
> - `EventUpcaster` list (optional)
> - `EventSourcingStore`
> - `Session` (created via factory, not injected directly)
> 
> **Rationale:**
> - Works with any DI solution (Riverpod, get_it, injectable, manual)
> - No framework coupling
> - No hidden service locators
> 
> **Example with DI container:**
> ```dart
> final store = EventSourcingStore(
>   eventStore: container.read(eventStoreProvider),
>   serializer: container.read(eventSerializerProvider),
> );
> 
> final session = store.openSession();
> ```
> 
> **Rules:**
> - `Session` is never a singleton
> - `Session` is created per unit of work

### 7.3 Testing Support
- Should we provide an in-memory implementation out of the box?
- Test helpers for asserting on pending events?
- Fake session for unit testing aggregates in isolation?

> **Decision:** Provide first-class testing support out of the box.
> 
> **7.3.1 In-Memory EventStore**
> 
> Provide an `InMemoryEventStore` implementation that:
> - Enforces optimistic concurrency
> - Preserves event ordering
> - Behaves identically to real stores
> 
> **Rationale:**
> - Enables fast unit and integration tests
> - Prevents logic that "only works in prod"
> 
> **7.3.2 Session-Level Testing**
> 
> Do NOT expose "pending events" directly. Tests assert against persisted events.
> 
> **Example:**
> ```dart
> final store = InMemoryEventStore();
> final es = EventSourcingStore(
>   eventStore: store,
>   serializer: serializer,
> );
> 
> final session = es.openSession();
> session.startStream<UserAggregate>('id', UserCreatedEvent(...));
> await session.saveChanges();
> 
> final events = await store.loadStream('id');
> expect(events.length, 1);
> ```
> 
> **Rationale:**
> - Avoids white-box testing
> - Keeps session internals free to evolve
> 
> **7.3.3 Aggregate Testing**
> 
> Test aggregates by constructing events, applying them, asserting on state. No fake session needed.
> 
> **Example:**
> ```dart
> final agg = UserAggregate.create('id', UserCreatedEvent(...));
> agg.applyNameChangedEvent(NameChangedEvent(...));
> 
> expect(agg.name, 'Daniel');
> ```
> 
> **Rationale:**
> - Aggregates are pure
> - No persistence required
> - Fast, deterministic tests

---

## 8. Naming

### 8.1 Package Name
- Is `continuum` the final name?
- Any concerns about name conflicts with existing packages?

> **Decision:** Package name is `continuum`.
> 
> **Rationale:**
> - Fits event sourcing semantics (continuous history over time)
> - Short, memorable, domain-appropriate
> - No existing package conflict on pub.dev
> 
> **Rules:**
> - All public APIs live under `package:continuum/...`
> - No prefixes like `es_`, `event_`, etc.

### 8.2 Class Naming Conventions
- `EventSourcingSession` vs `Session` vs `UnitOfWork`?
- `AggregateRoot` vs `Aggregate` vs `EventSourcedAggregate`?
- `DomainEvent` vs `Event` vs `SourcedEvent`?

> **Decision:** Naming reflects Marten-style mental model. Explicitness over cleverness.
> 
> **Session**
> 
> Use `Session` (not `EventSourcingSession` or `UnitOfWork`).
> 
> ```dart
> final session = store.openSession();
> ```
> 
> **Rationale:**
> - Matches Marten terminology exactly
> - `EventSourcingSession` is verbose and redundant
> - `UnitOfWork` is abstract and misleading here
> - Short-lived, represents one event-sourcing unit of work
> 
> **Aggregate**
> 
> Use `Aggregate` (not `AggregateRoot` or `EventSourcedAggregate`).
> 
> ```dart
> @Aggregate()
> class UserAggregate { ... }
> ```
> 
> **Rationale:**
> - No mandatory base class (decision 2.1)
> - No inheritance-based discovery
> - `AggregateRoot` is incorrect and misleading given no base class
> - `EventSourcedAggregate` is redundant
> - "Aggregate" is a conceptual term only
> 
> **DomainEvent**
> 
> Use `DomainEvent` (not `Event` or `SourcedEvent`).
> 
> ```dart
> abstract class DomainEvent {
>   String get eventId;
>   DateTime get occurredOn;
>   Map<String, dynamic> toJson();
> }
> ```
> 
> **Rationale:**
> - Distinguishes domain events from UI events, framework events, system notifications
> - Matches established DDD terminology
> - Avoids overly generic `Event`
> - All persisted events implement `DomainEvent`

---

## 9. Future Considerations

### 9.1 Snapshots
- Even though out of scope, should we design `AggregateRoot` and `EventStore` to accommodate snapshots later?
- E.g., a `toSnapshot()` / `fromSnapshot()` pattern?

> **Decision:** Do NOT add snapshot APIs to aggregates in v1. Design EventStore/Session to allow snapshots later.
> 
> **Rationale:**
> - Snapshots are an infrastructure concern, not a domain concern
> - Adding snapshot APIs to aggregates pollutes the domain model
> - Many systems never need snapshots; premature addition adds complexity
> 
> **Design hooks for later support:**
> 
> `Session.load()` should conceptually support:
> - Loading from a snapshot if available
> - Replaying events after the snapshot version
> 
> `EventStore` may later gain optional methods (non-breaking):
> ```dart
> Future<Snapshot?> loadSnapshot(String streamId);
> Future<void> storeSnapshot(Snapshot snapshot);
> ```
> 
> **Rule:**
> - Aggregates remain unaware of snapshots
> - Snapshot creation and usage is handled entirely by infrastructure

### 9.2 Projections
- Should `StoredEvent` include a global sequence number now for future projection support?

> **Decision:** Yes, include optional `globalSequence` on `StoredEvent` now. Don't expose in public APIs in v1.
> 
> **Rationale:**
> - Projections (especially async, ordered) require global ordering
> - Adding it later would require storage migrations
> - Keeping it optional avoids forcing all EventStore implementations to use it immediately
> 
> **Design:**
> ```dart
> class StoredEvent {
>   final int version;              // per-stream position
>   final int? globalSequence;      // optional, monotonic, cross-stream
> }
> ```
> 
> **Rule:**
> - Global ordering is infrastructure-only in v1
> - Projections are explicitly out of scope for v1
> - This decision aligns with 4.5 (Global Event Ordering)

### 9.3 Multi-tenancy
- Should stream IDs have tenant prefixes?
- Should the EventStore be tenant-aware?

> **Decision:** Do NOT encode tenancy in stream IDs. Core remains tenant-agnostic. Support multi-tenancy via composition.
> 
> **Rationale:**
> - Tenant prefixes in IDs leak infrastructure concerns into domain
> - Many applications are single-tenant
> - Different deployments require different tenancy strategies
> 
> **Recommended patterns (outside core):**
> 
> **Option 1:** One `EventSourcingStore` per tenant
> 
> **Option 2:** Tenant-aware EventStore wrapper
> ```dart
> class TenantEventStore implements EventStore {
>   final String tenantId;
>   final EventStore inner;
>   
>   // Wraps calls with tenant context
> }
> ```
> 
> **Option 3:** Tenant resolution at application boundary
> 
> **Rule:**
> - Continuum remains tenant-agnostic
> - Multi-tenancy is an application-level concern
> - Tenant isolation strategy is deployment-specific

---

## 10. Additional Clarifications

### 10.1 Stream ID Type
- Is stream ID always `String` or should it be a strong type?

> **Decision:** Stream ID is a strong type (like `EventId`), not a raw `String`.
> 
> **Rationale:**
> - Type safety and self-documentation
> - Consistent with `EventId` being a strong type
> - Prevents accidental string confusion
> 
> **Example:**
> ```dart
> class StreamId {
>   final String value;
>   const StreamId(this.value);
> }
> ```

### 10.2 Metadata on DomainEvent
- Should metadata be part of the DomainEvent contract?

> **Decision:** Yes, include optional metadata in `DomainEvent` contract.
> 
> **Updated contract:**
> ```dart
> abstract class DomainEvent {
>   EventId get eventId;
>   DateTime get occurredOn;
>   Map<String, dynamic> get metadata;
>   
>   Map<String, dynamic> toJson();
> }
> ```
> 
> **Note:** Metadata is optional (may return empty map).

### 10.3 occurredOn Generation
- Is `occurredOn` auto-generated like `eventId`?

> **Decision:** Yes, `occurredOn` is auto-generated.
> 
> **Behavior:**
> - Both `eventId` and `occurredOn` are generated automatically when an event is created
> - `eventId` uses ULID (decision 1.1)
> - `occurredOn` uses `DateTime.now().toUtc()`
> - Developers do not need to provide these values

---

## Decisions Log

| # | Question | Decision | Date |
|---|----------|----------|------|
| 1.1 | Event ID Generation | Auto-generate as strong type using ULID | 2026-01-02 |
| 1.2 | Event Metadata | Simple `Map<String, dynamic>` | 2026-01-02 |
| 1.3 | Event Annotation Design | Reference aggregate type directly; one event → one aggregate; missing annotation = silently ignored | 2026-01-02 |
| 1.4 | Event Immutability | Immutable, no freezed, json_serializable OK | 2026-01-02 |
| 2.1 | Aggregate Base Class | No base class; plain classes with applyXxxEvent & static create; stream ID external | 2026-01-02 |
| 2.2 | Version Management | Version is infrastructure metadata owned by Session/EventStore; not exposed in aggregates | 2026-01-02 |
| 2.3 | Creation Event Convention | Identified via static create* method signatures; no apply method generated for creation events; one event type per create* method | 2026-01-02 |
| 2.4 | Aggregate Construction | Generated factories; create* handles birth, apply* handles mutation; first event must be creation event | 2026-01-02 |
| 2.5 | Apply Method Visibility | Public, no enforcement for now | 2026-01-02 |
| 3.1 | Session Lifecycle | Reusable after saveChanges() | 2026-01-02 |
| 3.2 | Aggregate Caching | No caching in v1, future feature | 2026-01-02 |
| 3.3 | Append Without Load | Allowed; aggregate type inferred from event's @Event annotation | 2026-01-02 |
| 3.4 | Multiple Aggregates in Session | Yes, atomic saveChanges() across all streams (Marten-style) | 2026-01-02 |
| 3.5 | Concurrency Within Session | Session locked during saveChanges(); append/startStream throw if called during save | 2026-01-02 |
| 3.6 | Error Handling | Atomic; no partial success; session remains usable after failure; strongly typed errors | 2026-01-02 |
| 3.7 | Event Validation | Validate at append-time; aggregate type inferred from startStream or first event; fail fast | 2026-01-02 |
| 4.1 | Stream Existence | Return empty list for non-existent streams; no exception | 2026-01-02 |
| 4.2 | Optimistic Concurrency | Use ExpectedVersion.noStream constant (-1); typed ConcurrencyException | 2026-01-02 |
| 4.3 | Event Ordering | Strictly ordered by version; strictly sequential; no gaps | 2026-01-02 |
| 4.4 | Stream Deletion | Not supported in v1; future may use domain events instead | 2026-01-02 |
| 4.5 | Global Event Ordering | Optional globalSequence field in storage; not exposed in v1 API; enables future projections | 2026-01-02 |
| 5.1 | Event Type Discriminator | Custom explicit string via annotation (e.g., 'user.created'); mandatory, globally unique, stable forever | 2026-01-02 |
| 5.2 | Schema Evolution | Two strategies: (1) New event types (preferred/default), (2) Upcasters (exceptional); v1 focuses on strategy 1 | 2026-01-02 |
| 5.3 | JSON Serialization | Require toJson/fromJson contract; don't mandate framework; developers choose implementation | 2026-01-02 |
| 5.4 | Non-JSON Formats | Abstract via EventSerializer interface; ship JSON only in v1; enables future binary formats without API changes | 2026-01-02 |
| 6.1 | Build System | build_runner + source_gen; *.g.dart part files only; standard Dart codegen | 2026-01-02 |
| 6.2 | Generator Scope | Per-aggregate *.g.dart (apply interface, dispatcher, replay, factory) + central registry *.g.dart (type mappings) | 2026-01-02 |
| 6.3 | Aggregate Discovery | Via @Aggregate() annotation only; explicit and predictable | 2026-01-02 |
| 6.4 | Apply Method Naming | Fixed convention apply<EventClassName>; not configurable; predictability over brevity | 2026-01-02 |
| 6.5 | Generated Code Visibility | Prefixed with _$; in *.g.dart; public by language, private by convention | 2026-01-02 |
| 7.1 | Opening a Session | EventSourcingStore (not singleton); long-lived store creates short-lived sessions; explicit dependencies | 2026-01-02 |
| 7.2 | Dependency Injection | DI-friendly but DI-agnostic; constructor injection; works with any DI solution | 2026-01-02 |
| 7.3 | Testing Support | InMemoryEventStore provided; no pending events exposure; pure aggregate testing | 2026-01-02 |
| 8.1 | Package Name | continuum; fits event sourcing semantics; no prefixes | 2026-01-02 |
| 8.2 | Class Naming | Session (matches Marten); Aggregate (conceptual, no base class); DomainEvent (distinguishes from other events) | 2026-01-02 |
| 9.1 | Snapshots | Not in v1; design hooks in EventStore/Session for later; aggregates remain unaware; infrastructure concern only | 2026-01-02 |
| 9.2 | Projections | Optional globalSequence in StoredEvent now; not exposed in v1 APIs; enables future without migration | 2026-01-02 |
| 9.3 | Multi-tenancy | Tenant-agnostic core; no tenant prefixes in IDs; support via composition/wrappers; application-level concern | 2026-01-02 |
| 10.1 | Stream ID Type | Strong type (StreamId), not raw String | 2026-01-02 |
| 10.2 | Metadata on DomainEvent | Include optional metadata in DomainEvent contract | 2026-01-02 |
| 10.3 | occurredOn Generation | Auto-generated like eventId using DateTime.now().toUtc() | 2026-01-02 |
