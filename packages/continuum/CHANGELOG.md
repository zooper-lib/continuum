# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Breaking Changes

- **BREAKING**: Creation events must now be marked explicitly via `@AggregateEvent(creation: true)`.

## [3.2.0] - 2026-01-14

### Added

- Added a custom lint rule that reports when a non-abstract `@Aggregate()` class mixes in the generated `_$<Aggregate>EventHandlers` but does not implement all required `apply<Event>(...)` methods.
- Added a Quick Fix action to implement missing `apply<Event>(...)` handler stubs.
- Added a runnable example package under `example/` showing the lint in action.

## [3.1.1] - 2026-01-13

### Fixed

- Aggregate event discovery now scans all libraries in the package, so mutation apply methods and dispatch cases are generated even when the aggregate library does not import the event library (the aggregate still must import the event type for compilation).

## [3.1.0] - 2026-01-13

### Added

- Added an example demonstrating code generation for `abstract class` and `abstract interface class` aggregates.

### Fixed

- Combining builder now skips non-library Dart files (e.g. `*.freezed.dart` part files) when scanning `lib/`, preventing build failures in apps using Freezed.

## [3.0.1] - 2026-01-12

### Changed

- Bump `zooper_flutter_core` to `^1.0.3`.

## [3.0.0] - 2026-01-12

### Breaking Changes

- **BREAKING**: `ContinuumEvent` now implements `ZooperDomainEvent` for better integration with other Zooper packages.

### Fixed

- `JsonEventSerializer.deserialize` now always includes a `metadata` key (empty when no stored metadata) in the payload passed to `fromJson`.
- Code generation now emits `ContinuumEvent` for `applyEvent(...)`, `replayEvents(...)`, and `createFromEvent(...)` (instead of the non-existent `DomainEvent`).

## [2.0.0] - 2026-01-08

### Breaking Changes

- **BREAKING**: Renamed `@Event` annotation to `@AggregateEvent` to avoid naming conflicts with user code.
- **BREAKING**: Renamed `ofAggregate:` parameter to `of:` in `@AggregateEvent` annotation.
- **BREAKING**: Renamed `DomainEvent` class to `ContinuumEvent` to avoid naming conflicts.
- **BREAKING**: Renamed `Session` interface to `ContinuumSession` to avoid naming conflicts.
- **BREAKING**: Renamed `StoredEvent.fromDomainEvent()` to `StoredEvent.fromContinuumEvent()`.
- **BREAKING**: Updated all parameter names from `domainEvent` to `continuumEvent`.

### Other Changes

- Updated generator implementation for analyzer 8 API changes.
- Updated generator dependencies for `source_gen ^4.0.0` (including `analyzer` and `build`).

## [1.0.0]

- Initial release with event sourcing core functionality.
- Added `@Aggregate()` and `@Event()` annotations for code generation.
- Added strong types: `EventId`, `StreamId`.
- Added persistence interfaces and store implementations.
- Added exception types for error handling.
