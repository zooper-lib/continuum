## MODIFIED Requirements

### Requirement: TransientAdapterException for transient backend failures

The system SHALL provide a `TransientAdapterException` class that represents transient backend failures. It SHALL move from the `continuum` package to the `continuum_state` package.

#### Scenario: TransientAdapterException construction
- **WHEN** a `TransientAdapterException` is created with message and cause
- **THEN** it SHALL have `message` and `cause` fields accessible

#### Scenario: TransientAdapterException removed from continuum
- **WHEN** inspecting the `continuum` package barrel file
- **THEN** it SHALL NOT export `TransientAdapterException`

#### Scenario: TransientAdapterException available from continuum_state
- **WHEN** a consumer imports `package:continuum_state/continuum_state.dart`
- **THEN** `TransientAdapterException` SHALL be available

### Requirement: PermanentAdapterException for permanent backend failures

The system SHALL provide a `PermanentAdapterException` class that represents permanent backend failures. It SHALL move from the `continuum` package to the `continuum_state` package.

#### Scenario: PermanentAdapterException construction
- **WHEN** a `PermanentAdapterException` is created with a message
- **THEN** the `message` field SHALL be accessible

#### Scenario: PermanentAdapterException removed from continuum
- **WHEN** inspecting the `continuum` package barrel file
- **THEN** it SHALL NOT export `PermanentAdapterException`

#### Scenario: PermanentAdapterException available from continuum_state
- **WHEN** a consumer imports `package:continuum_state/continuum_state.dart`
- **THEN** `PermanentAdapterException` SHALL be available

### Requirement: PartialSaveException moves to continuum_uow

`PartialSaveException` SHALL move from the `continuum` package to the `continuum_uow` package, as it is a session-level concern applicable to any persistence strategy.

#### Scenario: PartialSaveException removed from continuum
- **WHEN** inspecting the `continuum` package barrel file
- **THEN** it SHALL NOT export `PartialSaveException`

#### Scenario: PartialSaveException available from continuum_uow
- **WHEN** a consumer imports `package:continuum_uow/continuum_uow.dart`
- **THEN** `PartialSaveException` SHALL be available

### Requirement: New exception types implement Exception

`TransientAdapterException`, `PermanentAdapterException`, and `PartialSaveException` SHALL all implement `Exception`. They SHALL be `final class` types. Their behavior is unchanged — only the package location changes.

#### Scenario: Exception type hierarchy unchanged
- **WHEN** inspecting the exception types
- **THEN** `TransientAdapterException`, `PermanentAdapterException`, and `PartialSaveException` SHALL each be a `final class` that `implements Exception`

## REMOVED Requirements

### Requirement: New exceptions are exported from barrel file

**Reason**: These exception types move to their respective packages (`continuum_uow` for `PartialSaveException`, `continuum_state` for adapter exceptions). They are no longer exported from `continuum.dart`.
**Migration**: Import `PartialSaveException` from `package:continuum_uow/continuum_uow.dart`. Import `TransientAdapterException` and `PermanentAdapterException` from `package:continuum_state/continuum_state.dart`.
