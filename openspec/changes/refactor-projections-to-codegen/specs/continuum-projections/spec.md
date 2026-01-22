# Capability: Continuum Projections (Code-Generated)

This capability specifies the code-generated projection system for building read models from events.

---

## ADDED Requirements

### Requirement: Projection Annotation

The system SHALL provide a `@Projection()` annotation to mark classes as projections.

The annotation SHALL accept:
- A required `name` parameter that uniquely identifies the projection for position tracking
- A required `events` parameter that lists the event types this projection handles

#### Scenario: Annotating a single-stream projection

- **GIVEN** a user creates a class extending `SingleStreamProjection`
- **WHEN** the user annotates the class with `@Projection(name: 'user-profile', events: [UserRegistered, EmailChanged])`
- **THEN** the code generator SHALL discover the class as a projection
- **AND** SHALL use `'user-profile'` as the projection name
- **AND** SHALL generate handlers for `UserRegistered` and `EmailChanged`

#### Scenario: Annotating a multi-stream projection

- **GIVEN** a user creates a class extending `MultiStreamProjection`
- **WHEN** the user annotates the class with `@Projection(name: 'library-stats', events: [AudioFileAdded, AudioFileRemoved])`
- **THEN** the code generator SHALL discover the class as a projection
- **AND** SHALL use `'library-stats'` as the projection name
- **AND** SHALL generate handlers for `AudioFileAdded` and `AudioFileRemoved`

---

### Requirement: Events List Discovery

The system SHALL read the `events` parameter from the `@Projection` annotation to determine which event handlers to generate.

For each event type in the `events` list, the generator SHALL create an abstract `apply<EventName>` method in the generated mixin.

#### Scenario: Generating handlers from events list

- **GIVEN** a projection annotated with `@Projection(name: 'user-profile', events: [UserRegistered, EmailChanged])`
- **WHEN** the code generator processes the projection
- **THEN** it SHALL generate mixin `_$UserProfileProjectionHandlers`
- **AND** the mixin SHALL contain abstract methods `applyUserRegistered` and `applyEmailChanged`
- **AND** the Dart compiler SHALL enforce implementation of these methods

#### Scenario: Empty events list

- **GIVEN** a projection annotated with `@Projection(name: 'empty', events: [])`
- **WHEN** the code generator processes the projection
- **THEN** it SHALL generate an empty mixin with no required handlers
- **AND** the generated `handledEventTypes` set SHALL be empty

---

### Requirement: Generated Event Handlers Mixin

The system SHALL generate a `_$<ProjectionName>Handlers` mixin for each projection based on the `events` list in the annotation.

The mixin SHALL declare:
- An abstract `createInitial(TKey key)` method to initialize the read model
- Abstract `apply<EventName>` methods for each event type in the `events` list

Each generated handler method SHALL:
- Return the read model type `TReadModel`
- Accept two parameters: `TReadModel current` and the typed event

#### Scenario: Mixin generation with createInitial and handlers

- **GIVEN** a projection `UserProfileProjection` annotated with `events: [UserRegistered, EmailChanged, NameChanged]`
- **AND** the projection extends `SingleStreamProjection<UserProfile>`
- **WHEN** the code generator runs
- **THEN** it SHALL generate mixin `_$UserProfileProjectionHandlers`
- **AND** the mixin SHALL contain:
  - `UserProfile createInitial(StreamId streamId)`
  - `UserProfile applyUserRegistered(UserProfile current, UserRegistered event)`
  - `UserProfile applyEmailChanged(UserProfile current, EmailChanged event)`
  - `UserProfile applyNameChanged(UserProfile current, NameChanged event)`

#### Scenario: Compile-time enforcement of all methods

- **GIVEN** a projection class mixes in `_$<Name>Handlers`
- **WHEN** the projection class does not implement `createInitial` or any required handler
- **THEN** Dart compilation SHALL fail with missing method errors

---

### Requirement: Generated Event Dispatcher

The system SHALL generate a `$<ProjectionName>EventDispatch` extension for each projection.

The extension SHALL provide:
- A static `handledEventTypes` set containing all handled event types
- An `applyEvent()` method that dispatches events to typed handlers

#### Scenario: Dispatcher routes events to correct handlers

- **GIVEN** a projection with handler `applyEmailChanged`
- **WHEN** `applyEvent(currentState, EmailChanged(...))` is called
- **THEN** it SHALL invoke `applyEmailChanged(currentState, event)`
- **AND** SHALL return the handler's result

#### Scenario: Dispatcher throws on unhandled events

- **GIVEN** a projection that handles `EmailChanged` but not `NameChanged`
- **WHEN** `applyEvent(currentState, NameChanged(...))` is called
- **THEN** it SHALL throw `UnsupportedEventException`
- **AND** the exception SHALL identify the event type and projection type

---

### Requirement: Generated Projection Bundle

The system SHALL generate a `$<ProjectionName>` constant for each projection containing:
- The projection name (string)
- The set of handled event types
- Optionally, a factory function to create projection instances

#### Scenario: Projection bundle generation

- **GIVEN** a projection `UserProfileProjection` with name `'user-profile'`
- **WHEN** the code generator runs
- **THEN** it SHALL generate constant `$UserProfileProjection`
- **AND** `$UserProfileProjection.projectionName` SHALL equal `'user-profile'`
- **AND** `$UserProfileProjection.handledEventTypes` SHALL contain all discovered event types

---

### Requirement: Generated Schema Hash

The system SHALL generate a `schemaHash` for each projection, computed from the sorted event type names.

The schema hash SHALL be included in the generated projection bundle.

#### Scenario: Schema hash generation

- **GIVEN** a projection annotated with `events: [UserRegistered, EmailChanged]`
- **WHEN** the code generator runs
- **THEN** it SHALL compute a hash from the sorted event type names
- **AND** `$UserProfileProjection.schemaHash` SHALL contain the computed hash

#### Scenario: Schema hash changes when events list changes

- **GIVEN** a projection previously had `events: [UserRegistered, EmailChanged]`
- **WHEN** the user changes it to `events: [UserRegistered, EmailChanged, NameChanged]`
- **AND** the code generator runs
- **THEN** the new `schemaHash` SHALL differ from the previous hash

---

### Requirement: Schema Change Detection on Startup

The system SHALL detect schema changes by comparing the generated `schemaHash` with the stored schema hash in the position store.

On schema mismatch, the system SHALL:
1. Mark the projection as stale
2. Clear the read model store for the projection
3. Reset the position to 0
4. Start a background rebuild (non-blocking)

#### Scenario: Schema change triggers rebuild

- **GIVEN** a projection with stored `schemaHash: 'abc123'`
- **AND** the generated bundle has `schemaHash: 'def456'`
- **WHEN** the projection system initializes
- **THEN** the system SHALL log that the schema changed
- **AND** SHALL clear the read model store for this projection
- **AND** SHALL reset the position to 0
- **AND** SHALL start a background rebuild

#### Scenario: No schema change continues normally

- **GIVEN** a projection with stored `schemaHash: 'abc123'`
- **AND** the generated bundle has `schemaHash: 'abc123'`
- **WHEN** the projection system initializes
- **THEN** the system SHALL continue processing from the stored position
- **AND** SHALL NOT clear the read model store

---

### Requirement: Read Model Result with Staleness Flag

The read model store SHALL return results with a staleness indicator.

```dart
class ReadModelResult<T> {
  final T? value;
  final bool isStale;
}
```

#### Scenario: Reading during rebuild returns stale flag

- **GIVEN** a projection is rebuilding after schema change
- **WHEN** `loadAsync(key)` is called
- **THEN** it SHALL return `ReadModelResult(value: data, isStale: true)`

#### Scenario: Reading after rebuild completes returns fresh flag

- **GIVEN** a projection has completed rebuilding
- **WHEN** `loadAsync(key)` is called
- **THEN** it SHALL return `ReadModelResult(value: data, isStale: false)`

---

### Requirement: Non-Blocking Rebuild

The projection rebuild SHALL NOT block application startup.

Both single-stream and multi-stream projections SHALL use the same rebuild behavior:
- Background rebuild (non-blocking)
- Reads return available data with `isStale: true` until rebuild completes

#### Scenario: App starts immediately during rebuild

- **GIVEN** a projection requires a full rebuild
- **WHEN** the application starts
- **THEN** the application SHALL be usable immediately
- **AND** reads SHALL return stale data until rebuild completes

---

### Requirement: Global Projection List Generation

The system SHALL generate a `$projectionList` containing all projections discovered in the package.

#### Scenario: Combining multiple projections

- **GIVEN** a package contains `UserProfileProjection` and `UserStatisticsProjection`
- **WHEN** the combining builder runs
- **THEN** it SHALL generate `$projectionList` in `continuum.g.dart`
- **AND** `$projectionList` SHALL contain `$UserProfileProjection` and `$UserStatisticsProjection`

---

### Requirement: Lint Rule for Missing Handlers

The system SHALL provide a lint rule `continuum_missing_projection_handlers` that reports diagnostics when a projection class:
- Is annotated with `@Projection(events: [...])`
- Mixes in `_$<Name>Handlers`
- Does not implement one or more required handler methods declared in the generated mixin

#### Scenario: Lint reports missing handler

- **GIVEN** a projection annotated with `events: [EmailChanged, NameChanged]`
- **AND** the projection class only implements `applyEmailChanged`
- **WHEN** the lint rule analyzes the class
- **THEN** the lint SHALL report a diagnostic on the class
- **AND** the diagnostic message SHALL name the missing method `applyNameChanged`

#### Scenario: Lint provides quick-fix

- **GIVEN** the lint reports a missing handler `applyEmailChanged`
- **WHEN** the user invokes the quick-fix
- **THEN** a stub method SHALL be generated:
  ```dart
  @override
  UserProfile applyEmailChanged(UserProfile current, EmailChanged event) {
    // TODO: Implement handler
    throw UnimplementedError();
  }
  ```

---

## MODIFIED Requirements

### Requirement: Simplified Single-Stream Projection Base Class

The `SingleStreamProjection` base class SHALL NOT require users to override `handledEventTypes`.

The generated extension SHALL provide `handledEventTypes` instead.

#### Scenario: User defines single-stream projection

- **GIVEN** a user creates a class extending `SingleStreamProjection<UserProfile>`
- **WHEN** the user implements only `createInitial()` and `apply<EventName>` handlers
- **THEN** the projection SHALL compile and function correctly
- **AND** the user SHALL NOT be required to override `handledEventTypes`

---

### Requirement: Simplified Multi-Stream Projection Base Class

The `MultiStreamProjection` base class SHALL NOT require users to override `handledEventTypes`.

The user SHALL still be required to override `extractKey()` (domain-specific logic).

#### Scenario: User defines multi-stream projection

- **GIVEN** a user creates a class extending `MultiStreamProjection<LibraryStats, String>`
- **WHEN** the user implements `extractKey()`, `createInitial()`, and `apply<EventName>` handlers
- **THEN** the projection SHALL compile and function correctly
- **AND** the user SHALL NOT be required to override `handledEventTypes`

---

### Requirement: Registry Accepts Generated Bundles

The `ProjectionRegistry` SHALL accept `GeneratedProjection` bundles for registration.

#### Scenario: Registering generated projections

- **GIVEN** a `ProjectionRegistry` instance
- **WHEN** the user calls `registry.registerInline($UserProfileProjection, readModelStore)`
- **THEN** the registry SHALL register the projection with its generated metadata
- **AND** the registry SHALL route events based on `handledEventTypes` from the bundle

---

## REMOVED Requirements

### Requirement: Manual `handledEventTypes` Override

**Reason**: The generator now produces `handledEventTypes` from discovered handler methods.

**Migration**: Remove `@override Set<Type> get handledEventTypes => {...}` from projection classes. The generated extension provides this automatically.

---

### Requirement: Manual `apply()` Dispatcher Override

**Reason**: The generator produces `applyEvent()` dispatcher extension.

**Migration**: Remove the `@override TReadModel apply(...)` method with its switch statement. Instead, implement individual `apply<EventName>` methods and use the generated `applyEvent()` dispatcher.
