# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added a custom lint rule that reports when a non-abstract `@Aggregate()` class mixes in the generated `_$<Aggregate>EventHandlers` but does not implement all required `apply<Event>(...)` methods.
- Added a runnable example package under `example/` showing the lint in action.
