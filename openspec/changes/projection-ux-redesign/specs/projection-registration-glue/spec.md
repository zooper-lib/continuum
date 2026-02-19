## ADDED Requirements

### Requirement: Generator emits registration extension method

The code generator SHALL emit an extension method on `ProjectionRegistry` that registers all discovered projections in a single call.

The generated extension SHALL use named parameters — one parameter for each projection instance and one for each corresponding `ReadModelStore`. Parameter names SHALL be derived from the projection class name (camelCase).

#### Scenario: Generator discovers two projections and emits registerAll
- **WHEN** the generator discovers `UserProfileProjection` (inline, `SingleStreamProjection<UserProfile>`) and `OrderSummaryProjection` (async, `MultiStreamProjection<OrderSummary, CustomerId>`)
- **THEN** it SHALL emit an extension on `ProjectionRegistry` with a `registerAll` method requiring named parameters: `userProfileProjection`, `userProfileStore`, `orderSummaryProjection`, `orderSummaryStore`
- **THEN** the generated method body SHALL call `registerGeneratedInline` for inline projections and `registerGeneratedAsync` for async projections

#### Scenario: Generator emits correct store type parameters
- **WHEN** a projection `UserProfileProjection` extends `SingleStreamProjection<UserProfile>`
- **THEN** the generated store parameter type SHALL be `ReadModelStore<UserProfile, StreamId>`

#### Scenario: Generator emits correct store type for multi-stream projections
- **WHEN** a projection `OrderSummaryProjection` extends `MultiStreamProjection<OrderSummary, CustomerId>`
- **THEN** the generated store parameter type SHALL be `ReadModelStore<OrderSummary, CustomerId>`

### Requirement: Generated registration respects projection lifecycle

The generated `registerAll` method SHALL use the lifecycle declared in the `@Projection` annotation (or detected by the generator) to call the correct registration method.

#### Scenario: Inline projection registered via registerGeneratedInline
- **WHEN** a projection is marked as inline lifecycle
- **THEN** `registerAll` SHALL call `registerGeneratedInline` for that projection

#### Scenario: Async projection registered via registerGeneratedAsync
- **WHEN** a projection is marked as async lifecycle
- **THEN** `registerAll` SHALL call `registerGeneratedAsync` for that projection

### Requirement: Generated registration passes GeneratedProjection bundles

The generated `registerAll` method SHALL pass the corresponding `GeneratedProjection` bundle (containing `projectionName`, `schemaHash`, and `handledEventTypes`) when calling `registerGeneratedInline` or `registerGeneratedAsync`.

#### Scenario: GeneratedProjection bundle passed during registration
- **WHEN** `registerAll` registers a projection
- **THEN** it SHALL pass the generated `GeneratedProjection` bundle as the first argument to `registerGeneratedInline` or `registerGeneratedAsync`

### Requirement: Single registerAll call replaces per-projection wiring

After using the generated `registerAll` extension, the user SHALL NOT need to call individual `registerInline`, `registerAsync`, `registerGeneratedInline`, or `registerGeneratedAsync` methods for any projection discovered by the generator.

#### Scenario: All discovered projections registered in one call
- **WHEN** the user calls `registry.registerAll(...)` with all required projection instances and stores
- **THEN** all discovered projections SHALL be registered with the correct lifecycle, bundle, and store
- **THEN** `registry.length` SHALL equal the number of discovered projections
