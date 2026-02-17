## ADDED Requirements

### Requirement: README documents StateBasedStore construction
The README SHALL contain a "State-Based Store" section under "Core Concepts" that shows how to construct a `StateBasedStore` with an adapter map and `$aggregateList`.

#### Scenario: User reads State-Based Store section
- **WHEN** a user reads the "Core Concepts" section of the README
- **THEN** they find a "State-Based Store" subsection placed after the "Event Sourcing Store" subsection
- **THEN** the section shows a construction snippet with `StateBasedStore(adapters: {...}, aggregates: $aggregateList)`
- **THEN** the section explains that each aggregate type maps to an `AggregatePersistenceAdapter` implementation

### Requirement: README shows AggregatePersistenceAdapter implementation pattern
The README SHALL include a concrete adapter implementation example showing `fetchAsync` and `persistAsync` methods.

#### Scenario: User learns how to implement an adapter
- **WHEN** a user reads the "State-Based Store" section
- **THEN** they find a code block showing a class that implements `AggregatePersistenceAdapter<T>`
- **THEN** the example shows `fetchAsync` returning a constructed aggregate
- **THEN** the example shows `persistAsync` receiving a stream ID, aggregate, and pending events

### Requirement: README Mode 3 quick-start uses StateBasedStore
The README's "Mode 3: Hybrid with Backend" quick-start code snippet SHALL use `StateBasedStore` and `openSession()` instead of manual aggregate construction.

#### Scenario: User follows Mode 3 quick-start
- **WHEN** a user reads the "Use Your Aggregate → Mode 3" section
- **THEN** the code snippet shows constructing a `StateBasedStore` with an adapter
- **THEN** the code snippet shows `store.openSession()` → `applyAsync` → `saveChangesAsync`
- **THEN** the pattern is visibly parallel to the Mode 2 (Event Sourcing) snippet

### Requirement: Runnable state-based store example exists
A runnable example file SHALL exist at `example/lib/store_state_based.dart` demonstrating the full adapter → store → session → save flow.

#### Scenario: User runs the state-based store example
- **WHEN** a user runs `dart run store_state_based.dart` from the example directory
- **THEN** the example defines a fake adapter with simulated backend calls
- **THEN** the example constructs a `StateBasedStore` and opens a session
- **THEN** the example applies a creation event and a mutation event via `applyAsync`
- **THEN** the example calls `saveChangesAsync` and prints the committed events
- **THEN** the example loads the aggregate via `loadAsync` and prints its state

### Requirement: Example index lists state-based store example
The `example/main.dart` file SHALL list the new `store_state_based.dart` example.

#### Scenario: User reads example index
- **WHEN** a user runs `dart run main.dart` or reads `main.dart`
- **THEN** they see `store_state_based.dart` listed with a brief description
- **THEN** the listing appears under a "STATE-BASED PERSISTENCE" heading or alongside existing persistence examples
