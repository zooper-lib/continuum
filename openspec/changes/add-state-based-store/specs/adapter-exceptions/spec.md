## ADDED Requirements

### Requirement: TransientAdapterException for transient backend failures

The system SHALL provide a `TransientAdapterException` class that represents transient backend failures (network timeouts, 503 Service Unavailable, rate limits). It SHALL have a `message` field of type `String` and an optional `cause` field of type `Object?`.

#### Scenario: TransientAdapterException construction
- **WHEN** a `TransientAdapterException` is created with message `'Connection timed out'` and cause `SocketException`
- **THEN** it SHALL have `message == 'Connection timed out'` and `cause` equal to the `SocketException` instance

#### Scenario: Session rethrows TransientAdapterException
- **WHEN** `adapter.persistAsync` throws `TransientAdapterException`
- **THEN** the session SHALL rethrow it immediately without retrying — the caller decides whether to retry the whole workflow

#### Scenario: Session rethrows TransientAdapterException from fetchAsync
- **WHEN** `adapter.fetchAsync` throws `TransientAdapterException`
- **THEN** the session SHALL rethrow it immediately to the caller

### Requirement: PermanentAdapterException for permanent backend failures

The system SHALL provide a `PermanentAdapterException` class that represents permanent backend failures (400 Bad Request, 403 Forbidden, validation errors). It SHALL have a `message` field of type `String` and an optional `cause` field of type `Object?`.

#### Scenario: PermanentAdapterException construction
- **WHEN** a `PermanentAdapterException` is created with message `'Validation failed: email format invalid'`
- **THEN** it SHALL have `message == 'Validation failed: email format invalid'`

#### Scenario: Session rethrows PermanentAdapterException
- **WHEN** `adapter.persistAsync` throws `PermanentAdapterException`
- **THEN** the session SHALL rethrow it immediately without retrying

#### Scenario: Session rethrows PermanentAdapterException from fetchAsync
- **WHEN** `adapter.fetchAsync` throws `PermanentAdapterException`
- **THEN** the session SHALL rethrow it immediately to the caller

### Requirement: PartialSaveException for multi-stream partial failures

The system SHALL provide a `PartialSaveException` class thrown when `saveChangesAsync` persists multiple streams and some succeed while others fail. It SHALL have `savedStreams` (`List<StreamId>`), `failedStreams` (`List<StreamId>`), and `cause` (`Object`) fields.

#### Scenario: PartialSaveException construction
- **WHEN** a `PartialSaveException` is created with `savedStreams: [userStreamId]`, `failedStreams: [playlistStreamId]`, and `cause: someException`
- **THEN** it SHALL contain the correct stream ID lists and the original cause

#### Scenario: PartialSaveException is not thrown for single-stream saves
- **WHEN** `saveChangesAsync()` is called with only one stream having pending events and `persistAsync` throws
- **THEN** the session SHALL rethrow the original exception directly, NOT wrap it in `PartialSaveException`

#### Scenario: PartialSaveException is not thrown when all streams fail
- **WHEN** `saveChangesAsync()` is called with multiple streams and all `persistAsync` calls fail
- **THEN** the session SHALL throw the exception from the first failure, NOT a `PartialSaveException` with empty `savedStreams`

### Requirement: ConcurrencyException triggers retry in state-based session

The existing `ConcurrencyException` SHALL trigger the same reload-and-retry behavior in `StateBasedSession` as it does in `SessionImpl`. The session SHALL catch `ConcurrencyException` from `adapter.persistAsync`, re-fetch the aggregate via `adapter.fetchAsync`, re-apply pending events, and retry.

#### Scenario: ConcurrencyException caught and retried
- **WHEN** `adapter.persistAsync` throws `ConcurrencyException` and `maxRetries > 0`
- **THEN** the session SHALL call `adapter.fetchAsync` to get the latest state, re-apply all pending events, and call `adapter.persistAsync` again

#### Scenario: ConcurrencyException rethrown after max retries
- **WHEN** `adapter.persistAsync` throws `ConcurrencyException` on every attempt including the last retry
- **THEN** the session SHALL rethrow the `ConcurrencyException`

### Requirement: Unknown exceptions propagate unchanged

When `adapter.persistAsync` or `adapter.fetchAsync` throws an exception that is not `ConcurrencyException`, `StreamNotFoundException`, `TransientAdapterException`, or `PermanentAdapterException`, the session SHALL let it propagate unchanged.

#### Scenario: Raw HttpException propagates
- **WHEN** `adapter.persistAsync` throws an `HttpException` (not in the known hierarchy)
- **THEN** the session SHALL rethrow the `HttpException` as-is without wrapping or catching it

### Requirement: New exception types implement Exception

`TransientAdapterException`, `PermanentAdapterException`, and `PartialSaveException` SHALL all implement `Exception` (not `Error`). They SHALL be `final class` types.

#### Scenario: Exception type hierarchy
- **WHEN** inspecting the exception types
- **THEN** `TransientAdapterException`, `PermanentAdapterException`, and `PartialSaveException` SHALL each be a `final class` that `implements Exception`

### Requirement: New exceptions are exported from barrel file

`TransientAdapterException`, `PermanentAdapterException`, and `PartialSaveException` SHALL be exported from the `continuum.dart` barrel file.

#### Scenario: Import from barrel file
- **WHEN** a consumer imports `package:continuum/continuum.dart`
- **THEN** `TransientAdapterException`, `PermanentAdapterException`, and `PartialSaveException` SHALL be available
