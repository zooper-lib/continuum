## MODIFIED Requirements

### Requirement: Discover aggregates and events
The system SHALL discover aggregates and events by scanning `@Aggregate()` and `@AggregateEvent(of: ...)` annotations. No change to discovery behavior.

The system SHALL classify an event as a creation event if and only if the event annotation has `creation: true`. No change to classification behavior.

#### Scenario: Building mappings for an aggregate
- **GIVEN** an aggregate `A` and multiple events annotated as belonging to `A`
- **WHEN** the generator runs
- **THEN** it builds a mapping of creation events and mutation events for `A` based on each event's `creation` flag

### Requirement: Generated code imports remain valid

Generated code SHALL reference `AggregateFactoryRegistry`, `EventApplierRegistry`, and `EventApplicationMode` from `package:continuum/continuum.dart`. These types remain in the `continuum` core package and SHALL NOT move.

#### Scenario: Generated registry references compile
- **WHEN** `continuum_generator` emits code referencing `AggregateFactoryRegistry` and `EventApplierRegistry`
- **THEN** the generated imports SHALL point to `package:continuum/continuum.dart` and SHALL compile

### Requirement: Generated projection code imports from continuum_es

If the generator emits code referencing projection types (e.g., `GeneratedProjection`, projection registration types), those imports SHALL point to `package:continuum_es/continuum_es.dart` since projection types move to the `continuum_es` package.

#### Scenario: Projection imports updated
- **WHEN** `continuum_generator` emits projection-related code
- **THEN** the generated imports SHALL reference `package:continuum_es/continuum_es.dart` for projection types

#### Scenario: Non-projection generated code unchanged
- **WHEN** `continuum_generator` emits aggregate factory and applier code
- **THEN** the generated imports SHALL remain `package:continuum/continuum.dart`
