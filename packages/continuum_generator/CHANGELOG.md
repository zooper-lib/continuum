# Changelog

## 2.0.0 - 2026-01-08

### Breaking Changes

- **BREAKING**: Updated to work with continuum 2.0.0 breaking changes:
  - Generator now looks for `@AggregateEvent` instead of `@Event`
  - Generator now expects `of:` parameter instead of `ofAggregate:`
  - Generator now references `ContinuumEvent` base class instead of `DomainEvent`

### Other Changes

- Updated generator dependencies for `source_gen ^4.0.0` (including `analyzer` and `build`).
- Updated generator implementation for analyzer 8 API changes.

## 1.0.0

- Initial release with aggregate and event code generation.
