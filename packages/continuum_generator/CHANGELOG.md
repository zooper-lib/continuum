# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Breaking Changes

- **BREAKING**: `ContinuumEvent` is now implementing `ZooperDomainEvent` for better integration with other Zooper packages.

### Fixed

- `JsonEventSerializer.deserialize` now always includes a `metadata` key (empty when no stored metadata) in the payload passed to `fromJson`.

## [2.0.0] - 2026-01-08

### Breaking Changes

- **BREAKING**: Updated to work with continuum 2.0.0 breaking changes:
  - Generator now looks for `@AggregateEvent` instead of `@Event`
  - Generator now expects `of:` parameter instead of `ofAggregate:`
  - Generator now references `ContinuumEvent` base class instead of `DomainEvent`

### Other Changes

- Updated generator dependencies for `source_gen ^4.0.0` (including `analyzer` and `build`).
- Updated generator implementation for analyzer 8 API changes.

## [1.0.0]

- Initial release with aggregate and event code generation.
