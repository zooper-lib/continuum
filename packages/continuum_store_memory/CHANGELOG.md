# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

# Changelog

## [2.0.0] - 2026-01-08

### Breaking Changes

- **BREAKING**: Updated to work with continuum 2.0.0 breaking changes:
  - Now uses `ContinuumSession` instead of `Session`
  - Now uses `ContinuumEvent` instead of `DomainEvent`

## [1.0.0]

- Initial release with in-memory EventStore implementation.
- Added support for atomic multi-stream appends via `AtomicEventStore`.
