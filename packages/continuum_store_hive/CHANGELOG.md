# Changelog

## 2.0.0 - 2026-01-08

### Breaking Changes

- **BREAKING**: Updated to work with continuum 2.0.0 breaking changes:
  - Now uses `ContinuumSession` instead of `Session`
  - Now uses `ContinuumEvent` instead of `DomainEvent`

## 1.0.0

- Initial release with Hive-backed EventStore implementation.
- Added support for atomic multi-stream appends via `AtomicEventStore` using a transaction log.
