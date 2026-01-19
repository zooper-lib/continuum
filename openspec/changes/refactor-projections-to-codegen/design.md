# Design: Code-Generated Projection System

## Context

Continuum uses code generation extensively for aggregates:
- `@Aggregate()` annotation marks aggregate classes
- `@AggregateEvent(of: ...)` links events to aggregates
- Generator produces mixins, dispatchers, and registries
- Lints catch missing handlers at edit-time

The projection system was implemented without following this pattern, forcing users to write boilerplate that should be generated. This design document specifies how to bring projections in line with the established code generation approach.

**Stakeholders**: Continuum library users building read models from events.

**Constraints**:
- Must follow existing generator architecture patterns
- Must support both single-stream and multi-stream projections
- Must integrate with existing lint infrastructure
- Must not break unrelated aggregate code generation
- Must keep runtime dependencies minimal

## Goals / Non-Goals

### Goals
- Eliminate manual `handledEventTypes` declaration
- Eliminate manual event dispatch switch statements
- Generate `apply<EventName>` contract enforcement via mixins
- Provide lint support for missing projection handlers
- Auto-discover projections for registry configuration
- Maintain consistency with aggregate code generation patterns

### Non-Goals
- Auto-generate `extractKey()` for multi-stream projections (requires domain knowledge)
- Auto-generate `createInitial()` (requires domain knowledge)
- Auto-generate read model classes themselves
- Support projection versioning or schema evolution (future work)
- Real-time event streaming infrastructure

## Decisions

### Decision 1: Annotation Design

#### `@Projection()` Annotation

```dart
/// Marks a class as a projection that transforms events into read models.
class Projection {
  /// Unique name for this projection (used in position tracking).
  final String name;

  /// The list of event types this projection handles.
  ///
  /// The generator uses this list to create the required `apply<EventName>`
  /// methods in the generated mixin.
  final List<Type> events;

  const Projection({required this.name, required this.events});
}
```

The `name` is required (not derived from class name) because:
- Projection names are persisted for position tracking
- Renaming a class should not break position recovery
- Explicit naming prevents accidental collisions

The `events` list is required because:
- It is the source of truth for which events the projection handles
- Generator uses it to create the mixin with required `apply<EventName>` methods
- Compiler then enforces that the user implements all handlers

#### Event Declaration Strategy

**Decision**: Projections declare their handled events in the `@Projection` annotation's `events` parameter.

Rationale:
- One place to see all events a projection handles
- No need to modify event classes when adding projections
- Events may be handled by multiple projections—annotation on events would be verbose
- Consistent with "projection owns its event dependencies" principle
- Generator creates the mixin first, user implements handlers second (same flow as aggregates)
- Compiler enforces all handlers are implemented

```dart
@Projection(name: 'user-profile', events: [UserRegistered, EmailChanged, NameChanged])
class UserProfileProjection extends SingleStreamProjection<UserProfile>
    with _$UserProfileProjectionHandlers {
  // Generator creates mixin requiring applyUserRegistered, applyEmailChanged, applyNameChanged
  // User implements these methods; Dart compiler enforces completion
}
```

The generator reads the `events` list and generates the `_$<Name>Handlers` mixin with required `apply<EventName>` methods.

### Decision 2: Generated Mixin Structure

For a projection class `UserProfileProjection` with handlers for `UserRegistered`, `EmailChanged`, and `NameChanged`:

```dart
// Generated in user_profile_projection.g.dart

/// Generated mixin requiring initialization and apply methods for UserProfileProjection.
mixin _$UserProfileProjectionHandlers {
  /// Creates the initial read model state for a new key.
  ///
  /// Called when processing the first event for a given key.
  UserProfile createInitial(StreamId streamId);

  /// Applies a UserRegistered event to the read model.
  UserProfile applyUserRegistered(UserProfile current, UserRegistered event);

  /// Applies a EmailChanged event to the read model.
  UserProfile applyEmailChanged(UserProfile current, EmailChanged event);

  /// Applies a NameChanged event to the read model.
  UserProfile applyNameChanged(UserProfile current, NameChanged event);
}
```

The mixin declares:
- `createInitial()` to initialize the read model when first event for a key arrives
- Abstract `apply<EventName>` methods for each event in the `events` list

The Dart compiler enforces that the projection class implements all methods.

### Decision 3: Generated Dispatcher

```dart
/// Generated extension providing event dispatch for UserProfileProjection.
extension $UserProfileProjectionEventDispatch on UserProfileProjection {
  /// Set of event types this projection handles.
  static const Set<Type> handledEventTypes = {
    UserRegistered,
    EmailChanged,
    NameChanged,
  };

  /// Routes an event to the appropriate apply method.
  UserProfile applyEvent(UserProfile current, ContinuumEvent event) {
    return switch (event) {
      UserRegistered() => applyUserRegistered(current, event),
      EmailChanged() => applyEmailChanged(current, event),
      NameChanged() => applyNameChanged(current, event),
      _ => throw UnsupportedEventException(
            eventType: event.runtimeType,
            projectionType: UserProfileProjection,
          ),
    };
  }
}
```

The generated extension:
- Provides `handledEventTypes` as a static constant (no runtime overhead)
- Provides `applyEvent()` dispatcher routing to typed handlers
- Throws on unhandled events (fail-fast, no silent drops)

### Decision 4: Base Class Simplification

Current base classes require manual overrides. Simplified versions delegate to generated code:

```dart
/// Base class for single-stream projections.
abstract class SingleStreamProjection<TReadModel>
    extends Projection<TReadModel, StreamId> {

  /// Extracts the stream ID from the event (always the event's stream).
  @override
  StreamId extractKey(StoredEvent event) => event.streamId;

  /// Creates initial read model state for a new stream.
  TReadModel createInitial(StreamId streamId);

  // Note: apply() is now provided by generated extension, not overridden here
}
```

The `handledEventTypes` getter and `apply()` method move to generated code.

### Decision 5: Projection Discovery

The generator scans for classes annotated with `@Projection()` and reads the `events` list from the annotation:

```dart
final class ProjectionDiscovery {
  List<ProjectionInfo> discoverProjections(LibraryElement library) {
    final projections = <ProjectionInfo>[];

    for (final element in library.classes) {
      if (!_projectionChecker.hasAnnotationOf(element)) continue;

      final annotation = _projectionChecker.firstAnnotationOf(element);
      final name = annotation?.getField('name')?.toStringValue();

      // Read events list from annotation
      final eventsField = annotation?.getField('events');
      final eventTypes = <DartType>[];
      if (eventsField != null && !eventsField.isNull) {
        final eventsList = eventsField.toListValue();
        for (final eventValue in eventsList ?? []) {
          final eventType = eventValue.toTypeValue();
          if (eventType != null) eventTypes.add(eventType);
        }
      }

      projections.add(ProjectionInfo(
        element: element,
        name: name,
        eventTypes: eventTypes,
      ));
    }

    return projections;
  }
}
```

### Decision 6: Generated Projection Bundle

Similar to `GeneratedAggregate`, we generate a `GeneratedProjection` bundle:

```dart
/// Generated projection bundle for UserProfileProjection.
final $UserProfileProjection = GeneratedProjection(
  projectionName: 'user-profile',
  handledEventTypes: {UserRegistered, EmailChanged, NameChanged},
  factory: () => UserProfileProjection(),
);
```

And a combined list:

```dart
/// All generated projections in this package.
final List<GeneratedProjection> $projectionList = [
  $UserProfileProjection,
  $UserStatisticsProjection,
];
```

### Decision 7: Event Type Discovery from Annotation

The generator reads the `events` list from the `@Projection` annotation to determine handled event types:

```dart
// User writes:
@Projection(name: 'user-profile', events: [UserRegistered, EmailChanged, NameChanged])
class UserProfileProjection extends SingleStreamProjection<UserProfile>
    with _$UserProfileProjectionHandlers { ... }

// Generator reads annotation and produces:
// - Event types: [UserRegistered, EmailChanged, NameChanged]
// - Mixin with: applyUserRegistered, applyEmailChanged, applyNameChanged
// - User then implements these methods
```

This approach:
- Annotation is the single source of truth for handled events
- Generator creates requirements first, user implements second
- Compiler enforces all handlers are implemented (mixin has abstract methods)
- Mirrors the aggregate flow: annotation → generated mixin → user implementation

### Decision 8: StoredEvent vs ContinuumEvent in Handlers

**Question**: Should handlers receive `StoredEvent` (with metadata) or the typed `ContinuumEvent` payload?

**Decision**: Handlers receive the **typed event payload** (`ContinuumEvent`), not `StoredEvent`.

Rationale:
- Consistent with aggregate `apply<EventName>(event)` pattern
- Cleaner handler signatures
- Metadata access available via separate mechanism if needed
- The dispatcher unwraps `StoredEvent` before calling handler

```dart
// Handler signature (clean, typed):
UserProfile applyEmailChanged(UserProfile current, EmailChanged event);

// NOT this (exposes storage concerns):
UserProfile applyEmailChanged(UserProfile current, StoredEvent event);
```

The generated dispatcher handles the `StoredEvent` → typed event conversion.

### Decision 9: Lint Rule Design

New lint: `continuum_missing_projection_handlers`

Triggers when:
- Class has `@Projection()` annotation
- Class mixes in `_$<Name>Handlers`
- Class is missing one or more required `apply<EventName>` implementations

Quick-fix generates stub methods:

```dart
@override
UserProfile applyEmailChanged(UserProfile current, EmailChanged event) {
  // TODO: Implement handler
  throw UnimplementedError();
}
```

### Decision 10: Multi-Stream Projection Specifics

Multi-stream projections require custom `extractKey()` logic that cannot be generated:

```dart
@Projection(name: 'library-statistics', events: [AudioFileAdded, AudioFileRemoved])
class LibraryStatisticsProjection
    extends MultiStreamProjection<LibraryStats, String>
    with _$LibraryStatisticsProjectionHandlers {

  // User MUST implement this—key extraction requires domain knowledge
  @override
  String extractKey(StoredEvent event) {
    return event.data['libraryId'] as String;
  }

  @override
  LibraryStats createInitial(String key) => LibraryStats(libraryId: key);

  // Generated mixin requires these; user implements them:
  @override
  LibraryStats applyAudioFileAdded(LibraryStats current, AudioFileAdded event) =>
      current.copyWith(fileCount: current.fileCount + 1);

  @override
  LibraryStats applyAudioFileRemoved(LibraryStats current, AudioFileRemoved event) =>
      current.copyWith(fileCount: current.fileCount - 1);
}
```

The generator only generates:
- Handler mixin
- Event dispatcher
- `handledEventTypes` set

It does NOT generate `extractKey()` or `createInitial()`.

### Decision 11: Schema Change Detection and Lazy Rebuild

When the `events` list in a `@Projection` annotation changes, stale read models must be rebuilt without blocking the app.

#### Schema Hash

The generator computes a `schemaHash` from the sorted event type names:

```dart
// Generator computes:
final schemaHash = _computeHash(['EmailChanged', 'NameChanged', 'UserRegistered']);

// Included in generated bundle:
final $UserProfileProjection = GeneratedProjection(
  name: 'user-profile',
  schemaHash: 'a1b2c3d4',
  events: {UserRegistered, EmailChanged, NameChanged},
);
```

#### Position Store with Schema Hash

The position store saves the schema hash alongside the position:

```dart
class ProjectionPosition {
  final int lastProcessedSequence;
  final String schemaHash;
}
```

#### Startup Flow

On startup (for both inline and async projections):

1. Load stored position for projection
2. Compare `stored.schemaHash` vs `generated.schemaHash`
3. If different:
   - Log: `"Projection 'user-profile' schema changed, rebuilding..."`
   - Mark projection as stale
   - Clear read model store for this projection
   - Reset position to 0
   - Start background rebuild (non-blocking)
4. If same: continue from stored position

#### Read Model Result with Staleness Flag

Reads return data with a staleness indicator:

```dart
class ReadModelResult<T> {
  final T? value;
  final bool isStale;
  
  const ReadModelResult({this.value, required this.isStale});
}

// Usage:
final result = await readModelStore.loadAsync(streamId);
if (result.isStale) {
  // Show data but indicate it may be outdated
  showWithStaleIndicator(result.value);
} else {
  show(result.value);
}
```

#### Unified Behavior

Both single-stream and multi-stream projections use the same logic:
- Background rebuild (non-blocking)
- Reads return available data with `isStale: true` until rebuild completes
- No special-casing by projection type

**Rationale**:
- App starts instantly (no blocking rebuild)
- Users can display partial/stale data with appropriate UI indicators
- Consistent behavior regardless of projection type
- Simple mental model for developers

## Alternatives Considered

### Alternative A: Annotation on Events (`@ProjectionEvent`)

```dart
@AggregateEvent(of: User, type: 'user.email_changed')
@ProjectionEvent(of: UserProfileProjection)
@ProjectionEvent(of: UserStatisticsProjection)
class EmailChanged implements ContinuumEvent { ... }
```

**Rejected because**:
- Couples events to projections (events should be ignorant of consumers)
- Verbose when event is used by multiple projections
- Requires modifying event files when adding projections
- Inconsistent with principle that projections "own" their event dependencies

### Alternative B: Method Signature Inspection

```dart
@Projection(name: 'user-profile')
class UserProfileProjection extends SingleStreamProjection<UserProfile>
    with _$UserProfileProjectionHandlers {
  // User writes apply methods first, generator discovers them
  UserProfile applyEmailChanged(UserProfile current, EmailChanged event) => ...;
}
```

**Rejected because**:
- User writes methods first, then runs generator—backwards from aggregate pattern
- Generator cannot enforce anything until user writes code
- User could forget to run generator after adding handlers
- Doesn't provide the "implement missing methods" IDE experience

### Alternative C: Reflection-Based Discovery

Discover handlers at runtime via reflection.

**Rejected because**:
- Violates Continuum's "no reflection" principle
- Increases runtime overhead
- Breaks tree-shaking
- Dart's mirrors are limited on Flutter

## Risks / Trade-offs

| Risk | Impact | Mitigation |
|------|--------|------------|
| Method naming convention too strict | Medium | Document clearly; provide lint quick-fixes |
| Breaking change for existing projections | Low | Feature is new; migration guide provided |
| Generator complexity increases | Medium | Reuse existing aggregate discovery patterns |
| StoredEvent access lost in handlers | Low | Provide alternative API for metadata access |

## Implementation Sequence

1. **Phase 1: Annotations** — Add `@Projection()` annotation to core package
2. **Phase 2: Discovery** — Implement projection discovery in generator
3. **Phase 3: Emission** — Generate mixin, dispatcher, and projection bundle
4. **Phase 4: Base Class Refactor** — Simplify `SingleStreamProjection` and `MultiStreamProjection`
5. **Phase 5: Combining Builder** — Generate `$projectionList` in `continuum.g.dart`
6. **Phase 6: Registry Integration** — Modify `ProjectionRegistry` to accept generated bundles
7. **Phase 7: Lints** — Add `continuum_missing_projection_handlers` rule
8. **Phase 8: Documentation & Examples** — Update README and examples

## Open Questions

1. ~~**Should `createInitial()` be abstract in the mixin?**~~
   - **Decided**: Yes, include in generated mixin contract
   - Compiler enforces implementation
   - Lint can provide quick-fix stub
   - Consistent with handler pattern

2. **How to handle projection inheritance?**
   - Can a projection extend another projection?
   - Recommendation: Disallow for v1; add if use case emerges

3. **Should the read model type be inferred or declared?**
   - Currently: Inferred from base class generic parameter
   - Alternative: Explicit in annotation `@Projection<UserProfile>(...)`
   - Recommendation: Infer from `SingleStreamProjection<T>` generic—less duplication
