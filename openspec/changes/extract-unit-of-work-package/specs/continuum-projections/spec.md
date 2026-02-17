## MODIFIED Requirements

### Requirement: Projection abstraction
The system SHALL provide a `Projection` abstraction that defines how events mutate a read model. This type SHALL move from the `continuum` package to the `continuum_es` package.

#### Scenario: Projection available from continuum_es
- **WHEN** a consumer imports `package:continuum_es/continuum_es.dart`
- **THEN** `Projection` and all projection-related types SHALL be available

#### Scenario: Projection removed from continuum
- **WHEN** inspecting the `continuum` package barrel file
- **THEN** it SHALL NOT export any projection types

### Requirement: All projection types move to continuum_es

`SingleStreamProjection`, `MultiStreamProjection`, `ProjectionRegistry`, `InlineProjectionExecutor`, `AsyncProjectionExecutor`, `ProjectionProcessor`, `ReadModelStore`, `ProjectionPositionStore`, `ProjectionPosition`, `ProjectionLifecycle`, `ProjectionRegistration`, `ReadModelResult`, `GeneratedProjection`, and `ProjectionEventStore` SHALL all move from the `continuum` package to the `continuum_es` package.

#### Scenario: Projection types removed from continuum barrel
- **WHEN** inspecting the `continuum` package barrel file after migration
- **THEN** it SHALL NOT export `SingleStreamProjection`, `MultiStreamProjection`, `ProjectionRegistry`, `InlineProjectionExecutor`, `AsyncProjectionExecutor`, `ProjectionProcessor`, `ReadModelStore`, `ProjectionPositionStore`, `ProjectionPosition`, `ProjectionLifecycle`, `ProjectionRegistration`, `ReadModelResult`, `GeneratedProjection`, or `ProjectionEventStore`

#### Scenario: All projection types available from continuum_es
- **WHEN** a consumer imports `package:continuum_es/continuum_es.dart`
- **THEN** all projection types listed above SHALL be available

### Requirement: EventSourcingStore projection integration
The system SHALL integrate projections into `EventSourcingStore` configuration. This integration remains in the `continuum_es` package.

#### Scenario: Configure store with projections
- **GIVEN** an `EventSourcingStore` factory call with projection registry
- **WHEN** the store is created
- **THEN** sessions from this store automatically execute inline projections

#### Scenario: Store without projections works unchanged
- **GIVEN** an `EventSourcingStore` factory call without projection registry
- **WHEN** sessions append events
- **THEN** no projection processing occurs

### Requirement: @Projection annotation stays in continuum core

The `@Projection` annotation SHALL remain in the `continuum` core package since it is used by `continuum_generator` for code generation discovery.

#### Scenario: @Projection annotation available from continuum
- **WHEN** a consumer imports `package:continuum/continuum.dart`
- **THEN** the `@Projection` annotation SHALL be available
