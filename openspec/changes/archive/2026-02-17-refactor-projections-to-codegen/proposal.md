# Change: Refactor Projections to Use Code Generation

## Why

The current projection implementation requires users to manually write boilerplate code that violates Continuum's core philosophy: **use code generation to eliminate repetitive patterns**.

### Current Pain Points

1. **Manual `handledEventTypes` declaration**: Users must manually maintain a `Set<Type>` that lists every event they handle—easy to forget when adding new handlers.

2. **Manual `apply()` dispatcher**: Users write a large switch statement inside `apply()` to route events—the exact pattern the aggregate generator already automates.

3. **No annotation-based discovery**: Events are not linked to projections via annotations, so the generator cannot assist.

4. **Inconsistent developer experience**: Aggregates get generated mixins, dispatchers, and registries; projections get nothing.

### Comparison

| Aspect | Aggregates (current) | Projections (current) |
|--------|---------------------|----------------------|
| Event handlers | `apply<EventName>(event)` methods | Manual switch in single `apply()` |
| Event registration | Auto-discovered via `@AggregateEvent` | Manual `handledEventTypes` set |
| Dispatch boilerplate | Generated | Hand-written |
| Lint support | `continuum_missing_apply_handlers` | None |

The projection system should follow the same ergonomic pattern as aggregates.

## What Changes

### Core Annotation Changes

- **ADDED**: `@Projection()` annotation to mark projection classes
- **ADDED**: `@ProjectionEvent()` annotation to link events to projections (similar to `@AggregateEvent`)
- **MODIFIED**: Projection base classes simplified—no longer require manual `handledEventTypes` override

### Code Generation Changes

- **ADDED**: Generator discovers `@Projection` classes and `@ProjectionEvent` annotations
- **ADDED**: Generator emits `_$<Projection>EventHandlers` mixin (requires `apply<EventName>` methods)
- **ADDED**: Generator emits `applyEvent()` dispatcher extension for projections
- **ADDED**: Generator emits `$projectionList` global list (like `$aggregateList`)
- **ADDED**: Generator emits projection registration helpers with auto-discovered event types

### Runtime Changes

- **MODIFIED**: `ProjectionRegistry` accepts generated projection bundles
- **REMOVED**: Manual `handledEventTypes` getter from user code (generated instead)

### Lint Support

- **ADDED**: `continuum_missing_projection_handlers` lint rule
- **ADDED**: Quick-fix to generate missing `apply<EventName>` methods

## Target Developer Experience

### Before (current painful approach)

```dart
class UserProfileProjection extends SingleStreamProjection<UserProfile> {
  @override
  Set<Type> get handledEventTypes => {UserRegistered, EmailChanged, NameChanged};

  @override
  String get projectionName => 'user-profile';

  @override
  UserProfile createInitial(StreamId streamId) =>
      UserProfile(id: streamId.value);

  @override
  UserProfile apply(UserProfile current, StoredEvent event) {
    return switch (event.payload) {
      UserRegistered e => current.copyWith(name: e.name, email: e.email),
      EmailChanged e => current.copyWith(email: e.newEmail),
      NameChanged e => current.copyWith(name: e.newName),
      _ => current,
    };
  }
}
```

### After (code-generated approach)

```dart
part 'user_profile_projection.g.dart';

@Projection(name: 'user-profile', events: [UserRegistered, EmailChanged, NameChanged])
class UserProfileProjection extends SingleStreamProjection<UserProfile>
    with _$UserProfileProjectionHandlers {

  @override
  UserProfile createInitial(StreamId streamId) =>
      UserProfile(id: streamId.value);

  // Generated mixin requires these handlers; Dart compiler enforces implementation:

  @override
  UserProfile applyUserRegistered(UserProfile current, UserRegistered event) =>
      current.copyWith(name: event.name, email: event.email);

  @override
  UserProfile applyEmailChanged(UserProfile current, EmailChanged event) =>
      current.copyWith(email: event.newEmail);

  @override
  UserProfile applyNameChanged(UserProfile current, NameChanged event) =>
      current.copyWith(name: event.newName);
}
```

The `events` list in the annotation tells the generator which handlers to require. The generator creates the mixin with abstract `apply<EventName>` methods. The Dart compiler then enforces that the user implements all handlers.

## Impact

- Affected specs: `continuum-projections` (to be created or updated)
- Affected code:
  - `packages/continuum/lib/src/annotations/` — new annotations
  - `packages/continuum/lib/src/projections/` — simplified base classes
  - `packages/continuum_generator/lib/src/` — projection discovery and emission
  - `packages/continuum_lints/lib/src/` — new lint rules
- Breaking changes: **YES** — projection API changes (but feature is new, so limited impact)
- Migration: Existing manual projections need refactoring to annotation-based approach

## Open Questions

1. **Read model type inference**: Should the read model type be inferred from the base class generic parameter, or explicitly declared in the annotation?
   - **Recommendation**: Infer from `SingleStreamProjection<T>` generic—less duplication

2. **Multi-stream key extraction**: How should multi-stream projections declare their key extraction logic? This cannot be generated.
   - **Recommendation**: Keep `extractKey()` as user-implemented; only generate dispatch

3. **Projection bundle structure**: What should `$UserProfileProjection` contain?
   - Event type set (for registry)
   - Factory for creating projection instances?
   - **Recommendation**: Similar to `GeneratedAggregate` but simpler
